## Install and configure MetalLB Operator

### Install MetalLB Operator
* Install the Operator using the metallb-system namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="metallb-system"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/metallb/operator.yaml | envsubst | oc apply -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create an instance of MetalLB
* Create an instance of MetalLB
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
* Specify address pool
  ```
  export ADDRESSES="10.74.251.175-10.74.251.176"
  ```
* Create an address pool
  ```
  cat << EOF | envsubst | oc apply -f -
  apiVersion: metallb.io/v1alpha1
  kind: AddressPool
  metadata:
    namespace: metallb-system
    name: l2-addresspool
  spec:
    protocol: layer2
    addresses:
    - ${ADDRESSES}
    autoAssign: true
  EOF
  ```
