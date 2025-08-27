
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
$ WORKER_CNF_NODE=$(oc get nodes --selector=node-role.kubernetes.io/worker-cnf= -o jsonpath='{.items[0].metadata.name}')
$ ssh core@$WORKER_CNF_NODE lscpu | grep NUMA
NUMA node(s):                         2
NUMA node0 CPU(s):                    0-15
NUMA node1 CPU(s):                    16-31

cat << EOF | oc create -f -
apiVersion: performance.openshift.io/v2
kind: PerformanceProfile
metadata:
  name: performance
spec:
  cpu:
    isolated: "4-15,20-31"
    reserved: "0-3,16-19"
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
apiVersion: v1
kind: Namespace
metadata:
  name: dynamic-irq
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynamic-irq
  namespace: dynamic-irq
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
      nodeSelector:
        node-role.kubernetes.io/worker-cnf: ""
      containers:
      - name: dynamic-irq-pod
        image: "quay.io/openshift-kni/cnf-tests:4.9"
        command: ["sleep", "10h"]
        resources:
          requests:
            cpu: 12
            memory: "200M"
          limits:
            cpu: 12
            memory: "200M"
EOF
~~~


#### Identify the node that is running the deployment pod by running the following command
~~~
$ oc get po -n dynamic-irq -o wide
NAME                                          READY   STATUS    RESTARTS   AGE     IP             NODE
dynamic-irq-798559ff47-dxc65                  1/1     Running   0          62s     10.128.2.3     worker03.ocp.example.com
~~~


#### The available capacity is reduced because some resources have already been allocated to Guaranteed QoS pods
~~~ 
POD_NAME=$(oc get pod -n dynamic-irq -l app=dynamic-irq -o jsonpath='{.items[0].metadata.name}')
$ oc exec -it "$POD_NAME" -n dynamic-irq -- /bin/bash -c "grep Cpus_allowed_list /proc/self/status | awk '{print \$2}'"
4-15

$ oc get noderesourcetopologies.topology.node.k8s.io $WORKER_CNF_NODE -o json | \
jq '.zones[] | {Name: .name, Resources: (.resources[] | select(.name=="cpu") | {Name: .name, Capacity: .capacity, Allocatable: .allocatable, Available: .available})}'
{
  "Name": "node-0",
  "Resources": {
    "Name": "cpu",
    "Capacity": "16",
    "Allocatable": "12",
    "Available": "0"
  }
}
{
  "Name": "node-1",
  "Resources": {
    "Name": "cpu",
    "Capacity": "16",
    "Allocatable": "12",
    "Available": "12"
  }
}

$ oc get pod $POD_NAME -n dynamic-irq -o jsonpath="{ .status.qosClass }"
Guaranteed
~~~

