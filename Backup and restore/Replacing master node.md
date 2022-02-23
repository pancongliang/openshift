## Replacing master node

### - 测试恢复过程如下:
  - 环境ocp4.6，模拟1个master宕机（master02.ocp4-6.example.com 关机），此时集群可用:
  

**1.确认异常的etcd member，并备份正常的etcd**
~~~
$ oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="EtcdMembersAvailable")]}{.message}{"\n"}'
  #2 of 3 members are available, master02.ocp4-6.example.com is unhealthy

$ ssh core@master01.ocp4-6.example.com
$ sudo /usr/local/bin/cluster-backup.sh /home/core/assets/backup
...
snapshot db and kube resources are successfully saved to /var/home/core/backup
~~~

**2.删除异常的etcd member**

a.首先选择一个正常的节点上的 pod:
~~~
$ oc get pods -n openshift-etcd | grep -v etcd-quorum-guard | grep etcd
$ oc rsh -n openshift-etcd etcd-master01.ocp4-6.example.com
~~~

b.查看成员列表，记录异常的 etcd member ID 和 NAME:
~~~
sh-4.2# etcdctl member list -w table
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
|        ID        | STATUS  |            NAME             |        PEER ADDRS         |       CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
| 46191ff6735e3be3 | stop    | master02.ocp4-6.example.com | https://10.72.36.162:2380 | https://10.72.36.162:2379 |      false |
| 4bd29169d428398a | started | master01.ocp4-6.example.com | https://10.72.45.161:2380 | https://10.72.45.161:2379 |      false |
| 7631738d05516ef5 | started | master03.ocp4-6.example.com | https://10.72.45.163:2380 | https://10.72.45.163:2379 |      false |
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
~~~

c.删除异常的 etcd member:
~~~
sh-4.2# etcdctl member remove 46191ff6735e3be3
Member 46191ff6735e3be3 removed from cluster 27362b2d2f04618
sh-4.2# etcdctl member list -w table
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
|        ID        | STATUS  |            NAME             |        PEER ADDRS         |       CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
| 4bd29169d428398a | started | master01.ocp4-6.example.com | https://10.72.45.161:2380 | https://10.72.45.161:2379 |      false |
| 7631738d05516ef5 | started | master03.ocp4-6.example.com | https://10.72.45.163:2380 | https://10.72.45.163:2379 |      false |
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
~~~

**3.查看已删除/异常的etcd secret，并删除异常的etcd secret**
~~~
$ oc get secret -n openshift-etcd |grep master02.ocp4-6.example.com 
  etcd-peer-master02.ocp4-6.example.com              kubernetes.io/tls        2      18d
  etcd-serving-master02.ocp4-6.example.com           kubernetes.io/tls        2      18d
  etcd-serving-metrics-master02.ocp4-6.example.com   kubernetes.io/tls        2      18d

$ oc delete secret -n openshift-etcd etcd-peer-master02.ocp4-6.example.com
  secret "etcd-peer-master02.ocp4-6.example.com" deleted

$ oc delete secret -n openshift-etcd etcd-serving-master02.ocp4-6.example.com
  secret "etcd-serving-master02.ocp4-6.example.com" deleted

$ oc delete secret -n openshift-etcd etcd-serving-metrics-master02.ocp4-6.example.com
  secret "etcd-serving-metrics-master02.ocp4-6.example.com" deleted
~~~

**4.删除etcd异常的master节点**
~~~
$ oc get node
NAME                          STATUS     ROLES           AGE   VERSION
master01.ocp4-6.example.com   Ready      master,worker   18d   v1.19.0+7070803
master02.ocp4-6.example.com   NotReady   master,worker   18d   v1.19.0+7070803
master03.ocp4-6.example.com   Ready      master,worker   18d   v1.19.0+7070803
worker01.ocp4-6.example.com   Ready      worker          18d   v1.19.0+7070803

$ oc adm cordon master02.ocp4-6.example.com
$ oc adm drain master02.ocp4-6.example.com --force --delete-local-data --ignore-daemonsets
$ oc delete node master02.ocp4-6.example.com

$ oc get no
NAME                          STATUS   ROLES           AGE   VERSION
master01.ocp4-6.example.com   Ready    master,worker   18d   v1.19.0+7070803
master03.ocp4-6.example.com   Ready    master,worker   18d   v1.19.0+7070803
worker01.ocp4-6.example.com   Ready    worker          18d   v1.19.0+7070803
~~~

