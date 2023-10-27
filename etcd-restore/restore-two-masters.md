
## restore tow master

### Test the recovery process
   - Environment 4.8(UPI)
   - Simulate the downtime of 2 masters (master02/03.ocp4.example.com is shut down). At this time, the cluster API is unavailable (the oc command cannot be used, and only the personal business pod service is normal):
   - Make etcd backup in advance, otherwise the inability to access kube-apiserver will result in an error message indicating that the backup cannot be performed. Although the backup can be forced by adding --force, there is no guarantee that the etcd backup data is complete.


### simulate a failure environment
* Shut down non-recovery control plane hosts (master02/03) in order to simulate a failure environment
  ```
  $ ssh core@master02.ocp4.example.com sudo shutdown -h now
  $ ssh core@master03.ocp4.example.com sudo shutdown -h now

  $ oc get nodes
  Unable to connect to the server: EOF
  ```

### etcd restore

* Copy the etcd backup directory to the recovery control plane host (master01)
  ```
  [root@bastion ~]# scp -r /root/backup/ core@master01.ocp4.example.com:/home/core/
  ```

* Run the etcd recovery script on the recovery control plane host (master01)
  ```
  $ ssh core@master01.ocp4.example.com

  [core@master01 ~]$ sudo -E /usr/local/bin/cluster-restore.sh /home/core/backup
  ···
  Waiting for container kube-scheduler to stop
  complete
  ···
  starting kube-scheduler-pod.yaml
  static-pod-resources/kube-scheduler-pod-12/kube-scheduler-pod.yaml
  ```

* Restart the Kubelet service in the recovery control plane host
  ```
  [core@master01 ~]$ sudo systemctl restart kubelet.service
  ```

* Confirm that the oc command is available and the recovery control plane host is in the Ready state
  ```
  [core@master01 ~]$ sudo -i
  [root@master01 ~]# export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
  [root@master01 ~]# oc get nodes
  NAME                        STATUS     ROLES                AGE     VERSION
  master01.ocp4.example.com   Ready      master               13d   v1.23.5+3afdacb  #<-- It may take several minutes for the node to report its status
  master02.ocp4.example.com   NotReady   master               13d   v1.23.5+3afdacb
  master03.ocp4.example.com   NotReady   master               13d   v1.23.5+3afdacb
  worker01.ocp4.example.com   Ready      worker               13d   v1.23.5+3afdacb
  worker02.ocp4.example.com   Ready      worker               13d   v1.23.5+3afdacb
  worker03.ocp4.example.com   Ready      worker,worker-rhel   13d   v1.23.12+a57ef08
  ```

* Verify that the etcd pod for a single container in the recovery control plane host has started successfully
  ```
  [root@master01 ~]# crictl ps | grep etcd | grep -v operator
  4b315ff3aeb94       d9a894cf8f2712af891b38b72885c4c9d3fd3e8185a3467a2f5e9c91554607cb   2 minutes ago    Running      etcd

  [root@master01 ~]# oc -n openshift-etcd get pods -l k8s-app=etcd
  NAME                             READY   STATUS    RESTARTS   AGE
  etcd-master01.ocp4.example.com   1/1     Running   0          2m45s
  etcd-master02.ocp4.example.com   4/4     Running   8          13d
  etcd-master03.ocp4.example.com   4/4     Running   4          13d
  ```

### (Optional) Restart the Open Virtual Network (OVN) Kubernetes pod on all hosts only when using the OVNKubernetes CNI plugin
* Remove the northbound database (nbdb) and southbound database (sbdb):
  ```
  $ ssh core@master01.ocp4.example.com
  $ sudo rm -f /var/lib/ovn/etc/*.db
  ```

* Delete all OVN-Kubernetes control plane pods by running the following command:
  ```
  $ oc delete pods -l app=ovnkube-master -n openshift-ovn-kubernetes
  ```

