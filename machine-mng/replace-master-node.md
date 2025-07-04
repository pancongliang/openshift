### Replace an unhealthy control-plane node

#### 1. OpenShift Cluster installed using ABI (Platform: None):
~~~
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.18.10   True        False         120m    Cluster version is 4.18.10

$ oc get infrastructures.config.openshift.io cluster -o yaml |grep platformSpec -A1
  platformSpec:
    type: None

$ oc get cm -n openshift-config openshift-install-manifests -o yaml | grep 'invoker\|version'
  invoker: agent-installer
  version: v4.18.0
~~~

#### 2. Export the master Ignition file from the current OpenShift cluster:
~~~
$ oc extract -n openshift-machine-api secret/master-user-data-managed --keys=userData --to=- > master.ign
~~~

#### 3. Shutdown the unhealthy control plane node to prepare for the replacement test:
~~~
$ export UNHEALTHY_CONTROL_PLANE_NODE=master01.ocp4.example.com
$ ssh core@$UNHEALTHY_CONTROL_PLANE_NODE sudo shutdown -h now

$ oc get nodes -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{"\t"}{range .spec.taints[*]}{.key}{" "}' | grep unreachable
master01.ocp4.example.com  node-role.kubernetes.io/master node.kubernetes.io/unreachable

$ oc get nodes -l node-role.kubernetes.io/master | grep "NotReady"
master01.ocp4.example.com   NotReady   control-plane,master   84m   v1.31.7
~~~

#### 4. Determining the state of the unhealthy etcd member:
~~~
$ oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="EtcdMembersAvailable")]}{.message}{"\n"}'
2 of 3 members are available, master01.ocp4.example.com is unhealthy

$ oc -n openshift-etcd get pods -l k8s-app=etcd
$ export HEALTHY_CONTROL_PLANE_NODE=master02.ocp4.example.com

$ oc -n openshift-etcd rsh -c etcdctl etcd-$HEALTHY_CONTROL_PLANE_NODE etcdctl endpoint health --cluster
{"level":"warn","ts":"2025-07-03T12:16:44.037389Z","logger":"client","caller":"v3@v3.5.18/retry_interceptor.go:63","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0xc00017c000/10.184.134.15:2379","attempt":0,"error":"rpc error: code = DeadlineExceeded desc = latest balancer error: last connection error: connection error: desc = \"transport: Error while dialing: dial tcp 10.184.134.15:2379: connect: no route to host\""}
https://10.184.134.16:2379 is healthy: successfully committed proposal: took = 5.332963ms
https://10.184.134.17:2379 is healthy: successfully committed proposal: took = 8.1217ms
https://10.184.134.15:2379 is unhealthy: failed to commit proposal: context deadline exceeded
Error: unhealthy cluster
command terminated with exit code 1

$ oc -n openshift-etcd rsh -c etcdctl etcd-$HEALTHY_CONTROL_PLANE_NODE etcdctl member list -w table
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |          NAME             |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
| 1a58b01637d4e7f4 | started | master02.ocp4.example.com | https://10.184.134.16:2380 | https://10.184.134.16:2379 |      false |
| 980ff555e921eb74 | started | master01.ocp4.example.com | https://10.184.134.15:2380 | https://10.184.134.15:2379 |      false |
| e1d09fe35ed2e1b8 | started | master03.ocp4.example.com | https://10.184.134.17:2380 | https://10.184.134.17:2379 |      false |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
~~~

#### 5. Remove the unhealthy etcd member by providing the ID to the etcdctl member remove command:
~~~
$ oc -n openshift-etcd rsh -c etcdctl etcd-$HEALTHY_CONTROL_PLANE_NODE etcdctl member remove 980ff555e921eb74
Member 980ff555e921eb74 removed from cluster f7fc9660ff37d964
~~~

#### 6. View the member list again and verify that the member was removed:
~~~
$ oc -n openshift-etcd rsh -Tc etcdctl etcd-$HEALTHY_CONTROL_PLANE_NODE etcdctl member list -w table
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |            NAME           |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
| 1a58b01637d4e7f4 | started | master02.ocp4.example.com | https://10.184.134.16:2380 | https://10.184.134.16:2379 |      false |
| e1d09fe35ed2e1b8 | started | master03.ocp4.example.com | https://10.184.134.17:2380 | https://10.184.134.17:2379 |      false |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+

$ oc -n openshift-etcd rsh -c etcdctl etcd-$HEALTHY_CONTROL_PLANE_NODE etcdctl endpoint health --cluster
https://10.184.134.16:2379 is healthy: successfully committed proposal: took = 4.601737ms
https://10.184.134.17:2379 is healthy: successfully committed proposal: took = 7.078678ms
~~~

#### 7. Turn off the quorum guard by entering the following command:
~~~
$ oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": {"useUnsupportedUnsafeNonHANonProductionUnstableEtcd": true}}}'
etcd.operator.openshift.io/cluster patched
~~~

#### 8. Delete the affected node by running the following command:
~~~
$ oc delete node $UNHEALTHY_CONTROL_PLANE_NODE
node "master01.ocp4.example.com" deleted

$ oc get nodes -l node-role.kubernetes.io/master
NAME                        STATUS   ROLES                  AGE    VERSION
master02.ocp4.example.com   Ready    control-plane,master   113m   v1.31.7
master03.ocp4.example.com   Ready    control-plane,master   113m   v1.31.7
~~~

#### 9. Remove the old secrets for the unhealthy etcd member that was removed:
~~~
$ oc get secrets -n openshift-etcd | grep $UNHEALTHY_CONTROL_PLANE_NODE
etcd-peer-master01.ocp4.example.com              kubernetes.io/tls         2      114m
etcd-serving-master01.ocp4.example.com           kubernetes.io/tls         2      114m
etcd-serving-metrics-master01.ocp4.example.com   kubernetes.io/tls         2      114m

