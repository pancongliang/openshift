
## Install and Configure Multi Cluster Engine Operator

### Install Multi Cluster Engine Operator

* To install the Operator using the default namespace, follow these steps:

  ```
  export CHANNEL_NAME="stable-2.8"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="multicluster-engine"

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/mce/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create Multi Cluster Engine Custom Resources

* Create the multi cluster engine with the following command:

  ```
  cat << EOF | oc apply -f -
  apiVersion: multicluster.openshift.io/v1
  kind: MultiClusterEngine
  metadata:
    name: multiclusterengine
    namespace: multicluster-engine
  spec: {}
  EOF
  ```

### Check Resources

* Check multi cluster engine Status
  ```
  oc get mce -o=jsonpath='{.items[0].status.phase}' -n multicluster-engine
  ```

* Check pod
  ```
  oc get pods -n open-cluster-management
  oc get pods -n open-cluster-management-agent
  oc get pods -n open-cluster-management-agent-addon
  ```

### Uninstalling

- Removing MultiClusterHub resources by using commands 
  ```
  oc delete multiclusterengine --all -n multicluster-engine
  ```

- Cleaning up artifacts before reinstalling
  ```
  oc get csv -n multicluster-engine | grep multicluster | awk '{print $1}' | xargs -I {} oc delete csv {} -n multicluster-engine
  oc delete sub multicluster-engine -n multicluster-engine
  ```
  
- If the multicluster engine custom resource is not being removed, remove any potential remaining artifacts by running the clean-up script.
  ```
  oc delete apiservice v1.admission.cluster.open-cluster-management.io v1.admission.work.open-cluster-management.io
  oc delete validatingwebhookconfiguration multiclusterengines.multicluster.openshift.io
  oc get mce --all -A

  oc delete mce --all -n multicluster-engine
   ```
