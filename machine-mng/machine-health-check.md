## Automatically replace failed OpenShift cluster nodes

### Configure Machine health checks

* View the current MachineSet and the corresponding relationship between Machine and Node,
  and select a MachineSet to create a MachineHealthCheck object.

  ```
  # The test environment contains two machinesets, of which copan-swqdc-worker-ap-northeast-2a machineset contains two machines
  $ oc get machineset -n openshift-machine-api
  NAME                                 DESIRED   CURRENT   READY   AVAILABLE   AGE
  copan-swqdc-worker-ap-northeast-2a   2         2         2       2           19h
  copan-swqdc-worker-ap-northeast-2b   1         1         1       1           19h
  copan-swqdc-worker-ap-northeast-2c   0         0                             19h
  copan-swqdc-worker-ap-northeast-2d   0         0                             19h
  
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:.metadata.name,MACHINE:.status.nodeRef.name |grep worker
  copan-swqdc-worker-ap-northeast-2a-p5gcv   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-vrmnq   ip-10-0-11-69.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-pzq57   ip-10-0-54-224.ap-northeast-2.compute.internal
  ```

* Create a MachineHealthCheck object
  ```
  $ export MACHINESET_NAME=copan-swqdc-worker-ap-northeast-2a   # Select a machineset containing two machines
  
  $ cat << EOF | oc apply -f -
  apiVersion: machine.openshift.io/v1beta1
  kind: MachineHealthCheck
  metadata:
    name: my-machine-health-check
    namespace: openshift-machine-api
  spec:
    selector:
      matchLabels:
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${MACHINESET_NAME} 
    unhealthyConditions:
    - type:    "Ready"
      timeout: "300s" 
      status: "False"
    - type:    "Ready"
      timeout: "300s" 
      status: "Unknown"
    maxUnhealthy: "50%"   # The machineset must contain two or more machines
  EOF
  ```

### Simulate node failures matched by MachineHealthCheck objects
* First confirm the node where the application pod is located to confirm the pod eviction process.
  ```
  $ oc -n test-1 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                           STATUS    NODE                                            IP
  mysql-6ddb7bf95f-kwr27        Running   ip-10-0-11-69.ap-northeast-2.compute.internal   10.131.2.19
  nginx-5bc755d967-wlpnv        Running   ip-10-0-11-69.ap-northeast-2.compute.internal   10.131.2.18
  postgresql-5687bd8948-65xg9   Running   ip-10-0-11-69.ap-northeast-2.compute.internal   10.131.2.7

  $ oc -n test-2 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                             STATUS    NODE                                             IP
  famous-quotes-67dc6cb8f-dnkgj   Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.8
  loadtest-cff78c6f6-774ql        Running   ip-10-0-11-69.ap-northeast-2.compute.internal    10.131.2.16
  todo-http-957579ff5-rfxxq       Running   ip-10-0-11-69.ap-northeast-2.compute.internal    10.131.2.1
  ```
  
* Simulate worker node failure
  ```
  $ oc get nodes --selector=node-role.kubernetes.io/worker=
  NAME                                             STATUS   ROLES    AGE     VERSION
  ip-10-0-11-69.ap-northeast-2.compute.internal    Ready    worker   15m     v1.27.10+c79e5e2
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready    worker   19m     v1.27.10+c79e5e2
  ip-10-0-54-224.ap-northeast-2.compute.internal   Ready    worker   7m30s   v1.27.10+c79e5e2

  $ oc debug node/ip-10-0-11-69.ap-northeast-2.compute.internal
  sh-4.4# chroot /host
  sh-5.1# sudo -i
  [root@ip-10-0-11-69 ~]# mkdir test   # Confirm node replacement when simulating node failure
  [root@ip-10-0-11-69 ~]# systemctl disable kubelet.service --now
  ```

### Verify automatic replacement of failed nodes

* The status of the faulty Worker node changes to NOTReady, SchedulingDisabled
  ```
  $ oc get node -l node-role.kubernetes.io/worker
  NAME                                             STATUS     ROLES    AGE   VERSION
  ip-10-0-11-69.ap-northeast-2.compute.internal    NotReady   worker   28m   v1.27.10+c79e5e2
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready      worker   32m   v1.27.10+c79e5e2
  ip-10-0-54-224.ap-northeast-2.compute.internal   Ready      worker   20m   v1.27.10+c79e5e2
  
  $ oc get node -l node-role.kubernetes.io/worker
  NAME                                             STATUS                        ROLES    AGE   VERSION
  ip-10-0-11-69.ap-northeast-2.compute.internal    NotReady,SchedulingDisabled   worker   29m   v1.27.10+c79e5e2
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready                         worker   33m   v1.27.10+c79e5e2
  ip-10-0-54-224.ap-northeast-2.compute.internal   Ready                         worker   21m   v1.27.10+c79e5e2
  ```
  
