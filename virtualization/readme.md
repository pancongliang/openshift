## Install and configure virtualization Operator

### Install virtualization Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="rhacs-operator"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/acs/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create virtualization instance  
* Create Central instance
