### OpenShift namespace describe


**NAMESPACE：openshift-apiserver-operator**
~~~
openshift-apiserver-operator-84d7d978c5-dj95w   #<-- 安装和维护 openshift-apiserver
~~~

**NAMESPACE：openshift-apiserver**
~~~
apiserver-66575ffdd7-2jdxt                      #<-- 提供 API endponint并负责 Rest API 通信
~~~

**NAMESPACE：openshift-authentication**
~~~
oauth-openshift-6fb548d946-8p4px                #<-- 发行用户可以使用的 Token
~~~

**NAMESPACE：openshift-authentication-operator**
~~~
authentication-operator-67f9d5d59c-mlhc4        #<-- 安装和维护 openshift-authentication
~~~

**NAMESPACE：openshift-cloud-credential-operator**
~~~
cloud-credential-operator-5477ffdb97-vt7dp      #<-- 提供 AWS 和 Azure 等云提供商请求的权限
~~~

**NAMESPACE：openshift-cluster-machine-approver**
~~~
machine-approver-58488dbb64-zbkjb               #<-- 管理CSR(Certificate Signing Request) 请求批准/拒绝和更新状态
~~~

**NAMESPACE：openshift-cluster-node-tuning-operator**
~~~
cluster-node-tuning-operator-69cd7f55b4-85dwn   #<-- 以守护程序可以理解的格式将自定义调整规范传递给 Tuned 守护程序
tuned-24lm7                                     #<-- Tuned 守护程序将调整选项应用于节点
~~~

**NAMESPACE：openshift-cluster-samples-operator**
~~~
cluster-samples-operator-5767d48cb7-nfgdv       #<-- 维护 image stream 和 template
~~~

**NAMESPACE：openshift-cluster-storage-operator**
~~~
cluster-storage-operator-6c548f984b-8rjtm       #<-- 设置 OpenShift 集群级存储默认值并确保存在默认存储类
csi-snapshot-controller-7cbc9f746d-c5b79        #<-- 使用集群在特定时间点的存储卷状态（快照）配置新卷
csi-snapshot-webhook-6f78c74bf4-jvbrk           #<-- snapshot controller 通过 webhook 检查无效的快照对象
~~~

**NAMESPACE：openshift-cluster-version**
~~~
cluster-version-operator-6fd879f59b-ljhmg       #<-- 检查 OpenShift 集群版本并设法升级到有效版本
~~~

**NAMESPACE：openshift-config-operator**
~~~
openshift-config-operator-6d569957b5-qnfb9      #<-- 保存 OpenShift 集群标准设置
~~~

**NAMESPACE：openshift-console**
~~~
console-75b59999f-6l4xg                         #<-- 提供用户可以访问的 Web 控制台
downloads-86588df886-4xwlg                      #<-- 通过 Web 控制台提供 CLI 工具下载
~~~

**NAMESPACE：openshift-console-operator**
~~~
console-operator-5c6bf5789-84nsb                #<-- 安装和维护 Web 控制台
~~~

**NAMESPACE：openshift-controller-manager**
~~~
controller-manager-dwtpj                        #<-- 检查 OpenShift API 对象的更改(build, deployment 等)
~~~

**NAMESPACE：openshift-controller-manager-operator**
~~~
openshift-controller-manager-operator-5f856b96-ftkfj   #<-- 安装和维护CRD(Custom Resource Definition)
~~~

**NAMESPACE：openshift-dns**
~~~
dns-default-4dntp                               #<-- 更新 /etc/resolv.conf 以回退到指定的 nameserver
node-resolver-zpfb4                             #<-- 将 Service IP/Port 放在每个节点上以进行resolv
~~~

**NAMESPACE：openshift-dns-operator**
~~~
dns-operator-768f885646-cl8wq                   #<-- 部署和管理 CoreDNS 并使用它来发现基于 DNS 的服务
~~~

**NAMESPACE：openshift-etcd**
~~~
etcd-master1.ocp4.example.net                   #<-- 用于在分布式系统或 machines 集群上共享设置、发现服务和协调调度程序的 key-value 存储
etcd-quorum-guard-7f7dd97d78-cctgq              #<-- 检查 ETCD 的状态以保持 quorum
revision-pruner-16-master1.ocp4.example.net     #<-- 管理安装在主机上的static Pod
~~~

**NAMESPACE：openshift-etcd-operator**
~~~
etcd-operator-6b79444874-htwwg                  #<-- 自动化 etcd 集群扩展，并通过启用 etcd 监控和指标来简化灾难恢复过程
~~~

**NAMESPACE：openshift-image-registry**
~~~
cluster-image-registry-operator-7b75cf85c-w9q4j #<-- 管理 registry 的所有配置，包括创建单个实例和存储 OpenShift registry
image-registry-94757f4cc-ffdtr                  #<-- 保存 OpenShift 内置的 image
node-ca-2wmn5                                   #<-- 管理 registry 连接的证书
~~~

**NAMESPACE：openshift-ingress**
~~~
router-default-79fd86499d-7kjtm                 #<-- 从外部路由以访问 OpenShift 内的服务域
~~~

**NAMESPACE：openshift-ingress-canary**
~~~
ingress-canary-2w9gj                            #<-- 按比例将流量分配到每个 Pod
~~~

**NAMESPACE：openshift-ingress-operator**
~~~
ingress-operator-7b7c8f7456-d7hvz               #<-- 实现 IngressController API 并启用对 OpenShift 集群服务的外部访问的组件
~~~

