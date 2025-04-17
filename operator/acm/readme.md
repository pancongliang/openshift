

## Install and Configure Advanced Cluster Management Operator

### Install Advanced Cluster Management Operator

* To install the Operator using the default namespace, follow these steps:

  ```
  export CHANNEL_NAME="release-2.12"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="open-cluster-management"

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/acm/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create Advanced Cluster Management Custom Resources

* Create the multi cluster hub with the following command:

  ```
  cat << EOF | oc apply -f -
  apiVersion: operator.open-cluster-management.io/v1
  kind: MultiClusterHub
  metadata:
    name: multiclusterhub
    namespace: open-cluster-management
  spec: {}
  EOF
  ```

### Check Resources

* Check multi cluster hub Status
  ```
  oc get mch -o=jsonpath='{.items[0].status.phase}'
  ```

* Check pod
  ```
  oc get pods -n open-cluster-management-hub
  oc get pods -n open-cluster-management-agent
  oc get pods -n open-cluster-management-agent-addon
  ```
