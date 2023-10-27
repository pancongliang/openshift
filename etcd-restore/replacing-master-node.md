
## Replacing master node

### Test the recovery process
  - Environment 4.8(UPI)
  - Simulate 1 master downtime (master02.ocp4.example.com shuts down), and the cluster is available at this time:
  

### Backup etcd
* Confirm the unhealthy etcd member and backup the healthy etcd
  ```
  $ oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="EtcdMembersAvailable")]}{.message}{"\n"}'
  2 of 3 members are available, master02.ocp4.example.com is unhealthy

  $ ssh core@master01.ocp4.example.com
  $ sudo /usr/local/bin/cluster-backup.sh /home/core/assets/backup
  ...
  {"hash":1509591849,"revision":41172778,"totalKey":11537,"totalSize":171085824}
  snapshot db and kube resources are successfully saved to /home/core/assets/backup
  ```

### Delete unhealthy etcd members

* First select a etcd pod on a healthy node:
  ```
  $ oc get pods -n openshift-etcd | grep -v etcd-quorum-guard | grep etcd
  $ oc rsh -n openshift-etcd etcd-master01.ocp4.example.com
  ```

* View the member list and record unhealthy etcd member IDs and names:
  ```
  sh-4.2# etcdctl member list -w table
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  |        ID        | STATUS  |           NAME            |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  | 703682e53a2dd8e7 | stop    | master02.ocp4.example.com | https://10.74.249.135:2380 | https://10.74.249.135:2379 |      false |
  | 990eb461754095b1 | started | master01.ocp4.example.com | https://10.74.253.114:2380 | https://10.74.253.114:2379 |      false |
  | cc91e85b0b59e3e2 | started | master03.ocp4.example.com | https://10.74.249.217:2380 | https://10.74.249.217:2379 |      false |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  ```

* Delete unhealthy etcd members:
  ```
  sh-4.2# etcdctl member remove 703682e53a2dd8e7
  Member 703682e53a2dd8e7 removed from cluster daa0b0ddcfe3ece8
  sh-4.2# etcdctl member list -w table
  +------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
  |        ID        | STATUS  |            NAME             |        PEER ADDRS         |       CLIENT ADDRS        | IS LEARNER |
  +------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
  | 4bd29169d428398a | started | master01.ocp4.example.com | https://10.72.45.161:2380 | https://10.72.45.161:2379 |      false |
  | 7631738d05516ef5 | started | master03.ocp4.example.com | https://10.72.45.163:2380 | https://10.72.45.163:2379 |      false |
  +------------------+---------+-----------------------------+---------------------------+---------------------------+------------+
  ```

###  Delete unhealthy etcd secret and master node

* Delete unhealthy etcd secret
  ```
  $ oc get secret -n openshift-etcd |grep master02.ocp4.example.com 
    etcd-peer-master02.ocp4.example.com              kubernetes.io/tls                     2      72d
    etcd-serving-master02.ocp4.example.com           kubernetes.io/tls                     2      72d
    etcd-serving-metrics-master02.ocp4.example.com   kubernetes.io/tls                     2      72d

  $ oc delete secret etcd-peer-master02.ocp4.example.com \
                     etcd-serving-master02.ocp4.example.com
                     etcd-serving-metrics-master02.ocp4.example.com -n openshift-etcd 
  ```

* Delete unhealthy etcd master nodes:
  ```
  $ oc get node
  NAME                        STATUS     ROLES          AGE   VERSION
  master01.ocp4.example.com   Ready      master         72d   v1.21.6+b4b4813
  master02.ocp4.example.com   NotReady   master         72d   v1.21.6+b4b4813
  master03.ocp4.example.com   Ready      master         72d   v1.21.6+b4b4813
  worker01.ocp4.example.com   Ready      infra,worker   72d   v1.21.6+b4b4813
  worker02.ocp4.example.com   Ready      infra,worker   72d   v1.21.6+b4b4813
  worker03.ocp4.example.com   Ready      worker         72d   v1.21.6+b4b4813

  $ oc delete node master02.ocp4.example.com

  # If the secret is regenerated, you can delete the secret again after deleting master02）。
  $ oc get secret -n openshift-etcd |grep master02.ocp4.example.com 
  ```

### Reinstall master02 using master.ign file

* Use the same method as the initial installation of the ocp cluster, and install the master02 node separately without bootstrap
  ```
  coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.250.185:8080/pre/master.ign \
  ip=10.74.252.85::10.74.255.254:255.255.248.0:master02.ocp4.example.com::none \
  nameserver=10.74.250.185
  ```

