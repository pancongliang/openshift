## Install and configure MetalLB Operator

### Install MetalLB Operator

```
cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: metallb-operator
  namespace: metallb-system
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: metallb-operator-sub
  namespace: metallb-system
spec:
  channel: stable
  installPlanApproval: "Automatic"
  name: metallb-operator
  source:  redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Create an instance of MetalLB
```
cat << EOF | oc apply -f -
apiVersion: metallb.io/v1beta1
kind: MetalLB
metadata:
  name: metallb
  namespace: metallb-system
EOF
```

### Create an address pool
```
export ADDRESSES="10.184.134.180-10.184.134.182"
# or 
export ADDRESSES="10.184.134.135/24"

oc create -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example-l2
  namespace: metallb-system
spec:
  addresses:
  - ${ADDRESSES}
  autoAssign: true
  avoidBuggyIPs: true
EOF
```

### Configure MetalLB with L2 Advertisement
```
oc create -f - <<EOF 
apiVersion: metallb.io/v1beta1 
kind: L2Advertisement 
metadata: 
  name: l2advertisement 
  namespace: metallb-system 
spec: 
  ipAddressPools: 
   - example-l2
EOF
```
