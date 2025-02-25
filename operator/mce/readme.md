
## Install and Configure Multi Cluster Engine Operator

### Install Multi Cluster Engine Operator

* To install the Operator using the default namespace, follow these steps:

  ```
  export CHANNEL_NAME="stable-2.7"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="multicluster-engine"

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/mce/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create Multi Cluster Engine Custom Resources

* Create the Central instance with the following command:

  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/mce/02-multiclusterengine.yaml
  ```

### Check Resources

* Check MulticlusterEngine Status
  ```
  oc get mce -o=jsonpath='{.items[0].status.phase}'
  ```

* Check pod
  ```
  oc get pods -n open-cluster-management-hub
  oc get pods -n open-cluster-management-agent
  oc get pods -n open-cluster-management-agent-addon
  ```
