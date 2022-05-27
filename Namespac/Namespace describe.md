### OpenShift namespace describe


**Namespace：openshift-apiserver-operator**
~~~
openshift-apiserver-operator-84d7d978c5-dj95w   #<-- 安装和维护 openshift-apiserver
~~~

**Namespace：openshift-apiserver**
~~~
apiserver-66575ffdd7-2jdxt                      #<-- 验证和配置 OpenShift 资源的数据，例如project, route, template
~~~

**Namespace：openshift-authentication**
~~~
oauth-openshift-6fb548d946-8p4px                #<-- 用户从 OpenShift OAuth Server 请求 token 向 API 验证自己
~~~

**Namespace：openshift-authentication-operator**
~~~
authentication-operator-67f9d5d59c-mlhc4        #<-- 安装和维护 openshift-authentication
~~~

**Namespace：openshift-cloud-credential-operator**
~~~
cloud-credential-operator-5477ffdb97-vt7dp      #<-- 提供 AWS 和 Azure 等云提供商请求的权限
~~~

**Namespace：openshift-cluster-machine-approver**
~~~
machine-approver-58488dbb64-zbkjb               #<-- 管理CSR(Certificate Signing Request) 请求批准/拒绝和更新状态
~~~

**Namespace：openshift-cluster-node-tuning-operator**
~~~
cluster-node-tuning-operator-69cd7f55b4-85dwn   #<-- 以守护程序可以理解的格式将自定义调整规范传递给 Tuned 守护程序
tuned-24lm7                                     #<-- Tuned 守护程序将调整选项应用于节点
~~~

**Namespace：openshift-cluster-samples-operator**
~~~
cluster-samples-operator-5767d48cb7-nfgdv       #<-- 维护 image stream 和 template
~~~

**Namespace：openshift-cluster-storage-operator**
~~~
cluster-storage-operator-6c548f984b-8rjtm       #<-- 设置 OpenShift 集群级存储默认值并确保存在默认存储类
csi-snapshot-controller-7cbc9f746d-c5b79        #<-- 使用集群在特定时间点的存储卷状态（快照）配置新卷
csi-snapshot-webhook-6f78c74bf4-jvbrk           #<-- snapshot controller 通过 webhook 检查无效的快照对象
~~~

**Namespace：openshift-cluster-version**
~~~
cluster-version-operator-6fd879f59b-ljhmg       #<-- 检查 OpenShift 集群版本并设法升级到有效版本
~~~

**Namespace：openshift-config-operator**
~~~
openshift-config-operator-6d569957b5-qnfb9      #<-- 保存 OpenShift 集群标准设置
~~~

**Namespace：openshift-console**
~~~
console-75b59999f-6l4xg                         #<-- 提供用户可以访问的 Web 控制台
downloads-86588df886-4xwlg                      #<-- 通过 Web 控制台提供 CLI 工具下载
~~~

**Namespace：openshift-console-operator**
~~~
console-operator-5c6bf5789-84nsb                #<-- 安装和维护 Web 控制台
~~~

**Namespace：openshift-controller-manager**
~~~
controller-manager-dwtpj                       #<-- 监视 etcd 以了解 OpenShift 对象（例如project, route, template controller）的更改，然后使用 API 强制执行指定的状态
~~~

**Namespace：openshift-controller-manager-operator**
~~~
openshift-controller-manager-operator-5f856b96-ftkfj   #<-- 安装和维护CRD(Custom Resource Definition)
~~~

**Namespace：openshift-dns**
~~~
dns-default-4dntp                               #<-- 更新 /etc/resolv.conf 以回退到指定的 nameserver
node-resolver-zpfb4                             #<-- 将 Service IP/Port 放在每个节点上以进行resolv
~~~

**Namespace：openshift-dns-operator**
~~~
dns-operator-768f885646-cl8wq                   #<-- 部署和管理 CoreDNS 并使用它来发现基于 DNS 的服务
~~~

**Namespace：openshift-etcd**
~~~
etcd-master1.ocp4.example.net                   #<-- 用于在分布式系统或 machines 集群上共享设置、发现服务和协调调度程序的 key-value 存储
etcd-quorum-guard-7f7dd97d78-cctgq              #<-- 检查 ETCD 的状态以保持 quorum
revision-pruner-16-master1.ocp4.example.net     #<-- 管理安装在主机上的static Pod
~~~

**Namespace：openshift-etcd-operator**
~~~
etcd-operator-6b79444874-htwwg                  #<-- 自动化 etcd 集群扩展，并通过启用 etcd 监控和指标来简化灾难恢复过程
~~~

**Namespace：openshift-image-registry**
~~~
cluster-image-registry-operator-7b75cf85c-w9q4j #<-- 管理 registry 的所有配置，包括创建单个实例和存储 OpenShift registry
image-registry-94757f4cc-ffdtr                  #<-- 保存 OpenShift 内置的 image
node-ca-2wmn5                                   #<-- 管理 registry 连接的证书
~~~

**Namespace：openshift-ingress**
~~~
router-default-79fd86499d-7kjtm                 #<-- 从外部路由以访问 OpenShift 内的服务域
~~~

**Namespace：openshift-ingress-canary**
~~~
ingress-canary-2w9gj                            #<-- 验证默认入口控制器的端到端连接，为此，canary控制器创建一个测试应用程序、service 和canary route，一旦canary route被默认入口控制器接纳，canary控制器就会周期性地向canary route发送请求，并验证控制器是否得到响应[1]
~~~

**Namespace：openshift-ingress-operator**
~~~
ingress-operator-7b7c8f7456-d7hvz               #<-- 实现 IngressController API 并启用对 OpenShift 集群服务的外部访问的组件
~~~