* After master02 is started, approve the csr of the new node
  ```
  $ oc get csr
  NAME        AGE   SIGNERNAME                                    REQUESTOR                                                                   CONDITION
  csr-gtzqg   47s   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending

  $ oc get csr -o name | xargs oc adm certificate approve
  certificatesigningrequest.certificates.k8s.io/csr-gtzqg approved

  $ oc get csr
  NAME        AGE    SIGNERNAME                                    REQUESTOR                                                                   CONDITION
  csr-gtzqg   103s   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
  csr-wfvds   8s     kubernetes.io/kubelet-serving                 system:node:master02.ocp4.example.com                                       Pending

  $ oc get csr -o name | xargs oc adm certificate approve
  certificatesigningrequest.certificates.k8s.io/csr-wfvds approved

  $ oc get no
  NAME                        STATUS   ROLES          AGE     VERSION
  master01.ocp4.example.com   Ready    master         73d     v1.21.6+b4b4813
  master02.ocp4.example.com   Ready    master         3m33s   v1.21.6+b4b4813   #<-- New add
  master03.ocp4.example.com   Ready    master         72d     v1.21.6+b4b4813
  worker01.ocp4.example.com   Ready    infra,worker   72d     v1.21.6+b4b4813
  worker02.ocp4.example.com   Ready    infra,worker   72d     v1.21.6+b4b4813
  worker03.ocp4.example.com   Ready    worker         72d     v1.21.6+b4b4813
  ```

### Verify etcd is healthy
* Verify that all etcd pods are running properly
  ```
  $ oc get pods -n openshift-etcd | grep -v etcd-quorum-guard | grep etcd
  etcd-master01.ocp4.example.com                 4/4     Running     0          2m28s
  etcd-master02.ocp4.example.com                 4/4     Running     0          4m6s
  etcd-master03.ocp4.example.com                 4/4     Running     0          67s

  $ oc rsh -n openshift-etcd etcd-master02.ocp4.example.com
  sh-4.2# etcdctl member list -w table
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  |        ID        | STATUS  |           NAME            |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  | 57e8c51635340a67 | started | master02.ocp4.example.com | https://10.74.252.85:2380  | https://10.74.252.85:2379  |      false |
  | 990eb461754095b1 | started | master01.ocp4.example.com | https://10.74.253.114:2380 | https://10.74.253.114:2379 |      false |
  | cc91e85b0b59e3e2 | started | master03.ocp4.example.com | https://10.74.249.217:2380 | https://10.74.249.217:2379 |      false |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+

  $ oc get co | grep -v '.True.*False.*False'
  ```

### If the status of the ocp component is inconsistent or abnormal, force the component to be redeployed

* Verify that etcd of all nodes is consistent
  ```
  $ oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
  3 nodes are at revision 28

  # If inconsistent, force redeployment of etcd
  $ oc patch etcd cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge 
  ```
* Verify that Kube API Server of all nodes is consistent
  ```
  $ oc get kubeapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
  AllNodesAtLatestRevision
  3 nodes are at revision 29

  # If inconsistent, force redeployment of  Kube API Server
  $ oc patch kubeapiserver cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
  ```

* Verify that Kube Controller Manager of all nodes is consistent
  ```
  $ oc get kubecontrollermanager -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
  AllNodesAtLatestRevision
  3 nodes are at revision 7
  
  # If inconsistent, force redeployment of Kube Controller Manager
  $ oc patch kubecontrollermanager cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
  ```

* Verify that Kubernetes scheduler of all nodes is consistent
  ```
  $ oc get kubescheduler -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
  AllNodesAtLatestRevision
  3 nodes are at revision 8

  # If inconsistent, force redeployment of Kubernetes scheduler
  $ oc patch kubescheduler cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
  ```

* Check cluster status
  ```
  $ oc get no
  NAME                        STATUS   ROLES          AGE     VERSION
  master01.ocp4.example.com   Ready    master         73d     v1.21.6+b4b4813
  master02.ocp4.example.com   Ready    master         3m33s   v1.21.6+b4b4813
  master03.ocp4.example.com   Ready    master         72d     v1.21.6+b4b4813
  worker01.ocp4.example.com   Ready    infra,worker   72d     v1.21.6+b4b4813
  worker02.ocp4.example.com   Ready    infra,worker   72d     v1.21.6+b4b4813
  worker03.ocp4.example.com   Ready    worker         72d     v1.21.6+b4b4813

  $ oc get co | grep -v '.True.*False.*False'
  NAME  VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE

  $ oc get po -A | grep -v 'Running\|Completed'

  $ oc get pods -n openshift-etcd | grep -v etcd-quorum-guard | grep etcd
  etcd-master01.ocp4.example.com                 4/4     Running     0          2m28s
  etcd-master02.ocp4.example.com                 4/4     Running     0          4m6s
  etcd-master03.ocp4.example.com                 4/4     Running     0          67s

  $ oc rsh -n openshift-etcd etcd-master02.ocp4.example.com
  sh-4.2# etcdctl member list -w table
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  |        ID        | STATUS  |           NAME            |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  | 57e8c51635340a67 | started | master02.ocp4.example.com | https://10.74.252.85:2380  | https://10.74.252.85:2379  |      false |
  | 990eb461754095b1 | started | master01.ocp4.example.com | https://10.74.253.114:2380 | https://10.74.253.114:2379 |      false |
  | cc91e85b0b59e3e2 | started | master03.ocp4.example.com | https://10.74.249.217:2380 | https://10.74.249.217:2379 |      false |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  ```
