## Applying autoscaling to an OpenShift Container Platform cluster

### Configure node automatic expansion

* Create a cluster autoscaler.
  ```
  $ cat << EOF | oc apply -f -
  apiVersion: "autoscaling.openshift.io/v1"
  kind: "ClusterAutoscaler"
  metadata:
    name: "default"
  spec:
    resourceLimits:
      cores:
        max: 128
        min: 8
      maxNodesTotal: 24
      memory:
        max: 512
        min: 8
    scaleDown:
      delayAfterAdd: 10m
      delayAfterDelete: 5m
      delayAfterFailure: 30s
      enabled: true
      unneededTime: 5m
  EOF
  ```

*  Before creating a machine autoscaler, first identify the set of machines to be autoscaled.
  ```
  $ oc get machineset -n openshift-machine-api
  NAME                                 DESIRED   CURRENT   READY   AVAILABLE   AGE
  copan-swqdc-worker-ap-northeast-2a   1         1         1       1           41h
  copan-swqdc-worker-ap-northeast-2b   1         1         1       1           41h
  copan-swqdc-worker-ap-northeast-2c   0         0                             41h
  copan-swqdc-worker-ap-northeast-2d   0         0                             41h

  $ export MACHINESET_NAME=copan-swqdc-worker-ap-northeast-2a
  ```

*  Create machine autoscaler.
  ```
  $ cat << EOF | oc apply -f -
  apiVersion: "autoscaling.openshift.io/v1beta1"
  kind: "MachineAutoscaler"
  metadata:
    name: "my-machine-autoscaler"
    namespace: "openshift-machine-api"
  spec:
    minReplicas: 1 
    maxReplicas: 12 
    scaleTargetRef: 
      apiVersion: machine.openshift.io/v1beta1
      kind: MachineSet 
      name: ${MACHINESET_NAME}
  EOF
  ```

### Verify auto-scaling nodes

* Create test pod
  ```
  $ oc new-project test
  $ oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

  $ oc patch deployment/nginx \
    --type='json' \
    --patch='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"limits":{"memory":"1Gi","cpu": 1},"requests":{"memory":"1Gi","cpu": 1}}}]'

  $ oc new-app --name hello-openshift --docker-image quay.io/redhattraining/hello-openshift

  $ oc patch deployment/hello-openshift \
    --type='json' \
    --patch='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"limits":{"memory":"1Gi","cpu": 1},"requests":{"memory":"1Gi","cpu": 1}}}]'

  $ oc new-app --name loadtest --docker-image quay.io/redhattraining/loadtest:v1.0

  $ oc patch deployment/loadtest \
    --type='json' \
    --patch='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"limits":{"memory":"1Gi","cpu": 1},"requests":{"memory":"1Gi","cpu": 1}}}]' 

  $ oc -n test get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                                STATUS    NODE                                             IP
  hello-openshift-5494bf6997-dh4m2   Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.104
  loadtest-686744898d-lts9h          Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.106
  nginx-655ddf5fb7-blg8j             Running   ip-10-0-32-243.ap-northeast-2.compute.internal   10.130.6.25
  ```
  
* Expand the number of Pod replicas to trigger the cluster auto-scaling function
  ```
  $ oc scale deployment/nginx --replicas=5
  $ oc scale deployment/hello-openshift --replicas=5
  $ oc scale deployment/loadtest --replicas=5
  ```