* Ensure that all the OVN-Kubernetes control plane pods are deployed again and are in a Running state by running the following command:
  ```
  $ oc get pods -l app=ovnkube-master -n openshift-ovn-kubernetes
  ```

* Delete all ovnkube-node pods by running the following command:
  ```
  $ oc get pods -n openshift-ovn-kubernetes -o name | grep ovnkube-node | while read p ; do oc delete $p -n openshift-ovn-kubernetes ; done
  ```

* Ensure that all the ovnkube-node pods are deployed again and are in a Running state by running the following command:
  ```
  $ oc get  pods -n openshift-ovn-kubernetes | grep ovnkube-node
  ```

* Delete and recreate other non-recovery control plane machines

  oc rsh to the etcd pod on the recovery control plane host, and then check the list of etcd members. Currently there is only one member, so there is no need to remove it manually.
  ```
  $ oc -n openshift-etcd get pods -l k8s-app=etcd
  NAME                             READY   STATUS    RESTARTS   AGE
  etcd-master01.ocp4.example.com   1/1     Running   0          3m26s
  etcd-master02.ocp4.example.com   4/4     Running   8          13d
  etcd-master03.ocp4.example.com   4/4     Running   4          13d

  $ oc rsh -n openshift-etcd etcd-master01.ocp4.example.com
  sh-4.2# etcdctl member list -w table
  +------------------+---------+---------------------------+---------------------------+---------------------------+------------+
  |        ID        | STATUS  |           NAME            |        PEER ADDRS         |       CLIENT ADDRS        | IS LEARNER |
  +------------------+---------+---------------------------+---------------------------+---------------------------+------------+
  | c757c4a56691e607 | started | master01.ocp4.example.com | https://10.74.251.61:2380 | https://10.74.251.61:2379 |      false |
  +------------------+---------+---------------------------+---------------------------+---------------------------+------------+
  sh-4.4# exit
  ```

b.Turn off the quorum guard:
~~~
$ oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": {"useUnsupportedUnsafeNonHANonProductionUnstableEtcd": true}}}'

$ oc get etcd/cluster -o yaml | grep unsupportedConfigOverrides -A1
  unsupportedConfigOverrides:
    useUnsupportedUnsafeNonHANonProductionUnstableEtcd: true
~~~

c.Delete the secret of the etcd member on the non-recovery control plane host (master02/03):
~~~
$ oc get secret -n openshift-etcd |grep master02.ocp4.example.com 
etcd-peer-master02.ocp4.example.com              kubernetes.io/tls                     2      13d
etcd-serving-master02.ocp4.example.com           kubernetes.io/tls                     2      13d
etcd-serving-metrics-master02.ocp4.example.com   kubernetes.io/tls                     2      13d

$ oc delete secret etcd-peer-master02.ocp4.example.com \
                   etcd-serving-master02.ocp4.example.com \
                   etcd-serving-metrics-master02.ocp4.example.com -n openshift-etcd 

$ oc get secret -n openshift-etcd |grep master03.ocp4.example.com 
etcd-peer-master03.ocp4.example.com              kubernetes.io/tls                     2      13d
etcd-serving-master03.ocp4.example.com           kubernetes.io/tls                     2      13d
etcd-serving-metrics-master03.ocp4.example.com   kubernetes.io/tls                     2      13d

$ oc delete secret etcd-peer-master03.ocp4.example.com \
                   etcd-serving-master03.ocp4.example.com \
                   etcd-serving-metrics-master03.ocp4.example.com -n openshift-etcd

- If the secret is regenerated, can delete the secret again after deleting the non-recovery control plane host(master02/03) . During this period, some problems may occur when accessing the cluster (Error from server: etcdserver: request timed out):
$ oc get secret -n openshift-etcd |grep master02.ocp4.example.com 
$ oc get secret -n openshift-etcd |grep master03.ocp4.example.com 
~~~