**NAMESPACE：openshift-insights**
~~~
insights-operator-688765dc7b-sf5vp              #<-- 识别与集群相关的问题并在控制台中显示最新结果
~~~

**NAMESPACE：openshift-kube-apiserver**
~~~
kube-apiserver-master1.ocp4.example.net         #<-- 公开 Kubernetes API 的组件
~~~

**NAMESPACE： openshift-kube-apiserver-operator**
~~~
kube-apiserver-operator-6f475fdb7d-kqmcb        #<-- 管理和更新 Kubernetes API Server
~~~

**NAMESPACE：openshift-kube-controller-manager**
~~~
kube-controller-manager-master1.ocp4.example.net #<--  通过apiserver监控集群的共享状态，控制使其保持在正常状态
~~~

**NAMESPACE：openshift-kube-controller-manager-operator**
~~~
kube-controller-manager-operator-64f9b8f8d4-zfz6p #<-- 管理和更新 Kubernetes 控制器管理器
~~~

**NAMESPACE：openshift-kube-scheduler**
~~~
openshift-kube-scheduler-master1.ocp4.example.net #<-- Pod 会自动查找一个可运行节点，并在节点中选择得分最高的节点启动 Pod
~~~

**NAMESPACE：openshift-kube-scheduler-operator**
~~~
openshift-kube-scheduler-operator-8698d9f84-8fld8 #<-- 管理和更新 Kubernetes Scheduler
~~~

**NAMESPACE：openshift-kube-storage-version-migrator**
~~~
migrator-64d4498fc5-2fp2q                         #<-- 将存储在 etcd 中的数据迁移到最新的存储版本
~~~

**NAMESPACE：openshift-kube-storage-version-migrator-operator**
~~~
kube-storage-version-migrator-operator-75545cf695-qr2fr #<-- 管理 kube-storage-version-migrator（创建存储版本迁移请求，检测资源库版本更改，处理迁移等）
~~~

**NAMESPACE：openshift-machine-api**
~~~
cluster-autoscaler-operator-68d4fdf48c-mn5wz      #<-- 管理 OpenShift Cluster Autoscaler 部署
cluster-baremetal-operator-754b95855c-s29cb       #<-- 部署所有必要的组件以便将 bare metal 配置为 worker 节点
machine-api-operator-5b49c547d6-dml7d             #<-- 管理扩展 Kubernetes API 的专用 CRD、controllers 和 RBAC 的生命周期
~~~

**NAMESPACE：openshift-machine-config-operator**
~~~
machine-config-controller-79f997977d-ctd5j        #<-- 使用 MachineConfig 中定义的配置让 Machine 可以正常升级
machine-config-daemon-26p84                       #<-- 更新时应用新的 Machine 设置  
machine-config-operator-578d99c7-gcwfd            #<-- 管理对 systemd, cri-o/kubelet, kernel, NetworkManager 的更新
machine-config-server-nh5r2                       #<-- 为添加到集群的 new machine 提供 ignition 配置         
~~~

**NAMESPACE：openshift-marketplace**
~~~
certified-operators-m7472                         #<-- 提供来自 ISV(independent software vendors) 产品
community-operators-k2zt5                         #<-- 产品在 GitHub repositroy 上维护，但没有来自 Red Hat 的官方支持     
marketplace-operator-dffcc765-sw88w               #<-- 将集群外的 Operator 带入集群的角色
redhat-marketplace-6h9q5                          #<-- 一个 open cloud marketplace，可以轻松发现和访问在 public cloud 和本地环境中运行的基于容器的环境的认证软件。        
redhat-operators-xzb29                            #<-- 提供 Red Hat 产品     
~~~

**NAMESPACE：openshift-network-diagnostics**
~~~
network-check-source-579795dc4b-ft77l             #<-- 使用 PodNetworkConnectivity，连接到为每个对象指定的 spec.targetEndpoint
network-check-target-64vmc                        #<-- 测试每个节点的连接状态
~~~

**NAMESPACE：openshift-network-operator**
~~~
network-operator-597645ff95-djpmh                 #<-- 在 OpenShift 集群上部署和管理集群网络组件，包括 CNI 默认网络提供程序插件
~~~

**NAMESPACE：openshift-operator-lifecycle-manager**
~~~
catalog-operator-6978dcfc69-2t8p6                 #<-- 查看并安装集群服务版本 (CSV) 和 CSV 指定的所需资源
olm-operator-646d7bd779-c2t28                     #<-- 安装/更新/管理 Kubernetes 原生应用（Operator）及相关服务的生命周期
packageserver-5f79bd8747-987qv                    #<-- 在 CatalogSource 中显示可用的包 
~~~

**NAMESPACE：openshift-sdn**
~~~    
sdn-222qm                                         #<-- 使用 Open vSwitch 在本地连接 Pod，并使用 VXLAN 隧道连接其它节点
sdn-controller-65qmx                              #<-- 通过在 project 中创建 netnamespace 和在节点中创建 HostSubnet 来提供 egressIP 的高可用性
~~~

**NAMESPACE：openshift-service-ca**
~~~
service-ca-57fcf9b649-rtv8l                       #<-- 提供您自己的 CA certificate/key pair
~~~

**NAMESPACE：openshift-service-ca-operator**
~~~
service-ca-operator-59f66cff67-4vcr4              #<-- Operator 在部署集群时创建自签名 CA
~~~
