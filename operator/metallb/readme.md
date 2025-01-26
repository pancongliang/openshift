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
* Define Address Pool Range
  ```
  export ADDRESSES="10.184.134.135-10.184.134.136"
  ```
* Create the Address Pool
  ```
  oc create -f - <<EOF
  apiVersion: metallb.io/v1beta1
  kind: IPAddressPool
  metadata:
    name: example-l2
    namespace: metallb-system
  spec:
    addresses:
    - ${ADDRESSES}
  EOF
  ```

### Configure MetalLB with L2 Advertisement
* Configuring MetalLB with an L2 advertisement
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
