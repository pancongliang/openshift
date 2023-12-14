
## Restore tow master

### Test the recovery process
   - Environment 4.10(UPI)
   - Simulate the downtime of 2 masters (master02/03.ocp4.example.com is shut down). At this time, the cluster API is unavailable (the oc command cannot be used, and only the personal business pod service is normal):
   - Make etcd backup in advance, otherwise the inability to access kube-apiserver will result in an error message indicating that the backup cannot be performed. Although the backup can be forced by adding --force, there is no guarantee that the etcd backup data is complete.


### Environment introduction
* Environment introduction
  ```
  $ oc get clusterversion
  NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
  version   4.10.20   True        False         13d    Cluster version is 4.10.20

  $ oc get network cluster -o yaml | grep networkType
  networkType: OpenShiftSDN
  ```

### Backing up etcd data
* Backing up etcd data
  ```
  $ oc debug node/master02.ocp4.example.com
  sh-4.2# chroot /host
  sh-4.4# /usr/local/bin/cluster-backup.sh /home/core/assets/backup
  ···
  snapshot db and kube resources are successfully saved to /home/core/assets/backup

  sh-4.4# ls /home/core/assets/backup
  snapshot_2023-03-22_161630.db  static_kuberesources_2023-03-22_161630.tar.gz

  sh-4.4# scp -r /home/core/assets/backup/ root@bastion:/root/
  ```
  
### Simulate a failure environment
* Shut down non-recovery control plane hosts (master02/03) in order to simulate a failure environment
  ```
  $ ssh core@master02.ocp4.example.com sudo shutdown -h now
  $ ssh core@master03.ocp4.example.com sudo shutdown -h now

  $ oc get nodes
  Unable to connect to the server: EOF
  ```

