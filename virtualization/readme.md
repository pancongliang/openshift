## Install and configure virtualization Operator

### Install virtualization Operator
~~~
oc create -f - <<EOF 
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  source: redhat-operators
  installPlanApproval: "Automatic"
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  channel: stable
EOF
~~~

### Create HyperConverged
~~~
oc create -f - <<EOF 
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
EOF
~~~

### Check the pods in the openshift-cnv namespace
```
oc get pod -n openshift-cnv
```