d.Delete non-recovery control plane host:
~~~
$ oc get nodes
NAME                        STATUS     ROLES                AGE     VERSION
master01.ocp4.example.com   Ready      master               66d   v1.23.5+3afdacb
master02.ocp4.example.com   NotReady   master               66d   v1.23.5+3afdacb
master03.ocp4.example.com   NotReady   master               66d   v1.23.5+3afdacb
worker01.ocp4.example.com   Ready      worker               66d   v1.23.5+3afdacb
worker02.ocp4.example.com   Ready      worker,worker-rhel   66d   v1.23.12+8a6bfe4

$ oc delete node master02.ocp4.example.com
$ oc delete node master03.ocp4.example.com

$ oc get nodes
NAME                        STATUS   ROLES    AGE     VERSION
NAME                        STATUS     ROLES                AGE     VERSION
master01.ocp4.example.com   Ready      master               66d   v1.23.5+3afdacb
worker01.ocp4.example.com   Ready      worker               66d   v1.23.5+3afdacb
worker02.ocp4.example.com   Ready      worker,worker-rhel   66d   v1.23.12+8a6bfe4
~~~

**10.Reinstall the deleted non-recovery control plane host (master02/03), after the installation is complete, wait for/approve the csr.**
The same as the initial installation of ocp master, the following content is for reference only:
~~~
- example:
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/master.ign  
ip=10.74.254.155::10.74.255.254:255.255.248.0:master02.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/master.ign  
ip=10.74.253.133::10.74.255.254:255.255.248.0:master03.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204

- Approve the csr of the newly added node:
$ oc get csr
NAME        AGE     SIGNERNAME                                    REQUESTOR                                                                   REQUESTEDDURATION   CONDITION
csr-cmbx8   3m30s   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-md8xl   5s      kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending

$ oc get csr -o name | xargs oc adm certificate approve

$ oc get csr |grep Pending
csr-jbvx8   77s     kubernetes.io/kubelet-serving                 system:node:master03.ocp4.example.com                                       <none>              Pending
csr-ztqqs   79s     kubernetes.io/kubelet-serving                 system:node:master02.ocp4.example.com                                       <none>              Pending

$ oc get csr -o name | xargs oc adm certificate approve

$ oc get no
NAME                        STATUS   ROLES                AGE     VERSION
master01.ocp4.example.com   Ready    master               13d     v1.23.5+3afdacb
master02.ocp4.example.com   Ready    master               2m32s   v1.23.5+3afdacb
master03.ocp4.example.com   Ready    master               2m30s   v1.23.5+3afdacb
worker01.ocp4.example.com   Ready    worker               13d     v1.23.5+3afdacb
worker02.ocp4.example.com   Ready    worker               13d     v1.23.5+3afdacb
worker03.ocp4.example.com   Ready    worker,worker-rhel   13d     v1.23.12+a57ef08
~~~

**11.Force etcd redeployment, then turn quorum guard back on**
~~~
- Force etcd redeployment:
$ oc patch etcd cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge 

- Turn the quorum guard back on by entering the following command:
$ oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": null}}'
$ oc get etcd/cluster -o yaml |grep unsupportedConfigOverrides

- Verify all nodes are updated to the latest revision:
$ oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}' 
AllNodesAtLatestRevision
3 nodes are at revision 19

# Only when all the pods ETCD are on the same version should proceed to the next step. This process can take several minutes to complete.
~~~

**12.After etcd is redeployed, force redeployment of Kube APIServer, Kube Controller Manager, and Kube Scheduler**
a.Force a new rollout for the Kubernetes API server and wait all nodes are updated to the latest revision:
~~~
- Force a new rollout for the Kubernetes API server:
$ oc patch kubeapiserver cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge

- Verify all nodes are updated to the latest revision:
$ oc get kubeapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 23

# Only when all the pods Kube APIServer are on the same version should you follow the next step. This process can take several minutes to complete.
~~~