**Namespace：openshift-insights**
~~~
insights-operator-688765dc7b-sf5vp              #<-- 识别与集群相关的问题并在控制台中显示最新结果
~~~

**Namespace：openshift-kube-apiserver**
~~~
kube-apiserver-master1.ocp4.example.net         #<-- 验证和配置 pod、 pods, services, replication controllers的数据。它还为集群的共享状态提供一个 focal
~~~

**Namespace： openshift-kube-apiserver-operator**
~~~
kube-apiserver-operator-6f475fdb7d-kqmcb        #<-- 管理和更新 Kubernetes API Server
~~~

**Namespace：openshift-kube-controller-manager**
~~~
kube-controller-manager-master1.ocp4.example.net #<--  监视 etcd 以了解对replication, namespace, service account controller 等对象的更改，然后使用 API 强制执行指定的状态。几个这样的进程一次创建一个具有 active leader 的集群
~~~

**Namespace：openshift-kube-controller-manager-operator**
~~~
kube-controller-manager-operator-64f9b8f8d4-zfz6p #<-- 管理和更新 Kubernetes 控制器管理器
~~~

**Namespace：openshift-kube-scheduler**
~~~
openshift-kube-scheduler-master1.ocp4.example.net #<-- Kubernetes 调度程序监视没有分配节点的新创建的 Pod，并选择最佳节点来托管 Pod
~~~

**Namespace：openshift-kube-scheduler-operator**
~~~
openshift-kube-scheduler-operator-8698d9f84-8fld8 #<-- 管理和更新 Kubernetes Scheduler
~~~

**Namespace：openshift-kube-storage-version-migrator**
~~~
migrator-64d4498fc5-2fp2q                         #<-- 将存储在 etcd 中的数据迁移到最新的存储版本
~~~

**Namespace：openshift-kube-storage-version-migrator-operator**
~~~
kube-storage-version-migrator-operator-75545cf695-qr2fr #<-- 管理 kube-storage-version-migrator（创建存储版本迁移请求，检测资源库版本更改，处理迁移等）
~~~

**Namespace：openshift-machine-api**
~~~
cluster-autoscaler-operator-68d4fdf48c-mn5wz      #<-- 管理 OpenShift Cluster Autoscaler 部署
cluster-baremetal-operator-754b95855c-s29cb       #<-- 部署所有必要的组件以便将 bare metal 配置为 worker 节点
machine-api-operator-5b49c547d6-dml7d             #<-- 管理扩展 Kubernetes API 的专用 CRD、controllers 和 RBAC 的生命周期
~~~

**Namespace：openshift-machine-config-operator**
~~~
machine-config-controller-79f997977d-ctd5j        #<-- 使用 MachineConfig 中定义的配置让 Machine 可以正常升级
machine-config-daemon-26p84                       #<-- 更新时应用新的 Machine 设置  
machine-config-operator-578d99c7-gcwfd            #<-- 管理对 systemd, cri-o/kubelet, kernel, NetworkManager 的更新
machine-config-server-nh5r2                       #<-- 为添加到集群的 new machine 提供 ignition 配置         
~~~

**Namespace：openshift-marketplace**
~~~
certified-operators-m7472                         #<-- 提供来自 ISV(independent software vendors) 产品
community-operators-k2zt5                         #<-- 产品在 GitHub repositroy 上维护，但没有来自 Red Hat 的官方支持     
marketplace-operator-dffcc765-sw88w               #<-- 将集群外的 Operator 带入集群的角色
redhat-marketplace-6h9q5                          #<-- 一个 open cloud marketplace，可以轻松发现和访问在 public cloud 和本地环境中运行的基于容器的环境的认证软件。        
redhat-operators-xzb29                            #<-- 提供 Red Hat 产品     
~~~

**Namespace：openshift-network-diagnostics**
~~~
network-check-source-579795dc4b-ft77l             #<-- 使用 PodNetworkConnectivity，连接到为每个对象指定的 spec.targetEndpoint
network-check-target-64vmc                        #<-- 测试每个节点的连接状态
~~~

**Namespace：openshift-network-operator**
~~~
network-operator-597645ff95-djpmh                 #<-- 在 OpenShift 集群上部署和管理集群网络组件，包括 CNI 默认网络提供程序插件
~~~

**Namespace：openshift-oauth-apiserver**
~~~
apiserver-c7d5cd5d9-2q2q8 :   #<-- 验证和配置数据以向 OpenShift 进行身份验证，例如group、user和 OAuth token
~~~

**Namespace：openshift-operator-lifecycle-manager**
~~~
catalog-operator-6978dcfc69-2t8p6                 #<-- 查看并安装集群服务版本 (CSV) 和 CSV 指定的所需资源
olm-operator-646d7bd779-c2t28                     #<-- 安装/更新/管理 Kubernetes 原生应用（Operator）及相关服务的生命周期
packageserver-5f79bd8747-987qv                    #<-- 在 CatalogSource 中显示可用的包 
~~~

**Namespace：openshift-sdn**
~~~    
sdn-222qm                                         #<-- 使用 Open vSwitch 在本地连接 Pod，并使用 VXLAN 隧道连接其它节点
sdn-controller-65qmx                              #<-- 通过在 project 中创建 netnamespace 和在节点中创建 HostSubnet 来提供 egressIP 的高可用性
~~~

**Namespace：openshift-service-ca**
~~~
service-ca-57fcf9b649-rtv8l                       #<-- 提供您自己的 CA certificate/key pair
~~~

**Namespace：openshift-service-ca-operator**
~~~
service-ca-operator-59f66cff67-4vcr4              #<-- Operator 在部署集群时创建自签名 CA
~~~