* Observe the node expansion process
  ```
  $ watch oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name
  NAME                                       PHASE         STATE     HOSTNAME
  copan-swqdc-master-0                       Running       running   ip-10-0-8-144.ap-northeast-2.compute.internal
  copan-swqdc-master-1                       Running       running   ip-10-0-34-137.ap-northeast-2.compute.internal
  copan-swqdc-master-2                       Running       running   ip-10-0-82-226.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-2cbr5   Provisioned   running   <none>
  copan-swqdc-worker-ap-northeast-2a-6wxs5   Provisioned   running   <none>
  copan-swqdc-worker-ap-northeast-2a-9fl4k   Provisioned   running   <none>
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running       running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-rsm6w   Provisioned   running   <none>
  copan-swqdc-worker-ap-northeast-2b-gqqlc   Running       running   ip-10-0-32-243.ap-northeast-2.compute.internal

  # After waiting for a while, the machine will automatically expand.
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name
  NAME                                       PHASE     STATE     HOSTNAME
  copan-swqdc-master-0                       Running   running   ip-10-0-8-144.ap-northeast-2.compute.internal
  copan-swqdc-master-1                       Running   running   ip-10-0-34-137.ap-northeast-2.compute.internal
  copan-swqdc-master-2                       Running   running   ip-10-0-82-226.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-2cbr5   Running   running   ip-10-0-11-77.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-6wxs5   Running   running   ip-10-0-5-82.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-9fl4k   Running   running   ip-10-0-19-29.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running   running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-rsm6w   Running   running   ip-10-0-18-241.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-gqqlc   Running   running   ip-10-0-32-243.ap-northeast-2.compute.internal

  $ oc get node -l node-role.kubernetes.io/worker
  NAME                                             STATUS   ROLES    AGE     VERSION
  ip-10-0-11-77.ap-northeast-2.compute.internal    Ready    worker   2m49s   v1.27.10+c79e5e2
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready    worker   22h     v1.27.10+c79e5e2
  ip-10-0-18-241.ap-northeast-2.compute.internal   Ready    worker   2m49s   v1.27.10+c79e5e2
  ip-10-0-19-29.ap-northeast-2.compute.internal    Ready    worker   110s    v1.27.10+c79e5e2
  ip-10-0-32-243.ap-northeast-2.compute.internal   Ready    worker   19h     v1.27.10+c79e5e2
  ip-10-0-5-82.ap-northeast-2.compute.internal     Ready    worker   108s    v1.27.10+c79e5e2

  $ oc -n test get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                                STATUS    NODE                                             IP
  hello-openshift-5494bf6997-79p6w   Running   ip-10-0-18-241.ap-northeast-2.compute.internal   10.131.8.7
  hello-openshift-5494bf6997-c95ws   Running   ip-10-0-19-29.ap-northeast-2.compute.internal    10.129.10.6
  hello-openshift-5494bf6997-dh4m2   Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.104
  hello-openshift-5494bf6997-kwdmp   Running   ip-10-0-19-29.ap-northeast-2.compute.internal    10.129.10.7
  hello-openshift-5494bf6997-pb6dz   Running   ip-10-0-18-241.ap-northeast-2.compute.internal   10.131.8.5
  loadtest-686744898d-2s24n          Running   ip-10-0-5-82.ap-northeast-2.compute.internal     10.130.10.8
  loadtest-686744898d-55vm4          Running   ip-10-0-11-77.ap-northeast-2.compute.internal    10.128.10.7
  loadtest-686744898d-lts9h          Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.106
  loadtest-686744898d-m9kgr          Running   ip-10-0-5-82.ap-northeast-2.compute.internal     10.130.10.7
  loadtest-686744898d-skrfq          Running   ip-10-0-11-77.ap-northeast-2.compute.internal    10.128.10.9
  nginx-655ddf5fb7-8k9b7             Running   ip-10-0-19-29.ap-northeast-2.compute.internal    10.129.10.5
  nginx-655ddf5fb7-blg8j             Running   ip-10-0-32-243.ap-northeast-2.compute.internal   10.130.6.25
  nginx-655ddf5fb7-hz8sw             Running   ip-10-0-18-241.ap-northeast-2.compute.internal   10.131.8.6
  nginx-655ddf5fb7-k4jdq             Running   ip-10-0-11-77.ap-northeast-2.compute.internal    10.128.10.8
  nginx-655ddf5fb7-x2tr4             Running   ip-10-0-32-243.ap-northeast-2.compute.internal   10.130.6.26
  ```

* Reducing the number of Pod copies triggers the cluster auto-scaling function
  ```
  $ oc scale deployment/hello-openshift --replicas=0
  $ oc scale deployment/loadtest --replicas=0
  ```

 * Observe the node shrinking process
  ```
  $ watch oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name
  NAME                                       PHASE      STATE     HOSTNAME
  copan-swqdc-master-0                       Running    running   ip-10-0-8-144.ap-northeast-2.compute.internal
  copan-swqdc-master-1                       Running    running   ip-10-0-34-137.ap-northeast-2.compute.internal
  copan-swqdc-master-2                       Running    running   ip-10-0-82-226.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-2cbr5   Running    running   ip-10-0-11-77.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-6wxs5   Running    running   ip-10-0-5-82.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-9fl4k   Running    running   ip-10-0-19-29.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running    running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-rsm6w   Deleting   running   ip-10-0-18-241.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-gqqlc   Running    running   ip-10-0-32-243.ap-northeast-2.compute.internal

  # After waiting for a period of time, the machine automatically shrinks to 3 units.
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name
  NAME                                       PHASE     STATE     HOSTNAME
  copan-swqdc-master-0                       Running   running   ip-10-0-8-144.ap-northeast-2.compute.internal
  copan-swqdc-master-1                       Running   running   ip-10-0-34-137.ap-northeast-2.compute.internal
  copan-swqdc-master-2                       Running   running   ip-10-0-82-226.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-9fl4k   Running   running   ip-10-0-19-29.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running   running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-gqqlc   Running   running   ip-10-0-32-243.ap-northeast-2.compute.internal

  $ oc get node -l node-role.kubernetes.io/worke
  NAME                                             STATUS   ROLES    AGE   VERSION
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready    worker   23h   v1.27.10+c79e5e2
  ip-10-0-19-29.ap-northeast-2.compute.internal    Ready    worker   44m   v1.27.10+c79e5e2
  ip-10-0-32-243.ap-northeast-2.compute.internal   Ready    worker   20h   v1.27.10+c79e5e2
  ```