$ oc delete secret -n openshift-etcd etcd-peer-$UNHEALTHY_CONTROL_PLANE_NODE etcd-serving-$UNHEALTHY_CONTROL_PLANE_NODE etcd-serving-metrics-$UNHEALTHY_CONTROL_PLANE_NODE
secret "etcd-peer-master01.ocp4.example.com" deleted
secret "etcd-serving-master01.ocp4.example.com" deleted
secret "etcd-serving-metrics-master01.ocp4.example.com" deleted
~~~

#### 10. Download and mount the RHCOS ISO, boot the target machine, and install the control plane node using the master ignition:
~~~
# Configure network setting:
[core@localhost ~]$ sudo -i
[root@localhost ~]# sudo nmcli con mod 'Wired connection 1' ipv4.addresses 10.184.134.15/24 ipv4.gateway 10.184.134.1 ipv4.dns 10.184.134.128 ipv4.method manual connection.autoconnect yes
[root@localhost ~]# sudo nmcli con down 'Wired connection 1'
[root@localhost ~]# sudo nmcli con up 'Wired connection 1'

# Install RHCOS using ignition:
[root@localhost ~]# sudo coreos-installer install /dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:0:0 --insecure-ignition --ignition-url=http://10.184.134.128:8080/pre/master.ign --insecure-ignition --firstboot-args 'rd.neednet=1' --copy-network
Install complete.

[root@localhost ~]# reboot
~~~

#### 11. Wait for and approve the CSR associated with the newly installed control plane node:
~~~
$ oc get csr
NAME        AGE     SIGNERNAME                                    REQUESTOR                                                                   REQUESTEDDURATION   CONDITION
csr-ltslg   6m20s   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending

$ oc get csr -o name | xargs oc adm certificate approve
certificatesigningrequest.certificates.k8s.io/csr-ltslg approved

$ oc get csr
NAME        AGE     SIGNERNAME                                    REQUESTOR                                                                   REQUESTEDDURATION   CONDITION
csr-ltslg   6m41s   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Approved,Issued
csr-zpvhm   1s      kubernetes.io/kubelet-serving                 system:node:master01.ocp4.example.com                                       <none>              Pending

$ oc get csr -o name | xargs oc adm certificate approve
certificatesigningrequest.certificates.k8s.io/csr-ltslg approved
certificatesigningrequest.certificates.k8s.io/csr-zpvhm approved
~~~

#### 12. Check the OCP Cluster:
~~~
$ oc get node
NAME                        STATUS   ROLES                  AGE     VERSION
master01.ocp4.example.com   Ready    control-plane,master   3m10s   v1.31.7
master02.ocp4.example.com   Ready    control-plane,master   135m    v1.31.7
master03.ocp4.example.com   Ready    control-plane,master   135m    v1.31.7
worker01.ocp4.example.com   Ready    worker                 125m    v1.31.7
worker02.ocp4.example.com   Ready    worker                 131m    v1.31.

$ oc get mcp
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-5585142797dd7c7492c87c1e916f24ac   True      False      False      3              3                   3                     0                      134m
worker   rendered-worker-516d1c9317ebd044353f0a00b05de379   True      False      False      2              2                   2                     0                      134m

# Wait for the cluster operator to return to normal state
$ oc get co | grep -v '.True.*False.*False'
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
~~~

#### 13. Turn the quorum guard back on by entering the following command:
~~~
$ oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": null}}'
etcd.operator.openshift.io/cluster patched
~~~

#### 14. Verify that the unsupportedConfigOverrides section is removed from the object by entering this command:
~~~
$ oc get etcd/cluster -oyaml |grep unsupportedConfigOverrides
~~~

#### 15. Verify that all etcd pods are running properly:
~~~
$ oc -n openshift-etcd get pods -l k8s-app=etcd
NAME                             READY   STATUS    RESTARTS   AGE
etcd-master01.ocp4.example.com   5/5     Running   0          6m14s
etcd-master02.ocp4.example.com   5/5     Running   0          8m
etcd-master03.ocp4.example.com   5/5     Running   0          9m46s

$ oc get etcd -o=jsonpath='{range.items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 17

# If only lists two pods, can manually force an etcd redeployment:
$ oc patch etcd cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge

$ oc get etcd -o=jsonpath='{range.items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 17
~~~

#### 16. Verify that there are exactly three etcd members:
~~~
$ oc -n openshift-etcd rsh -c etcdctl etcd-$HEALTHY_CONTROL_PLANE_NODE etcdctl member list -w table
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |            NAME           |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
| 1a58b01637d4e7f4 | started | master02.ocp4.example.com | https://10.184.134.16:2380 | https://10.184.134.16:2379 |      false |
| 4fca7c66432330b9 | started | master01.ocp4.example.com | https://10.184.134.15:2380 | https://10.184.134.15:2379 |      false |
| e1d09fe35ed2e1b8 | started | master03.ocp4.example.com | https://10.184.134.17:2380 | https://10.184.134.17:2379 |      false |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
~~~

#### 17. Verify that all etcd members are healthy by running the following command:
~~~
$ oc -n openshift-etcd rsh -c etcdctl etcd-${HEALTHY_CONTROL_PLANE_NODE} etcdctl endpoint health --cluster
https://10.184.134.16:2379 is healthy: successfully committed proposal: took = 5.648136ms
https://10.184.134.17:2379 is healthy: successfully committed proposal: took = 8.172716ms
https://10.184.134.15:2379 is healthy: successfully committed proposal: took = 8.739412ms
~~~
