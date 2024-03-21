## Install and configure Node Health Check Operator and Self Node Remediation Operator

* Use the Node Health Check Operator to identify unhealthy nodes. The Operator uses the Self Node Remediation Operator to remediate the unhealthy nodes.

### Install the Health Check Operator, and the Self Node Remediation Operator will be automatically installed

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/node-health-check/01-operator.yaml | envsubst | oc apply -f -

  sleep 6
  
  oc patch installplan $(oc get ip -n node-health-check -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n node-health-check --type merge --patch '{"spec":{"approved":true}}'
  
  oc get ip -n node-health-check
  oc get sub -n node-health-check
  ```

### Create NodeHealthCheck object
* Create NodeHealthCheck object.
  ```
  cat << EOF | oc apply -f -
  apiVersion: remediation.medik8s.io/v1alpha1
  kind: NodeHealthCheck
  metadata:
    name: nodehealthcheck-sample
  spec:
    minHealthy: 51%
    remediationTemplate:
      apiVersion: self-node-remediation.medik8s.io/v1alpha1
      name: self-node-remediation-automatic-strategy-template
      namespace: node-health-check
      kind: SelfNodeRemediationTemplate
    selector:
      matchExpressions:
        - key: node-role.kubernetes.io/worker
          operator: Exists
    unhealthyConditions:
      - duration: 300s
        type: Ready
        status: 'False'
      - duration: 300s
        type: Ready
        status: Unknown
  EOF
  ```

### Simulate node failures

* First confirm the node where the application pod is located to confirm the pod eviction process.
  ```
  $ oc -n test get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                                STATUS    NODE                        IP
  hello-openshift-5dddf5dcfc-nhmv7   Running   worker01.ocp4.example.com   10.128.3.38
  mysql-5ddf97d4dc-6cqv4             Running   worker01.ocp4.example.com   10.128.3.39
  todo-http-65779b7f79-hvxw6         Running   worker01.ocp4.example.com   10.128.3.37
  ```

* Simulate worker01 node failure and create a test file for the node.
  ```
  $ oc get node -l node-role.kubernetes.io/worker
  NAME                        STATUS   ROLES    AGE   VERSION
  worker01.ocp4.example.com   Ready    worker   30d   v1.25.11+1485cc9
  worker02.ocp4.example.com   Ready    worker   30d   v1.25.11+1485cc9
  worker03.ocp4.example.com   Ready    worker   27d   v1.25.16+6df2177

  $ ssh core@worker01.ocp4.example.com sudo touch test.txt
  $ ssh core@worker01.ocp4.example.com sudo systemctl stop kubelet
  ```
  
* Then check the time when the node was last started.
  ```
  $ ssh core@worker01.ocp4.example.com sudo who -b
         system boot  2024-03-18 07:22
  ```

 ### Verify the restore process of failed nodes
 
* Check the status of the faulty node. At this time, the faulty node will be reboot for restore.
  ```
  $ oc get node worker01.ocp4.example.com -w
  NAME                        STATUS   ROLES    AGE   VERSION
  worker01.ocp4.example.com   Ready    worker   30d   v1.25.11+1485cc9
  worker01.ocp4.example.com   NotReady   worker   30d   v1.25.11+1485cc9
  worker01.ocp4.example.com   NotReady   worker   30d   v1.25.11+1485cc9
  worker01.ocp4.example.com   NotReady,SchedulingDisabled   worker   30d   v1.25.11+1485cc9
  worker01.ocp4.example.com   NotReady,SchedulingDisabled   worker   30d   v1.25.11+1485cc9

  $ ssh core@wworker01.ocp4.example.com
  "System is booting up. Unprivileged users are not permitted to log in yet. Please come back later. For technical details, see 
  pam_nologin(8)."
  Connection closed by 10.74.251.58 port 22

  $ oc get node worker01.ocp4.example.com -w
  NAME                        STATUS   ROLES    AGE   VERSION
  worker01.ocp4.example.com   Ready,SchedulingDisabled      worker   30d   v1.25.11+1485cc9
  worker01.ocp4.example.com   Ready                         worker   30d   v1.25.11+1485cc9

  $ oc describe NodeHealthCheck nodehealthcheck-sample
  Normal   Enabled             8m9s               NodeHealthCheck  [remediation] No issues found, NodeHealthCheck is enabled.
  Normal   DetectedUnhealthy   92s (x3 over 92s)  NodeHealthCheck  [remediation] Node matches unhealthy condition. Node "worker01.ocp4.example.com", condition type "Ready", condition status "Unknown"
  Normal   RemediationCreated  92s                NodeHealthCheck  [remediation] Created remediation object for node worker01.ocp4.example.com
  Normal   DetectedUnhealthy   33s (x5 over 3m37s)  NodeHealthCheck  [remediation] Node matches unhealthy condition. Node "worker01.ocp4.example.com", condition type "Ready", condition status "Unknown"
  Normal   RemediationRemoved  0s                   NodeHealthCheck  [remediation] Deleted remediation CR of kind SelfNodeRemediation with name worker01.ocp4.example.com
  ```  
* View the pod eviction process.
  ```
  $ oc -n test get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                                STATUS    NODE                        IP
  hello-openshift-5dddf5dcfc-nhmv7   Running   worker01.ocp4.example.com   10.128.3.38
  hello-openshift-5dddf5dcfc-rl5gg   Pending   worker02.ocp4.example.com   <none>
  mysql-5ddf97d4dc-6cqv4             Running   worker01.ocp4.example.com   10.128.3.39
  mysql-5ddf97d4dc-8d22d             Pending   worker02.ocp4.example.com   <none>
  todo-http-65779b7f79-hvxw6         Running   worker01.ocp4.example.com   10.128.3.37
  todo-http-65779b7f79-tnrt6         Pending   worker02.ocp4.example.com   <none>

  $ oc -n test get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                                STATUS    NODE                        IP
  hello-openshift-5dddf5dcfc-nhmv7   Running   worker01.ocp4.example.com   10.128.3.38
  hello-openshift-5dddf5dcfc-rl5gg   Running   worker02.ocp4.example.com   10.129.1.73
  mysql-5ddf97d4dc-6cqv4             Running   worker01.ocp4.example.com   10.128.3.39
  mysql-5ddf97d4dc-8d22d             Running   worker02.ocp4.example.com   10.129.1.85
  todo-http-65779b7f79-hvxw6         Running   worker01.ocp4.example.com   10.128.3.37
  todo-http-65779b7f79-tnrt6         Running   worker02.ocp4.example.com   10.129.1.88
  ```

  
* Check the worker node that simulated the fault again and confirm that it has just been rebooted based on the latest startup time.
  ```
  $ ssh core@worker01.ocp4.example.com sudo who -b
         system boot  2024-03-20 09:42
  ```

* Can confirm that previously created files still exist.
  ```
  $ ssh core@worker01.ocp4.example.com sudo ls
  test.txt
  ```
### Pod eviction rules when replacing failed nodes
* If the `NodeHealthCheck.spec.unhealthyConditions.duration` value is less than the pod's default eviction time, the pod will be evicted early. 
  ```
  For example: `NodeHealthCheck.spec.unhealthyConditions.duration:150s`
  will not wait until the default pod eviction time,but will start evicting pods around the 150s
  ```
* If the `NodeHealthCheck.spec.unhealthyConditions.duration` value is greater than the pod's default eviction time, it will be evicted according to the pod's default eviction mechanism (5 ~ 6 minutes)

  ```
  For example: `NodeHealthCheck.spec.unhealthyConditions.duration:600s`
  will evict the pod according to the pod’s default eviction mechanism (5 ~ 6 minutes)
  ```