* Observe the pod eviction process
  ```
  $ oc -n test get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                      STATUS    NODE                                             IP
  nginx-655ddf5fb7-8k9b7   Running   ip-10-0-19-29.ap-northeast-2.compute.internal    10.129.10.5
  nginx-655ddf5fb7-blg8j   Running   ip-10-0-32-243.ap-northeast-2.compute.internal   10.130.6.25
  nginx-655ddf5fb7-hz8sw   Running   ip-10-0-18-241.ap-northeast-2.compute.internal   10.131.8.6
  nginx-655ddf5fb7-k4jdq   Running   ip-10-0-11-77.ap-northeast-2.compute.internal    10.128.10.8
  nginx-655ddf5fb7-x2tr4   Running   ip-10-0-32-243.ap-northeast-2.compute.internal   10.130.6.26
  
  # After waiting for a while, some pods restarted on other nodes because the nodes were automatically deleted.
  $ oc -n test get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                      STATUS    NODE                                             IP
  nginx-655ddf5fb7-6psjb   Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.112
  nginx-655ddf5fb7-7g5xs   Running   ip-10-0-12-135.ap-northeast-2.compute.internal   10.130.2.110
  nginx-655ddf5fb7-8k9b7   Running   ip-10-0-19-29.ap-northeast-2.compute.internal    10.129.10.5
  nginx-655ddf5fb7-blg8j   Running   ip-10-0-32-243.ap-northeast-2.compute.internal   10.130.6.25
  nginx-655ddf5fb7-x2tr4   Running   ip-10-0-32-243.ap-northeast-2.compute.internal   10.130.6.26
  ```


