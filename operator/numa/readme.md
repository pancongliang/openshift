~~~
cat << EOF | oc create -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker-cnf
  name: worker-cnf
spec:
  machineConfigSelector:
    matchExpressions:
    - key: machineconfiguration.openshift.io/role
      operator: In
      values:
      - worker
      - worker-cnf
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/worker-cnf: ""
EOF

oc label node worker03.ocp.example.net node-role.kubernetes.io/worker-cnf=
~~~
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
          machineconfiguration.openshift.io/role: worker-cnf
EOF
~~~
~~~
$ oc get po -n openshift-numaresources 
NAME                                                READY   STATUS    RESTARTS   AGE
numaresources-controller-manager-744b67cb6d-s7f9f   1/1     Running   0          5h5m
numaresourcesoperator-worker-cnf-4464w              2/2     Running   0          45m
~~~
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

~~~
$ oc get po -n openshift-numaresources 
NAME                                                READY   STATUS    RESTARTS   AGE
numaresources-controller-manager-744b67cb6d-s7f9f   1/1     Running   0          5h5m
numaresourcesoperator-worker-cnf-4464w              2/2     Running   0          45m
secondary-scheduler-7cd657696c-nxk8b                1/1     Running   0          42m
~~~

~~~
cat << EOF | oc replace -f -
apiVersion: performance.openshift.io/v2
kind: PerformanceProfile
metadata:
  name: performance
spec:
  cpu:
    isolated: "3-15,19-31"
    reserved: "0-2,16-18"
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

~~~
cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: numa-deployment-1
  namespace: openshift-numaresources
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      schedulerName: topo-aware-scheduler 
      containers:
      - name: ctnr
        image: quay.io/openshifttest/hello-openshift:openshift
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: "100Mi"
            cpu: "2"
          requests:
            memory: "100Mi"
            cpu: "2"
      - name: ctnr2
        image: registry.access.redhat.com/rhel:latest
        imagePullPolicy: IfNotPresent
        command: ["/bin/sh", "-c"]
        args: [ "while true; do sleep 1h; done;" ]
        resources:
          limits:
            memory: "100Mi"
            cpu: "2"
          requests:
            memory: "100Mi"
            cpu: "2"
EOF
~~~

~~~
$ oc get po -n openshift-numaresources -o wide
NAME                                                READY   STATUS    RESTARTS   AGE    IP             NODE                       NOMINATED NODE   READINESS GATES
numa-deployment-1-588d54659c-sxhhk                  2/2     Running   0          36m    10.128.2.5     worker03.ocp.example.com   <none>           <none>
numaresources-controller-manager-744b67cb6d-s7f9f   1/1     Running   0          5h6m   10.129.1.167   master02.ocp.example.com   <none>           <none>
numaresourcesoperator-worker-cnf-4464w              2/2     Running   0          46m    10.128.2.3     worker03.ocp.example.com   <none>           2/2
secondary-scheduler-7cd657696c-nxk8b                1/1     Running   0          44m    10.129.1.223   master02.ocp.example.com   <none>           <none>
~~~

~~~
$ oc get pod numa-deployment-1-588d54659c-sxhhk -n openshift-numaresources -o jsonpath="{ .status.qosClass }"
Guaranteed
~~~


cat << EOF | oc create -f -