### Restoring etcd data

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
  $ ssh core@master01.ocp4.example.com sudo systemctl restart kubelet.service
  ```

* Verify that the oc command is available and the recovery control plane host is in the Ready state
  ```
  [core@master01 ~]$ sudo -i
  [root@master01 ~]# export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
  [root@master01 ~]# oc get nodes
  NAME                        STATUS     ROLES                AGE     VERSION
  master01.ocp4.example.com   Ready      master               66d   v1.23.5+3afdacb  # It may take several minutes for the node to report its status
  master02.ocp4.example.com   NotReady   master               66d   v1.23.5+3afdacb
  master03.ocp4.example.com   NotReady   master               66d   v1.23.5+3afdacb
  worker01.ocp4.example.com   Ready      worker               66d   v1.23.5+3afdacb
  worker02.ocp4.example.com   Ready      worker,worker-rhel   66d   v1.23.12+8a6bfe4
  ```

* Verify that the etcd pod for a single container in the recovery control plane host has started successfully
  ```
  [root@master01 ~]# crictl ps | grep etcd | grep -v operator
  4b315ff3aeb94       d9a894cf8f2712af891b38b72885c4c9d3fd3e8185a3467a2f5e9c91554607cb   3 minutes ago    Running      etcd

  [root@master01 ~]# oc -n openshift-etcd get pods -l k8s-app=etcd
  NAME                             READY   STATUS    RESTARTS      AGE
  etcd-master01.ocp4.example.com   1/1     Running   0             8m58s
  etcd-master02.ocp4.example.com   4/4     Running   5 (11d ago)   66d
  etcd-master03.ocp4.example.com   4/4     Running   4             66d
  ```

* Verify etcd cluster status, there is currently only one member, no need to manually remove it
  ```
  $ oc rsh -n openshift-etcd etcd-master01.ocp4.example.com
  sh-4.2# etcdctl member list -w table
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  |        ID        | STATUS  |           NAME            |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  | c6d662b5c9232e6e | started | master01.ocp4.example.com | https://10.74.253.204:2380 | https://10.74.253.204:2379 |      false |
  +------------------+---------+---------------------------+----------------------------+----------------------------+------------+
  sh-4.4# exit
  ```
    
### (Optional) If it is an OVNKubernetes network plug-in environment, additional steps are required
* Because the steps are different between different versions of openshift, please refer to the [openshift docs](https://docs.openshift.com/container-platform/4.10/backup_and_restore/control_plane_backup_and_restore/disaster_recovery/scenario-2-restoring-cluster-state.html#dr-scenario-2-restoring-cluster-state_dr-restoring-cluster-state).


### Delete and recreate other non-recovery control plane machines
  
* Delete the secret of the etcd member on the non-recovery control plane host (master02/03)
  ```
  $ oc get secret -n openshift-etcd |grep master02.ocp4.example.com 
  etcd-peer-master02.ocp4.example.com              kubernetes.io/tls                     2      66d
  etcd-serving-master02.ocp4.example.com           kubernetes.io/tls                     2      66d
  etcd-serving-metrics-master02.ocp4.example.com   kubernetes.io/tls                     2      66d

  $ oc delete secret etcd-peer-master02.ocp4.example.com \
                     etcd-serving-master02.ocp4.example.com \
                     etcd-serving-metrics-master02.ocp4.example.com -n openshift-etcd 

  $ oc get secret -n openshift-etcd |grep master03.ocp4.example.com 
  etcd-peer-master03.ocp4.example.com              kubernetes.io/tls                     2      66d
  etcd-serving-master03.ocp4.example.com           kubernetes.io/tls                     2      66d
  etcd-serving-metrics-master03.ocp4.example.com   kubernetes.io/tls                     2      66d

  $ oc delete secret etcd-peer-master03.ocp4.example.com \
                     etcd-serving-master03.ocp4.example.com \
                     etcd-serving-metrics-master03.ocp4.example.com -n openshift-etcd
  ``` 

* Delete non-recovery control plane host:
  ```
  $ oc get nodes
  NAME                        STATUS     ROLES                AGE     VERSION
  master01.ocp4.example.com   Ready      master               66d   v1.23.5+3afdacb
  master02.ocp4.example.com   NotReady   master               66d   v1.23.5+3afdacb
  master03.ocp4.example.com   NotReady   master               66d   v1.23.5+3afdacb
  worker01.ocp4.example.com   Ready      worker               66d   v1.23.5+3afdacb
  worker02.ocp4.example.com   Ready      worker,worker-rhel   66d   v1.23.12+8a6bfe4

  $ oc delete node master02.ocp4.example.com
  $ oc delete node master03.ocp4.example.com

  # If the secret is regenerated, can delete the secret again after deleting the non-recovery control plane host(master02/03) 
  $ oc get secret -n openshift-etcd |grep master02.ocp4.example.com 
  $ oc get secret -n openshift-etcd |grep master03.ocp4.example.com 
  ```

### Reinstall the deleted non-recovery control plane host (master02/03)
* The same as the initial installation of ocp master, the following content is for reference only:
  ```
  # example:
  $ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/master.ign  
  ip=10.74.252.238::10.74.255.254:255.255.248.0:master02.ocp4.example.com:ens3:none
  nameserver=10.74.251.171

  $ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/master.ign  
  ip=10.74.250.166::10.74.255.254:255.255.248.0:master03.ocp4.example.com:ens3:none
  nameserver=10.74.251.171
  ```

### Approve the pending CSRs:

* Approve the pending CSRs:
  ```
  $ oc get csr
  NAME        AGE     SIGNERNAME                                      REQUESTOR                                                                     REQUESTEDDURATION   CONDITION
  csr-tw47q   8m6s    kubernetes.io/kube-apiserver-client-kubelet     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper     <none>              Pending
  csr-zcm86   2m10s   kubernetes.io/kube-apiserver-client-kubelet     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper     <none>              Pending 
  
  $ oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}  {{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
  certificatesigningrequest.certificates.k8s.io/csr-tw47q approved
  certificatesigningrequest.certificates.k8s.io/csr-zcm86 approved
  
  $ oc get csr
  NAME        AGE     SIGNERNAME                                      REQUESTOR                                                                     REQUESTEDDURATION   CONDITION
  csr-sg9hd   5m19s   kubernetes.io/kube-apiserver-client-kubelet     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper     <none>              Pending
  csr-wfn58   5s      kubernetes.io/kube-apiserver-client-kubelet     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper     <none>              Pending
  
  $ oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}  {{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
  certificatesigningrequest.certificates.k8s.io/csr-sg9hd approved
  certificatesigningrequest.certificates.k8s.io/csr-wfn58 approved
  
  $ oc get csr
  NAME        AGE     SIGNERNAME                                      REQUESTOR                                                                     REQUESTEDDURATION   CONDITION
  csr-57hkj   2s      kubernetes.io/kubelet-serving                   system:node:master02.  ocp4.example.com                                       <none>              Pending
  csr-tw47q   8m29s   kubernetes.io/kube-apiserver-client-kubelet     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper     <none>              Approved,Issued
  csr-z89qp   7s      kubernetes.io/kubelet-serving                   system:node:master03.  ocp4.example.com                                       <none>              Pending
  csr-zcm86   2m33s   kubernetes.io/kube-apiserver-client-kubelet     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper     <none>              Approved,Issued
  
  $ oc get csr -o name | xargs oc adm certificate approve
  certificatesigningrequest.certificates.k8s.io/csr-57hkj approved
  certificatesigningrequest.certificates.k8s.io/csr-tw47q approved
  certificatesigningrequest.certificates.k8s.io/csr-z89qp approved
  certificatesigningrequest.certificates.k8s.io/csr-zcm86 approved
  
  $ oc get no
  NAME                        STATUS   ROLES                AGE     VERSION
  master01.ocp4.example.com   Ready    master               66d     v1.23.5+3afdacb
  master02.ocp4.example.com   Ready    master               3m13s   v1.23.5+3afdacb
  master03.ocp4.example.com   Ready    master               3m7s    v1.23.5+3afdacb
  worker01.ocp4.example.com   Ready    worker               66d     v1.23.5+3afdacb
  worker02.ocp4.example.com   Ready    worker,worker-rhel   66d     v1.23.12+8a6bfe4
  ```

### Export the recovery kubeconfig file
* In a separate terminal window within the recovery host, export the recovery kubeconfig file by running the following command:
  ```
  [root@master01 ~]# export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost-recovery.kubeconfig  
  ```
  
### Turn off the quorum guard by entering the following command
* This command ensures that you can successfully re-create secrets and roll out the static pods.
  ```
  [root@master01 ~]# oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": {"useUnsupportedUnsafeNonHANonProductionUnstableEtcd": true}}}'

  $ oc get etcd/cluster -o yaml | grep unsupportedConfigOverrides -A1
  unsupportedConfigOverrides:
    useUnsupportedUnsafeNonHANonProductionUnstableEtcd: true
  ```

### Force etcd redeployment, then turn quorum guard back on

* Force etcd redeployment:
  ```
  $ oc patch etcd cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge 
  ```

* Turn the quorum guard back on by entering the following command:
  ```
  $ oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": null}}'
  $ oc get etcd/cluster -o yaml |grep unsupportedConfigOverrides
  ```  

* Verify all nodes are updated to the latest revision:
  
  In a terminal that has access to the cluster as a cluster-admin user, run the following command:
  ```
  $ oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}' 
  AllNodesAtLatestRevision
  3 nodes are at revision 19
  ```
*  Only when all the pods ETCD are on the same version should proceed to the next step. This process can take several minutes to complete.


### After etcd is redeployed, force redeployment of Kube APIServer, Kube Controller Manager, and Kube Scheduler
* Force a new rollout for the Kubernetes API server and wait all nodes are updated to the latest revision:
  ```
  # Force a new rollout for the Kubernetes API server:
  $ oc patch kubeapiserver cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge

  # Verify all nodes are updated to the latest revision:
  $ oc get kubeapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
  AllNodesAtLatestRevision
  3 nodes are at revision 23

  # Only when all the pods Kube APIServer are on the same version should you follow the next step. This process can take several minutes to complete.
  ```

  * Force a new rollout for the Kubernetes controller manager and wait all nodes are updated to the latest revision:
  ```
  # Force a new rollout for the Kubernetes controller manager:
  $ oc patch kubecontrollermanager cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge

  # Verify all nodes are updated to the latest revision
  $ oc get kubecontrollermanager -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
  AllNodesAtLatestRevision
  3 nodes are at revision 15

  # Only when all Controller Manager pods are on the same version should you proceed to the next step.
  ```

* Force a new rollout for the Kubernetes scheduler and wait all nodes are updated to the latest revision:
  ```
  # Force a new rollout for the Kubernetes scheduler:
  $ oc patch kubescheduler cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge

  # Verify all nodes are updated to the latest revision:
  $ oc get kubescheduler -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
  AllNodesAtLatestRevision
  3 nodes are at revision 15
  ```

### After the recovery is complete, verify that the cluster is normal
* Verify node status:
  ```
  $ oc get no
  NAME                        STATUS   ROLES                AGE   VERSION
  master01.ocp4.example.com   Ready    master               13d   v1.23.5+3afdacb
  master02.ocp4.example.com   Ready    master               51m   v1.23.5+3afdacb
  master03.ocp4.example.com   Ready    master               51m   v1.23.5+3afdacb
  worker01.ocp4.example.com   Ready    worker               13d   v1.23.5+3afdacb
  worker02.ocp4.example.com   Ready    worker               13d   v1.23.5+3afdacb
  worker03.ocp4.example.com   Ready    worker,worker-rhel   13d   v1.23.12+a57ef08
  ```

* Verify etcd pod status:
  ```
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
  ```

* Verify apiserver/controller/scheduler pod status:
  ```
  $ oc get pods -n openshift-kube-apiserver | grep kube-apiserver
  $ oc get pods -n openshift-kube-controller-manager | grep kube-controller-manager
  $ oc get pods -n openshift-kube-scheduler | grep openshift-kube-scheduler
  ```

* Verify cluster operator status:
  ```
  $ oc get co | grep -v '.True.*False.*False'
  ```

* Verify that the pod status is normal:
  ```
  $ oc get po -A | grep -v 'Running\|Completed'
  ```

