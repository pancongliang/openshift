# OVN-Kubernetes (Local Gateway Mode) 网络通信深度解析

## 1. 节点网络接口概览

| 网卡名称 | 类型 / 作用 | IP / 网络范围 | 核心功能说明 |
| :--- | :--- | :--- | :--- |
| **`lo`** | 本地回环 | `127.0.0.1` | 节点自身基础回环 |
| **`ens33`** | 物理网卡 | 无 IP | 物理上行链路，作为 OVS 桥 `br-ex` 的从属端口 |
| **`br-ex`** | OVS 外部桥 | `10.184.134.82/24` | 节点管理 IP 所在地。负责集群外部通信（入站/出站） |
| **`br-int`** | OVS 内部桥 | OVN 逻辑网络 | **逻辑核心**。OVN 逻辑网络核心，所有 Pod veth 接入 |
| **`ovn-k8s-mp0`** | OVN 管理端口 | `10.128.0.2/23` | **Host ↔ OVN 枢纽**。宿主机与 OVN 逻辑网络的桥梁, 用于 Host 进程访问 Pod/Service |
| **`genev_sys_6081`** | Geneve 隧道接口 | Overlay 封装 | **跨节点（东西向）枢纽**。承载封装后的跨节点 Pod 通信 |

---

## 2. 内部通信：Pod to Pod

### 同节点 Pod 访问 (Intra-Node)
1. **接入**：流量从 `Pod A` 的 veth 进入 `br-int`。
2. **逻辑交换**：`br-int` 匹配 OpenFlow 流表，识别目标 MAC/IP 属于本地端口。
3. **交付**：流量直接转发至同节点的 Pod B。
4. **特征**：全程在 OVS 内核态完成，**不经过隧道，不经过宿主机网络栈**。
~~~
Pod A (ns) ── veth pair ──► br-int ── local switch ──► veth pair ──► Pod B
~~~

### 跨节点 Pod 访问 (Inter-Node)
1. **封装**：流量进入 `br-int`，匹配流表发现目标 Pod 在远端节点。
2. **隧道化**：流量被封装为 Geneve 报文，由 genev_sys_6081 发出。
3. **底层传输**：封装后的包通过物理网卡 ens33 发往目标节点 IP。
4. **解封**：目标节点收到 UDP 包后解封装，报文进入其 `br-int`，最终送达目标 Pod。
~~~
Pod A ──► br-int ──►  genev_sys_6081 ──► ens33 ──► 远端节点 ens33 ──► br-int ──► Pod B
~~~
---

## 3. Service 通信机制 (Distributed Load Balancing)
- **分布式**：LB 逻辑分布在每个节点的 `br-int` 中。
- **性能**：在 OVS Datapath 中直接进行 DNAT 转换，无需像 iptables 那样逐条匹配。
- **一致性**：无论流量从哪里进入，最终都由 OVN 流表统一处理后端选择。

---

## 4. 不同入口访问 Service 的流程
### Pod → Service (ClusterIP)
1. **请求**：Pod 发起 ClusterIP 请求，流量进入 `br-int`。
2. **DNAT**：OVN 逻辑流表立即执行 DNAT，将 ClusterIP 转换为后端某个 Pod IP。
3. **分发**：根据后端 Pod 位置（本地或远端），走同节点或跨节点转发路径。
~~~
Pod ──► br-int（DNAT：ClusterIP → Pod IP）──► 本地 Pod  OR  Geneve → 远端 Pod
  ↓
br-int
  ↓（DNAT：ClusterIP → Pod IP）
本地 Pod  OR  Geneve → 远端 Pod
~~~

### Host → Service (ClusterIP)
1. **路由**：宿主机内核路由表显示 ClusterIP 的下一跳为 `ovn-k8s-mp0`。
2. **进入 OVN**：流量经管理端口进入 `br-int`。
3. **LB 处理**：OVN 流表执行 DNAT，随后流程与 Pod 访问 Service 一致。
~~~
Host Process ──► ovn-k8s-mp0  ──► br-int (DNAT）──► 后端 Pod
~~~

### External → Service (NodePort)
1. **入站**：请求到达物理 IP 的 NodePort 端口，进入 `br-ex`。
2. **重定向**：`br-ex` 上的流表识别流量并将其推入 OVN 逻辑流表。
3. **双向 NAT**：
   - **DNAT**：转换为后端 Pod IP。
   - **SNAT**：通常会执行 SNAT（源 IP 改为节点网关 IP），以确保回程流量能正确路由回该节点进行反向转换。
4. **转发**：进入 `br-int` 发往目标 Pod。
~~~
External Client ──► ens33 ──► br-ex（NodePort 匹配） ──► OVN DNAT ──► br-int ──► Pod（本地 / Geneve）
~~~

### External → Service (LoadBalancer)
- **机制**：由 MetalLB 或外部 LB 将流量导向节点的 NodePort。
- **流程**：后续路径与 **NodePort** 完全一致。

---

## 5. HostNetwork Pod 的通信特性

### 访问 HostNetwork Pod
- **直连**：HostNetwork Pod 共享宿主机的网络命名空间，直接监听在 br-ex 的 IP 上。
- **行为**：外部访问该 Pod 与访问宿主机原生服务完全一致。

### HostNetwork Pod 发起访问
- **访问普通 IP**：流量直接通过宿主机路由表从 br-ex 发出，完全绕过 OVN。
- **访问 Service (ClusterIP)**：
  - 虽然 Pod 在宿主机网络栈，但其访问 ClusterIP 的流量会匹配到宿主机路由，进入 ovn-k8s-mp0
  - 依然由 OVN 执行负载均衡，确保了行为的统一

---

## 6. 核心总结
- **南北流量**（外部进出）：流量核心在 `br-ex` 与 OVN 逻辑网关的对接。
- **东西流量**（Pod 间）：主要在 br-int 内部或通过 genev_sys_6081 隧道。
- **管理桥梁**：ovn-k8s-mp0 是 Host 与 OVN Overlay 世界的唯一“传送门”。
