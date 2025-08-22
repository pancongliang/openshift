
#### Create a new MachineConfigPool to bind the CNF node
~~~
cat << EOF | oc replace -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: worker-cnf
  labels:
    pools.operator.machineconfiguration.openshift.io/worker-cnf: ""
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,worker-cnf]} 
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/worker-cnf: "" 
EOF
~~~

#### Label a node to join the worker-cnf MCP
~~~
oc label node worker03.ocp.example.com node-role.kubernetes.io/worker-cnf=
~~~

#### Install the NUMA Resources Operator
~~~
cat << EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-numaresources
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: numaresources-operator
  namespace: openshift-numaresources
spec:
  targetNamespaces:
  - openshift-numaresources
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: numaresources-operator
  namespace: openshift-numaresources
spec:
  channel: "4.16"
  name: numaresources-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
~~~

#### Create the NUMAResourcesOperator custom resource
~~~
cat << EOF | oc create -f -
apiVersion: nodetopology.openshift.io/v1
kind: NUMAResourcesOperator
metadata:
  name: numaresourcesoperator
spec:
  nodeGroups:
    - machineConfigPoolSelector:
        matchLabels:
          pools.operator.machineconfiguration.openshift.io/worker-cnf: "" 
EOF
~~~

#### After a few minutes, run the following command to verify that the required resources deployed successfully
~~~
$ oc get all -n openshift-numaresources
NAME                                                    READY   STATUS    RESTARTS   AGE
pod/numaresources-controller-manager-744b67cb6d-s7f9f   1/1     Running   0          1h
pod/numaresourcesoperator-worker-cnf-dqd4s              2/2     Running   0          29s
~~~

#### Create the NUMAResourcesScheduler custom resource that deploys the NUMA-aware custom pod scheduler
~~~
cat << EOF | oc create -f -
apiVersion: nodetopology.openshift.io/v1
kind: NUMAResourcesScheduler
metadata:
  name: numaresourcesscheduler
spec:
  imageSpec: "registry.redhat.io/openshift4/noderesourcetopology-scheduler-rhel9:v4.16"
EOF
~~~

#### After a few seconds, run the following command to confirm the successful deployment of the required resources
~~~
$ oc get all -n openshift-numaresources
NAME                                                    READY   STATUS    RESTARTS   AGE
pod/numaresources-controller-manager-744b67cb6d-s7f9f   1/1     Running   0          1h
pod/numaresourcesoperator-worker-cnf-dqd4s              2/2     Running   0          50s
pod/secondary-scheduler-7cd657696c-kjmql                1/1     Running   0          2s
~~~

#### Configuring a Single NUMA Node Policy Using a PerformanceProfile
~~~
cat << EOF | oc create -f -
apiVersion: performance.openshift.io/v2
kind: PerformanceProfile
metadata:
  name: performance
spec:
  cpu:
    isolated: "3-15,19-31"
    reserved: "0-2,16-18"
  machineConfigPoolSelector:
    pools.operator.machineconfiguration.openshift.io/worker-cnf: "" 
  nodeSelector:
    node-role.kubernetes.io/worker-cnf: ""
  numa:
    topologyPolicy: single-numa-node 
  realTimeKernel:
    enabled: true
  workloadHints:
    highPowerConsumption: true
    perPodPowerManagement: false
    realTime: true
EOF
~~~

#### Get the name of the NUMA-aware scheduler that is deployed in the cluster by running the following command
~~~
oc get numaresourcesschedulers.nodetopology.openshift.io numaresourcesscheduler -o json | jq '.status.schedulerName'
~~~


#### Create a Deployment CR that uses scheduler named topo-aware-scheduler, for example
~~~
cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynamic-irq
  namespace: openshift-numaresources
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dynamic-irq
  template:
    metadata:
      labels:
        app: dynamic-irq
    spec:
      schedulerName: topo-aware-scheduler
      containers:
      - name: dynamic-irq-pod
        image: "quay.io/openshift-kni/cnf-tests:4.9"
        command: ["sleep", "10h"]
        resources:
          requests:
            cpu: 2
            memory: "200M"
          limits:
            cpu: 2
            memory: "200M"
EOF
~~~


#### Identify the node that is running the deployment pod by running the following command
~~~
$ oc get po -n openshift-numaresources -o wide
NAME                                          READY   STATUS    RESTARTS   AGE     IP             NODE
dynamic-irq-798559ff47-blkq2                  1/1     Running   0          62s     10.128.2.3     worker03.ocp.example.com
~~~


#### The available capacity is reduced because some resources have already been allocated to Guaranteed QoS pods
~~~ 
POD_NAME=$(oc get pod -n openshift-numaresources -l app=dynamic-irq -o jsonpath='{.items[0].metadata.name}')
oc exec -it "$POD_NAME" -n openshift-numaresources -- /bin/bash -c "grep Cpus_allowed_list /proc/self/status | awk '{print \$2}'"

oc describe noderesourcetopologies.topology.node.k8s.io worker03.ocp.example.com
···
Zones:
  Costs:
    Name:   node-0
    Value:  10
    Name:   node-1
    Value:  20
  Name:     node-0
  Resources:
    Allocatable:  13
    Available:    11
    Capacity:     16
    Name:         cpu
    Allocatable:  32596250624
    Available:    32396250624
    Capacity:     33749684224
    Name:         memory
  Type:           Node
  Costs:
    Name:   node-0
    Value:  20
    Name:   node-1
    Value:  10
  Name:     node-1
  Resources:
    Allocatable:  13
    Available:    13
    Capacity:     16
    Name:         cpu
    Allocatable:  33771720704
    Available:    33771720704
    Capacity:     33771720704
    Name:         memory
  Type:           Node

oc get pod $POD_NAME -n openshift-numaresources -o jsonpath="{ .status.qosClass }"
Guaranteed
~~~