b. Force a new rollout for the Kubernetes controller manager and wait all nodes are updated to the latest revision:
~~~
- Force a new rollout for the Kubernetes controller manager:
$ oc patch kubecontrollermanager cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge

- Verify all nodes are updated to the latest revision
$ oc get kubecontrollermanager -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 15

# Only when all Controller Manager pods are on the same version should you proceed to the next step.
~~~

c.Force a new rollout for the Kubernetes scheduler and wait all nodes are updated to the latest revision:
~~~
- Force a new rollout for the Kubernetes scheduler:
$ oc patch kubescheduler cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge

- Verify all nodes are updated to the latest revision:
$ oc get kubescheduler -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
AllNodesAtLatestRevision
3 nodes are at revision 15
~~~

**13.After the recovery is complete, verify that the cluster is normal**
a. Confirm node status:
~~~
$ oc get no
NAME                        STATUS   ROLES                AGE   VERSION
master01.ocp4.example.com   Ready    master               13d   v1.23.5+3afdacb
master02.ocp4.example.com   Ready    master               51m   v1.23.5+3afdacb
master03.ocp4.example.com   Ready    master               51m   v1.23.5+3afdacb
worker01.ocp4.example.com   Ready    worker               13d   v1.23.5+3afdacb
worker02.ocp4.example.com   Ready    worker               13d   v1.23.5+3afdacb
worker03.ocp4.example.com   Ready    worker,worker-rhel   13d   v1.23.12+a57ef08
~~~

b. Confirm etcd pod status:
~~~
$ oc get pods -n openshift-etcd | grep etcd
etcd-master01.ocp4.example.com                 4/4     Running     0          40m
etcd-master02.ocp4.example.com                 4/4     Running     0          43m
etcd-master03.ocp4.example.com                 4/4     Running     0          41m
etcd-quorum-guard-855c746474-g7j4x             1/1     Running     0          71m
etcd-quorum-guard-855c746474-lqt6t             1/1     Running     0          71m
etcd-quorum-guard-855c746474-tgthv             1/1     Running     0          71m

$ oc rsh -n openshift-etcd etcd-master01.ocp4.example.com
sh-4.4# etcdctl endpoint status -w table
+----------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|          ENDPOINT          |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| https://10.74.250.166:2379 | f417ddd0627a8309 |   3.5.3 |  143 MB |     false |      false |         6 |      49669 |              49669 |        |
| https://10.74.252.238:2379 | 14230a911cfd1a54 |   3.5.3 |  144 MB |     false |      false |         6 |      49669 |              49669 |        |
| https://10.74.253.204:2379 | c6d662b5c9232e6e |   3.5.3 |  144 MB |      true |      false |         6 |      49669 |              49669 |        |
+----------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
sh-4.4# etcdctl member list -w table
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |           NAME            |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
| 14230a911cfd1a54 | started | master02.ocp4.example.com | https://10.74.252.238:2380 | https://10.74.252.238:2379 |      false |
| c6d662b5c9232e6e | started | master01.ocp4.example.com | https://10.74.253.204:2380 | https://10.74.253.204:2379 |      false |
| f417ddd0627a8309 | started | master03.ocp4.example.com | https://10.74.250.166:2380 | https://10.74.250.166:2379 |      false |
+------------------+---------+---------------------------+----------------------------+----------------------------+------------+
sh-4.4# exit
~~~

c. Confirm apiserver/controller/scheduler pod status:
~~~
$ oc get pods -n openshift-kube-apiserver | grep kube-apiserver
$ oc get pods -n openshift-kube-controller-manager | grep kube-controller-manager
$ oc get pods -n openshift-kube-scheduler | grep openshift-kube-scheduler
~~~

d.Confirm cluster operator status:
~~~
$ oc get co | grep -v '.True.*False.*False'
~~~

e.Confirm that the pod status is normal:
~~~
$ oc get po -A | grep -v 'Running\|Completed'
~~~