* At this time, there is a new item in the Machine list, which is in the `Provisioning` stage (it will then enter the Provisioned stage);
* and the Machine corresponding to the faulty node becomes the `Deleting` stage (then the Machine will be deleted and disappear).
  ```
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name
  NAME                                       PHASE          STATE     HOSTNAME
  copan-swqdc-master-0                       Running        running   ip-10-0-8-144.ap-northeast-2.compute.internal
  copan-swqdc-master-1                       Running        running   ip-10-0-34-137.ap-northeast-2.compute.internal
  copan-swqdc-master-2                       Running        running   ip-10-0-82-226.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-6z47j   Provisioning   pending   <none>
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running        running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-vrmnq   Deleting       running   ip-10-0-11-69.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-pzq57   Running        running   ip-10-0-54-224.ap-northeast-2.compute.internal
  ```
  
* The faulty node has been deleted at this time.
  ```
  $ oc get node -l node-role.kubernetes.io/worker
  NAME                                             STATUS   ROLES    AGE   VERSION
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready    worker   35m   v1.27.10+c79e5e2
  ip-10-0-54-224.ap-northeast-2.compute.internal   Ready    worker   23m   v1.27.10+c79e5e2
  ```
  
* Subsequently, the Worker node corresponding to the newly created Machine will be regenerated, and the status will change from `NOTReady` to `Ready`. In addition, the faulty node has been replaced by a new node and there is no history file.
  ```
  $ oc get node -l node-role.kubernetes.io/worker
  NAME                                             STATUS   ROLES    AGE   VERSION
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready    worker   37m   v1.27.10+c79e5e2
  ip-10-0-24-94.ap-northeast-2.compute.internal    Ready    worker   59s   v1.27.10+c79e5e2
  ip-10-0-54-224.ap-northeast-2.compute.internal   Ready    worker   25m   v1.27.10+c79e5e

  $ oc debug node/ip-10-0-24-94.ap-northeast-2.compute.internal 
  sh-4.4# chroot /host
  sh-5.1# sudo -i
  root@ip-10-0-24-94 ~]# ls -a
  .  ..  .bash_logout  .bash_profile  .bashrc  .ssh
  ```

* Finally, the failed Machine and Worker nodes in the cluster were restored to normal.
  ```
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name
  NAME                                       PHASE     STATE     HOSTNAME
  copan-swqdc-master-0                       Running   running   ip-10-0-8-144.ap-northeast-2.compute.internal
  copan-swqdc-master-1                       Running   running   ip-10-0-34-137.ap-northeast-2.compute.internal
  copan-swqdc-master-2                       Running   running   ip-10-0-82-226.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-6z47j   Running   running   ip-10-0-24-94.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running   running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-pzq57   Running   running   ip-10-0-54-224.ap-northeast-2.compute.internal
  ```

* During the node replacement process, due to the default mechanism of node failover being triggered (when the notReady state lasts for more than 5 ~ 6 minutes), the application pod will be rescheduled to other normal nodes.
  ```
  $ oc -n test-1 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  mysql-6ddb7bf95f-j5zt2        Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.18
  mysql-6ddb7bf95f-kwr27        Running   ip-10-0-11-69.ap-northeast-2.compute.internal    10.131.2.19
  nginx-5bc755d967-7kdst        Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.17
  nginx-5bc755d967-wlpnv        Running   ip-10-0-11-69.ap-northeast-2.compute.internal    10.131.2.18
  postgresql-5687bd8948-65xg9   Running   ip-10-0-11-69.ap-northeast-2.compute.internal    10.131.2.7
  postgresql-5687bd8948-ng22q   Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.11

  $ oc -n test-2 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                             STATUS    NODE                                             IP
  famous-quotes-67dc6cb8f-dnkgj   Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.8
  loadtest-cff78c6f6-774ql        Running   ip-10-0-11-69.ap-northeast-2.compute.internal    10.131.2.16
  loadtest-cff78c6f6-j2q4j        Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.13
  todo-http-957579ff5-rfxxq       Running   ip-10-0-11-69.ap-northeast-2.compute.internal    10.131.2.17
  todo-http-957579ff5-tcmlc       Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.12

  $ oc -n test-1 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                           STATUS    NODE                                             IP
  mysql-6ddb7bf95f-j5zt2        Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.18
  nginx-5bc755d967-7kdst        Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.17
  postgresql-5687bd8948-ng22q   Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.11

  $ oc -n test-2 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                             STATUS    NODE                                             IP
  famous-quotes-67dc6cb8f-dnkgj   Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.8
  loadtest-cff78c6f6-j2q4j        Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.13
  todo-http-957579ff5-tcmlc       Running   ip-10-0-54-224.ap-northeast-2.compute.internal   10.128.4.12
  ```
### Pod eviction rules when replacing failed nodes
* If the `MachineHealthCheck.spec.unhealthyConditions.timeout` value is less than the pod's default eviction time, the pod will be evicted early. 
  ```
  For example: `MachineHealthCheck.spec.unhealthyConditions.timeout:150s`
  will not wait until the default pod eviction time,but will start evicting pods around the 150s
  ```
* If the `MachineHealthCheck.spec.unhealthyConditions.timeout` value is greater than the pod's default eviction time, it will be evicted according to the pod's default eviction mechanism (5 ~ 6 minutes)

  ```
  For example: `MachineHealthCheck.spec.unhealthyConditions.timeout:600s`
  will evict the pod according to the pod’s default eviction mechanism (5 ~ 6 minutes)
  ```

