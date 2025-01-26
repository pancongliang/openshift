## Install and configure virtualization Operator

### Install virtualization Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export STARTING_CSV="kubevirt-hyperconverged-operator.v4.16.5"    # export STARTING_CSV="kubevirt-hyperconverged-operator.v4.17.3"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-cnv"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/virtualization/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create HyperConverged
* Create HyperConverged
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/virtualization/02-hyperconverged.yaml


  oc get pod -n openshift-cnv
  ```