```
  $ cat << EOF | oc apply -f -
  apiVersion: "autoscaling.openshift.io/v1"
  kind: "ClusterAutoscaler"
  metadata:
    name: "default"
  spec:
    podPriorityThreshold: 10 
    resourceLimits:
      cores:
        max: 128
        min: 8
      maxNodesTotal: 24
      memory:
        max: 512
        min: 8
    scaleDown:
      delayAfterAdd: 10m
      delayAfterDelete: 5m
      delayAfterFailure: 30s
      enabled: true
      unneededTime: 5m
  EOF

  $ cat << EOF | oc apply -f -
  apiVersion: scheduling.k8s.io/v1
  kind: PriorityClass
  metadata:
    name: low-priority
  value: 1
  preemptionPolicy: PreemptLowerPriority 
  globalDefault: false 
  description: "This priority class should be used for XYZ service pods only."
  EOF
  
  $ cat << EOF | oc apply -f -
  apiVersion: scheduling.k8s.io/v1
  kind: PriorityClass
  metadata:
    name: medium-priority
  value: 10
  preemptionPolicy: PreemptLowerPriority 
  globalDefault: false 
  description: "This priority class should be used for XYZ service pods only."
  EOF
  
  $ cat << EOF | oc apply -f -
  apiVersion: scheduling.k8s.io/v1
  kind: PriorityClass
  metadata:
    name: high-priority
  value: 1000
  preemptionPolicy: PreemptLowerPriority 
  globalDefault: false 
  description: "This priority class should be used for XYZ service pods only."
  EOF
  
  $ oc new-project test
  
  $ oc new-app --name high-priority --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  $ oc patch deployment/high-priority \
    --type='json' \
    --patch='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"limits":  {"memory":"1Gi","cpu": 1},"requests":{"memory":"1Gi","cpu": 1}}}]'
  $ oc patch deployment high-priority -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
  
  $ oc new-app --name medium-priority --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  $ oc patch deployment/medium-priority \
    --type='json' \
    --patch='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"limits":  {"memory":"1Gi","cpu": 1},"requests":{"memory":"1Gi","cpu": 1}}}]'
  $ oc patch deployment medium-priority -p '{"spec":{"template":{"spec":{"priorityClassName":"medium-priority"}}}}'
  
  
  $ oc new-app --name low-priority --docker-image quay.io/redhattraining/hello-openshift
  $ oc patch deployment low-priority -p '{"spec":{"template":{"spec":{"priorityClassName":"low-priority"}}}}'
  $ oc patch deployment/low-priority \
    --type='json' \
    --patch='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"limits":  {"memory":"1Gi","cpu": 1},"requests":{"memory":"1Gi","cpu": 1}}}]'
  $ oc patch deployment low-priority -p '{"spec":{"template":{"spec":{"priorityClassName":"low-priority"}}}}'
  
  $ oc new-app --name no-priority --docker-image quay.io/redhattraining/loadtest:v1.0
  $ oc patch deployment/no-priority \
    --type='json' \
    --patch='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"limits":  {"memory":"1Gi","cpu": 1},"requests":{"memory":"1Gi","cpu": 1}}}]' 
  
  $ oc get node -l node-role.kubernetes.io/worker
  NAME                                             STATUS   ROLES    AGE    VERSION
  ip-10-0-12-135.ap-northeast-2.compute.internal   Ready    worker   4d3h   v1.27.10+c79e5e2
  ip-10-0-32-243.ap-northeast-2.compute.internal   Ready    worker   4d     v1.27.10+c79e5e2
  
  $ oc scale deployment/no-priority --replicas=15
  
  $ oc get po -n test |grep no-priority
  NAME                               READY   STATUS    RESTARTS   AGE
  no-priority-544b74bb7d-dqjv6       0/1     Pending   0          11m
  no-priority-544b74bb7d-h677m       0/1     Pending   0          11m
  no-priority-544b74bb7d-j8lgf       1/1     Running   0          19m
  ···
  
  $ oc describe po no-priority-544b74bb7d-dqjv6 -n test
  Events:
    Type     Reason            Age                    From               Message
    ----     ------            ----                   ----               -------
    Warning  FailedScheduling  11m                    default-scheduler  0/5 nodes are available: 2 Insufficient cpu, 3   node(s) had untolerated taint {node-role.kubernetes.io/master: }. preemption: 0/5 nodes are available: 2 No   preemption victims found for incoming pod, 3 Preemption is not helpful for scheduling..
  
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.  providerStatus.instanceState,HOSTNAME:status.nodeRef.name |grep worker
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running   running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-gqqlc   Running   running   ip-10-0-32-243.ap-northeast-2.compute.internal
  
  $ oc scale deployment/low-priority --replicas=15
  $ oc get po |grep low-priority -n test
  low-priority-dc8966dfd-nvbql       0/1     Pending       0          7s
  low-priority-dc8966dfd-qd49v       0/1     Pending       0          7s
  low-priority-dc8966dfd-s2tnr       1/1     Running       0          17m
  ···
  
  $ oc describe po low-priority-dc8966dfd-nvbql -n test
  Events:
    Type     Reason            Age                    From               Message
    ----     ------            ----                   ----               -------
    Warning  FailedScheduling  11m                    default-scheduler  0/5 nodes are available: 2 Insufficient cpu, 3   node(s) had untolerated taint {node-role.kubernetes.io/master: }. preemption: 0/5 nodes are available: 1   Insufficient cpu, 1 No preemption victims found for incoming pod, 3 Preemption is not helpful for scheduling..
  
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.  providerStatus.instanceState,HOSTNAME:status.nodeRef.name |grep worker
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running   running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-gqqlc   Running   running   ip-10-0-32-243.ap-northeast-2.compute.internal
  
  $ oc scale deployment medium-priority  --replicas=5
  $ oc get po -n test |grep medium-priority
  medium-priority-5746d975c9-82bdn   1/1     Running   0          5m12s
  medium-priority-5746d975c9-8sncz   1/1     Running   0          5m12s
  medium-priority-5746d975c9-jg9r7   1/1     Running   0          5m12s
  medium-priority-5746d975c9-ssmqp   1/1     Running   0          39m
  medium-priority-5746d975c9-x46dz   1/1     Running   0          5m12s
  
  $ oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.  providerStatus.instanceState,HOSTNAME:status.nodeRef.name |grep worker
  copan-swqdc-worker-ap-northeast-2a-dt94x   Running   running   ip-10-0-29-151.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2a-p5gcv   Running   running   ip-10-0-12-135.ap-northeast-2.compute.internal
  copan-swqdc-worker-ap-northeast-2b-gqqlc   Running   running   ip-10-0-32-243.ap-northeast-2.compute.internal
  
  $ oc scale deployment/high-priority --replicas=5
  
  
  $ watch oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.  providerStatus.instanceState,HOSTNAME:status.nodeRef.name
  ```
