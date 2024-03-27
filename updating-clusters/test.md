## ocp升级期间恢复到以前的集群状态

**1.升级ocp之前先备份etcd**

~~~
$ oc debug node/master01.ocp4.example.net
sh-4.2# chroot /host
sh-4.4# /usr/local/bin/cluster-backup.sh /home/core/assets/backup
···
snapshot db and kube resources are successfully saved to /home/core/assets/backup
sh-4.4# exit
sh-4.4# exit
~~~

**2.ocp集群升级至一半然后手动模拟故障**
~~~
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.10.20   True        False         8d      Cluster version is 4.10.20

$ oc adm upgrade --allow-explicit-upgrade \
     --to-image  ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}@sha256:0ca14e0f692391970fc23f88188f2a21f35a5ba24fe2f3cb908fd79fa46458e6
warning: The requested upgrade image is not one of the available updates.You have used --allow-explicit-upgrade for the update to proceed anyway
Requesting update to release image docker.registry.example.net:5000/ocp4/openshift4@sha256:0ca14e0f692391970fc23f88188f2a21f35a5ba24fe2f3cb908fd79fa46458e6

- 除了machine-config clusteroperator以外，均已升级至4.11.12
$ oc get co
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.11.12   True        False         False      45m     
···  
machine-approver                           4.11.12   True        False         False      7d21h   
machine-config                             4.10.20   True        True          False      5d15h   Working towards 4.11.12
···

- 如下命令可以得知master03还未升级至4.11.12，但其它节点已升级完成。
$ oc get node
NAME                        STATUS   ROLES           AGE   VERSION
master01.ocp4.example.net   Ready    master,worker   8d    v1.24.6+5157800
master02.ocp4.example.net   Ready    master,worker   8d    v1.24.6+5157800
master03.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb  
worker01.ocp4.example.net   Ready    worker          8d    v1.24.6+5157800

- 禁止master自动重启
$ oc patch --type=merge --patch='{"spec":{"paused":true}}' machineconfigpool/master

- 删除一些集群资源
$ oc delete ns openshift-monitoring openshift-dns
namespace "openshift-monitoring" deleted
namespace "openshift-dns" deleted

$ oc get ns | grep -v Active
NAME                                               STATUS        AGE
openshift-dns                                      Terminating   8d
openshift-monitoring                               Terminating   8d

$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.10.20   True        True          90m     Working towards 4.11.12: 679 of 803 done (84% complete)