**5.重新安装master节点，使用master.ign文件重新安装master，并批准csr**

a.使用最初安装ocp集群一样，单独安装master02节点，无需bootstrap:
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.45.160:8080/pre/master.ign  \
  ip=10.72.45.162::10.72.47.254:255.255.252.0:master02.ocp4-6.example.com::none \
  nameserver=10.72.45.160
~~~

b.master02启动完成后，批准新增节点的csr:
~~~
$ oc get csr
  csr-pfkt6   13s   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending

$ oc adm certificate approve csr-pfkt6
certificatesigningrequest.certificates.k8s.io/csr-pfkt6 approved

$ oc get csr
  csr-nvtfn   <invalid>   kubernetes.io/kubelet-serving   ystem:node:master02.ocp4-6.example.com  Pendingd

$ oc adm certificate approve csr-nvtfn
certificatesigningrequest.certificates.k8s.io/csr-nvtfn approved
~~~

c.确认master02是否成功添加:
~~~
$ oc get no
NAME                          STATUS   ROLES           AGE    VERSION
master01.ocp4-6.example.com   Ready    master,worker   18d    v1.19.0+7070803
master02.ocp4-6.example.com   Ready    master,worker   4m3s   v1.19.0+7070803  <--新添加的节点
master03.ocp4-6.example.com   Ready    master,worker   18d    v1.19.0+7070803
worker01.ocp4-6.example.com   Ready    worker          18d    v1.19.0+7070803
~~~

**6.验证etcd是否正常**
a.验证所有 etcd pod 是否正常运行:
~~~
$ oc get pods -n openshift-etcd | grep -v etcd-quorum-guard | grep etcd
etcd-master01.ocp4-6.example.com                 3/3     Running     0          61m
etcd-master02.ocp4-6.example.com                 3/3     Running     0          64m
etcd-master03.ocp4-6.example.com                 3/3     Running     0          63m
~~~


**报错时参考:**

**1. etcd 仅显示两个**

a. 如果上一个命令的输出仅列出两个 pod，通过如下方法强制重新部署etcd:
~~~
$ oc patch etcd cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge 
etcd.operator.openshift.io/cluster patched
~~~

b. 验证是否正好有三个 etcd 成员，并且都是started状态:
~~~
$ oc rsh -n openshift-etcd etcd-master01.ocp4-6.example.com
sh-4.2# etcdctl member list -w table
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
|        ID        | STATUS  |            NAME             |        PEER ADDRS         |       CLIENT ADDRS        | IS LEARNER |
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
| 4bd29169d428398a | started | master01.ocp4-6.example.com | https://10.72.45.161:2380 | https://10.72.45.161:2379 |      false |
| 7631738d05516ef5 | started | master03.ocp4-6.example.com | https://10.72.45.163:2380 | https://10.72.45.163:2379 |      false |
| ce5865e1dbd82976 | started | master02.ocp4-6.example.com | https://10.72.45.162:2380 | https://10.72.45.162:2379 |      false |
+------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
~~~

c.查看etcd cluster operator是否正常:
~~~
$ oc get co 
NAME   VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE
etcd   4.6.8     True        False         False      18d
~~~

**2. clusteroperator显示降级**

a.clusteroperator显示如下operator为降级状态,需要[重新安装control plane](https://docs.openshift.com/container-platform/4.6/backup_and_restore/control_plane_backup_and_restore/disaster_recovery/scenario-2-restoring-cluster-state.html):
~~~
$ oc get co
  NAME                          VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE
  kube-apiserver                4.6.8     True        False         True       5d9h
  kube-controller-manager       4.6.8     True        False         True       5d10h
  kube-scheduler                4.6.8     True        False         True       5d10h
~~~

b.强制对 Kubernetes API 服务器进行新的部署:
~~~
$ oc patch kubeapiserver cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
- 验证所有节点都更新到最新版本
$ oc get kubeapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
~~~

c.强制对 Kubernetes 控制器管理器进行新的部署:
~~~
$ oc patch kubecontrollermanager cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
- 验证所有节点都更新到最新版本
$ oc get kubecontrollermanager -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
~~~

d.强制对 Kubernetes 调度程序进行新的部署:
~~~
$ oc patch kubescheduler cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
- 验证所有节点都更新到最新版本
$ oc get kubescheduler -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
~~~