$ oc get co | grep -v '.True.*False.*False'
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.11.12   False       False         True       2m15s   OAuthServerRouteEndpointAccessibleControllerAvailable: Get "https://oauth-openshift.apps.ocp4.example.net/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
console                                    4.11.12   False       False         False      2m17s   RouteHealthAvailable: failed to GET route (https://console-openshift-console.apps.ocp4.example.net): Get "https://console-openshift-console.apps.ocp4.example.net": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
dns                                        4.11.12   False       True          True       2m30s   DNS "default" is unavailable.
machine-config                             4.10.20   True        True          True       6d2h    Unable to apply 4.11.12: error during syncRequiredMachineConfigPools: [timed out waiting for the condition, pool master has not progressed to latest configuration: controller version mismatch for rendered-master-81997fed88bb05b4cee5efc051848efd expected 0854b1512e8e445c235252a76e42043bbfa67512 has c3ac7f07f1cae32456a7ab361e29f49af7eb0802: <unknown>, retrying]
~~~

**3.开始还原集群状态，选择一个master节点用作恢复主机**
~~~
恢复主机: master01
非恢复主机: master02~03
~~~

**4.ssh访问所有master节点**

**5.将etcd备份目录复制到恢复主机中**

**6.停止非恢复主机的static pod**

a.在非恢复主机中将现有的etcd pod文件移出kubelet清单目录
~~~
- 在非恢复主机master02中将现有的etcd pod文件移出kubelet清单目录
$ ssh core@master02.ocp4.example.net sudo mv /etc/kubernetes/manifests/etcd-pod.yaml /tmp

- 验证etcd pod是否已停止
$ ssh core@master02.ocp4.example.net sudo crictl ps | grep etcd | grep -v operator

- 在非恢复主机master03中将现有的etcd pod文件移出kubelet清单目录
$ ssh core@master03.ocp4.example.net sudo mv /etc/kubernetes/manifests/etcd-pod.yaml /tmp

- 验证etcd pod是否已停止
$ ssh core@master03.ocp4.example.net sudo crictl ps | grep etcd | grep -v operator
~~~

b.在非恢复主机中将现有的Kubernetes API Server pod文件移出kubelet清单目录
~~~
- 在非恢复主机maser02中将现有的Kubernetes API Server pod文件移出kubelet清单目录
$ ssh core@master02.ocp4.example.net sudo mv /etc/kubernetes/manifests/kube-apiserver-pod.yaml /tmp

- 验证Kubernetes API Server pod是否已停止
$ ssh core@master02.ocp4.example.net sudo crictl ps | grep kube-apiserver | grep -v operator

- 在非恢复主机maser03中将现有的Kubernetes API Server pod文件移出kubelet清单目录
$ ssh core@master03.ocp4.example.net sudo mv /etc/kubernetes/manifests/kube-apiserver-pod.yaml /tmp

- 验证Kubernetes API Server pod是否已停止
$ ssh core@master03.ocp4.example.net sudo crictl ps | grep kube-apiserver | grep -v operator
~~~

c.在非恢复主机中将etcd数据目录移动到其他位置
~~~
$ ssh core@master02.ocp4.example.net sudo mv /var/lib/etcd/ /tmp

$ ssh core@master03.ocp4.example.net sudo mv /var/lib/etcd/ /tmp
~~~

**7.在恢复主机上运行还原脚本**
~~~
$ ssh core@master01.ocp4.example.net
[core@master01 ~]$ sudo -E /usr/local/bin/cluster-restore.sh /home/core/assets/backup
···
.complete
Waiting for container etcdctl to stop
............................complete
···
static-pod-resources/kube-scheduler-pod-9/kube-scheduler-pod.yaml
~~~

**8.还原完成后，检查节点以确保它们处于Ready状态，并验证集群以还原**

a.检查节点状态
~~~
$ ssh core@master01.ocp4.example.net
[core@master01 ~]$ sudo -i
[root@master01 ~]# export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
[root@master01 ~]# oc get nodes -w
NAME                        STATUS   ROLES           AGE   VERSION
master01.ocp4.example.net   Ready    master,worker   8d    v1.24.6+5157800
master02.ocp4.example.net   Ready    master,worker   8d    v1.24.6+5157800
master03.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb
worker01.ocp4.example.net   Ready    worker          8d    v1.24.6+5157800
~~~

b.如果任何节点处于NotReady状态，则ssh到节点，并从/var/lib/kubelet/pki目录中删除所有PEM文件
~~~
$ ssh core@<node-name>
[core@<node-name> ~]$ cd /var/lib/kubelet/pki
[core@<node-name> ~]$ ls
kubelet-client-2022-12-09-07-43-44.pem  kubelet-client-current.pem              kubelet-server-2022-12-10-04-19-38.pem
kubelet-client-2022-12-10-02-46-39.pem  kubelet-server-2022-12-09-07-44-05.pem  kubelet-server-current.pem
[root@<node-name> ~]$ sudo -i
[core@<node-name> ~]$ rm -rf kubelet-client* kubelet-server*
~~~

c.还原集群前删除了集群project，etcd还原后确认如下project是否还原了
~~~
[root@master01 ~]# oc get ns | grep openshift-monitoring 
openshift-monitoring                               Active   8d
[root@master01 ~]# oc get ns | grep openshift-dns
openshift-dns                                      Active   8d
~~~

**9.在所有master节点中重启kubelet服务**

a.首先从恢复主机运行以下命令：
~~~
$ ssh core@master01.ocp4.example.net sudo systemctl restart kubelet.service
~~~

b.然后重启非恢复主机的kubelet服务。
~~~
$ ssh core@master02.ocp4.example.net sudo systemctl restart kubelet.service

$ ssh core@master03.ocp4.example.net sudo systemctl restart kubelet.service
~~~

c.验证节点状态为Ready，并确认节点版本
~~~
- 如下命令输出可以确认到master03为4.10.20(升级前的版本)，其它节点均为4.11.12版本
$ oc get no
NAME                        STATUS                     ROLES           AGE   VERSION
master01.ocp4.example.net   Ready,SchedulingDisabled   master,worker   8d    v1.24.6+5157800
master02.ocp4.example.net   Ready,SchedulingDisabled   master,worker   8d    v1.24.6+5157800
master03.ocp4.example.net   Ready                      master,worker   8d    v1.23.5+3afdacb #<-- 只有该节点还是4.10.20版本
worker01.ocp4.example.net   Ready                      worker          8d    v1.24.6+5157800

$ oc get node -o wide
NAME                        STATUS                     ROLES           AGE   VERSION           INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                                                        KERNEL-VERSION                 CONTAINER-RUNTIME
master01.ocp4.example.net   Ready,SchedulingDisabled   master,worker   8d    v1.24.6+5157800   10.74.253.204   <none>        Red Hat Enterprise Linux CoreOS 411.86.202210201510-0 (Ootpa)   4.18.0-372.26.1.el8_6.x86_64   cri-o://1.24.3-5.rhaos4.11.gitc4567c0.el8
master02.ocp4.example.net   Ready                      master,worker   8d    v1.23.5+3afdacb   10.74.252.238   <none>        Red Hat Enterprise Linux CoreOS 410.84.202206212304-0 (Ootpa)   4.18.0-305.49.1.el8_4.x86_64   cri-o://1.23.3-6.rhaos4.10.git74543e3.el8
master03.ocp4.example.net   Ready                      master,worker   8d    v1.23.5+3afdacb   10.74.250.166   <none>        Red Hat Enterprise Linux CoreOS 410.84.202206212304-0 (Ootpa)   4.18.0-305.49.1.el8_4.x86_64   cri-o://1.23.3-6.rhaos4.10.git74543e3.el8
worker01.ocp4.example.net   Ready                      worker          8d    v1.24.6+5157800   10.74.253.183   <none>        Red Hat Enterprise Linux CoreOS 411.86.202210201510-0 (Ootpa)   4.18.0-372.26.1.el8_6.x86_64   cri-o://1.24.3-5.rhaos4.11.gitc4567c0.el8

- 等待mcp自动重启节点，如下输出可以确认到master02节点也自动降级到了4.10.20(升级前的版本)
$ oc get no 
NAME                        STATUS                     ROLES           AGE   VERSION
master01.ocp4.example.net   Ready,SchedulingDisabled   master,worker   8d    v1.24.6+5157800
master02.ocp4.example.net   Ready                      master,worker   8d    v1.23.5+3afdacb #<-- master02节点重启kubelet服务后自动降级为4.10.20
master03.ocp4.example.net   Ready                      master,worker   8d    v1.23.5+3afdacb
worker01.ocp4.example.net   Ready                      worker          8d    v1.24.6+5157800  

- 重启worker01节点的kubelet服务，等待mcp自动重启master01和worker01
$ ssh core@worker01.ocp4.example.net sudo systemctl restart kubelet.service  
$ oc get no 
NAME                        STATUS                        ROLES           AGE   VERSION
master01.ocp4.example.net   NotReady,SchedulingDisabled   master,worker   8d    v1.24.6+5157800
master02.ocp4.example.net   Ready                         master,worker   8d    v1.23.5+3afdacb
master03.ocp4.example.net   Ready                         master,worker   8d    v1.23.5+3afdacb
worker01.ocp4.example.net   NotReady,SchedulingDisabled   worker          8d    v1.24.6+5157800 

- master01和worker01自动重启完成后，所有节点版本都自动降级到了4.10.20(升级前的版本)，并且crio的版本也降级到了升级前的版本
$ oc get no 
NAME                        STATUS   ROLES           AGE   VERSION
master01.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb
master02.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb
master03.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb
worker01.ocp4.example.net   Ready    worker          8d    v1.23.5+3afdacb

$ oc get node -o wide
NAME                        STATUS   ROLES           AGE   VERSION           INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                                                        KERNEL-VERSION                 CONTAINER-RUNTIME
master01.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb   10.74.253.204   <none>        Red Hat Enterprise Linux CoreOS 410.84.202206212304-0 (Ootpa)   4.18.0-305.49.1.el8_4.x86_64   cri-o://1.23.3-6.rhaos4.10.git74543e3.el8
master02.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb   10.74.252.238   <none>        Red Hat Enterprise Linux CoreOS 410.84.202206212304-0 (Ootpa)   4.18.0-305.49.1.el8_4.x86_64   cri-o://1.23.3-6.rhaos4.10.git74543e3.el8
master03.ocp4.example.net   Ready    master,worker   8d    v1.23.5+3afdacb   10.74.250.166   <none>        Red Hat Enterprise Linux CoreOS 410.84.202206212304-0 (Ootpa)   4.18.0-305.49.1.el8_4.x86_64   cri-o://1.23.3-6.rhaos4.10.git74543e3.el8
worker01.ocp4.example.net   Ready    worker          8d    v1.23.5+3afdacb   10.74.253.183   <none>        Red Hat Enterprise Linux CoreOS 410.84.202206212304-0 (Ootpa)   4.18.0-305.49.1.el8_4.x86_64   cri-o://1.23.3-6.rhaos4.10.git74543e3.el8

$ oc describe node master01.ocp4.example.net | grep Annotations -A5
Annotations:        machineconfiguration.openshift.io/controlPlaneTopology: HighlyAvailable
                    machineconfiguration.openshift.io/currentConfig: rendered-master-81997fed88bb05b4cee5efc051848efd
                    machineconfiguration.openshift.io/desiredConfig: rendered-master-81997fed88bb05b4cee5efc051848efd
                    machineconfiguration.openshift.io/reason: 
                    machineconfiguration.openshift.io/ssh: accessed
                    machineconfiguration.openshift.io/state: Done

$ oc describe node master02.ocp4.example.net | grep Annotations -A5
Annotations:        machineconfiguration.openshift.io/controlPlaneTopology: HighlyAvailable
                    machineconfiguration.openshift.io/currentConfig: rendered-master-81997fed88bb05b4cee5efc051848efd
                    machineconfiguration.openshift.io/desiredConfig: rendered-master-81997fed88bb05b4cee5efc051848efd
                    machineconfiguration.openshift.io/reason: 
                    machineconfiguration.openshift.io/ssh: accessed
                    machineconfiguration.openshift.io/state: Done

$ oc describe node master03.ocp4.example.net | grep Annotations -A5
Annotations:        machineconfiguration.openshift.io/controlPlaneTopology: HighlyAvailable
                    machineconfiguration.openshift.io/currentConfig: rendered-master-81997fed88bb05b4cee5efc051848efd
                    machineconfiguration.openshift.io/desiredConfig: rendered-master-81997fed88bb05b4cee5efc051848efd
                    machineconfiguration.openshift.io/reason: 
                    machineconfiguration.openshift.io/ssh: accessed
                    machineconfiguration.openshift.io/state: Done

$ oc describe node worker01.ocp4.example.net | grep Annotations -A5
Annotations:        machineconfiguration.openshift.io/controlPlaneTopology: HighlyAvailable
                    machineconfiguration.openshift.io/currentConfig: rendered-worker-71f601f6de1ebdb641c03f2a6604f969
                    machineconfiguration.openshift.io/desiredConfig: rendered-worker-71f601f6de1ebdb641c03f2a6604f969
                    machineconfiguration.openshift.io/reason: 
                    machineconfiguration.openshift.io/ssh: accessed
                    machineconfiguration.openshift.io/state: Done

$ ssh core@master01.ocp4.example.net 
[core@master01 ~]$ sudo uname -a
Linux master01.ocp4.example.net 4.18.0-305.49.1.el8_4.x86_64 #1 SMP Wed May 11 09:47:48 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@master01 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.10
[core@master01 ~]$ sudo cat /etc/os-release | grep -w VERSION
VERSION="410.84.202206212304-0"

$ ssh core@master02.ocp4.example.net
[core@master02 ~]$ sudo uname -a 
Linux master02.ocp4.example.net 4.18.0-305.49.1.el8_4.x86_64 #1 SMP Wed May 11 09:47:48 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@master02 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.10
[core@master02 ~]$ cat /etc/os-release | grep -w VERSION
VERSION="410.84.202206212304-0"

$ ssh core@master03.ocp4.example.net 
[core@master03 ~]$ sudo uname -a
Linux master03.ocp4.example.net 4.18.0-305.49.1.el8_4.x86_64 #1 SMP Wed May 11 09:47:48 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@master03 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.10
[core@master03 ~]$ sudo cat /etc/os-release | grep -w VERSION
VERSION="410.84.202206212304-0"

$ ssh core@worker01.ocp4.example.net
[core@worker01 ~]$ sudo uname -a
Linux worker01.ocp4.example.net 4.18.0-305.49.1.el8_4.x86_64 #1 SMP Wed May 11 09:47:48 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@worker01 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.10
[core@worker01 ~]$ sudo cat /etc/os-release | grep -w VERSION
VERSION="410.84.202206212304-0"

- 所有节点的sssd服务都未启动，手动重启节点即可恢复正常
$ ssh core@<master01~03>.ocp4.example.net sudo systemctl status sssd.service
$ ssh core@<worker01>.ocp4.example.net sudo systemctl status sssd.service
● sssd.service - System Security Services Daemon
   Loaded: loaded (/usr/lib/systemd/system/sssd.service; enabled; vendor preset: enabled)
   Active: failed (Result: exit-code) since Sat 2022-12-17 19:53:55 UTC; 3min 43s ago
  Process: 125948 ExecStart=/usr/sbin/sssd -i ${DEBUG_LOGGER} (code=exited, status=3)
 Main PID: 125948 (code=exited, status=3)
      CPU: 29ms

Dec 17 19:53:55 master01.ocp4.example.net systemd[1]: sssd.service: Service RestartSec=100ms expired, scheduling restart.
Dec 17 19:53:55 master01.ocp4.example.net systemd[1]: sssd.service: Scheduled restart job, restart counter is at 5.
Dec 17 19:53:55 master01.ocp4.example.net systemd[1]: Stopped System Security Services Daemon.
Dec 17 19:53:55 master01.ocp4.example.net systemd[1]: sssd.service: Consumed 29ms CPU time
Dec 17 19:53:55 master01.ocp4.example.net systemd[1]: sssd.service: Start request repeated too quickly.
Dec 17 19:53:55 master01.ocp4.example.net systemd[1]: sssd.service: Failed with result 'exit-code'.
Dec 17 19:53:55 master01.ocp4.example.net systemd[1]: Failed to start System Security Services Daemon.
~~~

**10.确认集群状态**
~~~
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.10.20   True        False         8d      Cluster version is 4.10.20

$ oc get mcp
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-81997fed88bb05b4cee5efc051848efd   True      False      False      3              3                   3                     0                      8d
worker   rendered-worker-71f601f6de1ebdb641c03f2a6604f969   True      False      False      1              1                   1                     0                      8d

$ oc get co
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.10.20   True        False         False      4m19s   
baremetal                                  4.10.20   True        False         False      8d      
cloud-controller-manager                   4.10.20   True        False         False      8d      
cloud-credential                           4.10.20   True        False         False      8d      
cluster-autoscaler                         4.10.20   True        False         False      8d      
config-operator                            4.10.20   True        False         False      8d      
console                                    4.10.20   True        False         False      29s     
csi-snapshot-controller                    4.10.20   True        False         False      8d      
dns                                        4.10.20   True        False         False      8d      
etcd                                       4.10.20   True        False         False      8d      
image-registry                             4.10.20   True        False         False      11m     
ingress                                    4.10.20   True        False         False      12m     
insights                                   4.10.20   True        False         False      12s     
kube-apiserver                             4.10.20   True        False         False      8d      
kube-controller-manager                    4.10.20   True        False         False      8d      
kube-scheduler                             4.10.20   True        False         False      8d      
kube-storage-version-migrator              4.10.20   True        False         False      11m     
machine-api                                4.10.20   True        False         False      8d      
machine-approver                           4.10.20   True        False         False      8d      
machine-config                             4.10.20   True        False         False      6d4h    
marketplace                                4.10.20   True        False         False      8d      
monitoring                                 4.10.20   True        False         False      10s     
network                                    4.10.20   True        False         False      8d      
node-tuning                                4.10.20   True        False         False      8d      
openshift-apiserver                        4.10.20   True        False         False      8d      
openshift-controller-manager               4.10.20   True        False         False      7d10h   
openshift-samples                          4.10.20   True        False         False      8d      
operator-lifecycle-manager                 4.10.20   True        False         False      8d      
operator-lifecycle-manager-catalog         4.10.20   True        False         False      8d      
operator-lifecycle-manager-packageserver   4.10.20   True        False         False      5h52m   
service-ca                                 4.10.20   True        False         False      8d      
storage                                    4.10.20   True        False         False      8d

- 验证etcd pod是否正在运行，如果etcd pod状态为 Pending，需要等待几分钟
$ oc get pods -n openshift-etcd | grep -v etcd-quorum-guard | grep etcd
etcd-master01.ocp4.example.net                 4/4     Running     0          4m52s
etcd-master02.ocp4.example.net                 4/4     Running     0          30m
etcd-master03.ocp4.example.net                 4/4     Running     0          31m

- 验证control plane static pod版本是否一致
$ oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 13

$ oc get kubeapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 16

$ oc get kubecontrollermanager -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 7

$ oc get kubescheduler -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 8
~~~

**11.尝试重新升级至4.11.12**
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.10.20   True        False         8d      Cluster version is 4.10.20

$ oc adm upgrade --allow-explicit-upgrade \
     --to-image  ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}@sha256:0ca14e0f692391970fc23f88188f2a21f35a5ba24fe2f3cb908fd79fa46458e6
warning: The requested upgrade image is not one of the available updates.You have used --allow-explicit-upgrade for the update to proceed anyway
Requesting update to release image docker.registry.example.net:5000/ocp4/openshift4@sha256:0ca14e0f692391970fc23f88188f2a21f35a5ba24fe2f3cb908fd79fa46458e6

$ NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.11.12   True        False         8m50s   Cluster version is 4.11.12

$ oc get node 
NAME                        STATUS   ROLES           AGE   VERSION
master01.ocp4.example.net   Ready    master,worker   8d    v1.24.6+5157800
master02.ocp4.example.net   Ready    master,worker   8d    v1.24.6+5157800
master03.ocp4.example.net   Ready    master,worker   8d    v1.24.6+5157800
worker01.ocp4.example.net   Ready    worker          8d    v1.24.6+5157800

$ oc get co | grep -v '.True.*False.*False'
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE

$ ssh core@master01.ocp4.example.net 
[core@master01 ~]$ sudo uname -a
Linux master01.ocp4.example.net 4.18.0-372.26.1.el8_6.x86_64 #1 SMP Sat Aug 27 02:44:20 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@master01 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.11
[core@master01 ~]$ sudo cat /etc/os-release | grep -w VERSION
VERSION="411.86.202210201510-0"

$ ssh core@master02.ocp4.example.net
[core@master02 ~]$ sudo uname -a 
Linux master02.ocp4.example.net 4.18.0-372.26.1.el8_6.x86_64 #1 SMP Sat Aug 27 02:44:20 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@master02 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.11
[core@master02 ~]$ cat /etc/os-release | grep -w VERSION
VERSION="411.86.202210201510-0"

$ ssh core@master03.ocp4.example.net 
[core@master03 ~]$ sudo uname -a
Linux master03.ocp4.example.net 4.18.0-372.26.1.el8_6.x86_64 #1 SMP Sat Aug 27 02:44:20 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@master03 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.11
[core@master03 ~]$ sudo cat /etc/os-release | grep -w VERSION
VERSION="411.86.202210201510-0"

$ ssh core@worker01.ocp4.example.net
[core@worker01 ~]$ sudo uname -a
Linux worker01.ocp4.example.net 4.18.0-372.26.1.el8_6.x86_64 #1 SMP Sat Aug 27 02:44:20 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
[core@worker01 ~]$ sudo cat /etc/redhat-release
Red Hat Enterprise Linux CoreOS release 4.11
[core@worker01 ~]$ sudo cat /etc/os-release | grep -w VERSION
VERSION="411.86.202210201510-0"
~~~
