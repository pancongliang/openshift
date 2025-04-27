

## Install and Configure Advanced Cluster Management Operator

### Install Advanced Cluster Management Operator

* To install the Operator using the default namespace, follow these steps:

  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="open-cluster-management"

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/acm/01-oeprator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create Multi Cluster Hub Custom Resources

* Create the Multi Cluster Hub with the following command:

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
  oc get mch -o=jsonpath='{.items[0].status.phase}' -n open-cluster-management
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
  oc delete mch multiclusterhub -n open-cluster-management
  ```

- Remove Multicluster Engine and ClusterServiceVersion
  ```
  oc get csv -n open-cluster-management | grep multicluster | awk '{print $1}' | xargs -I {} oc delete csv {} -n multicluster-engine
  oc delete sub multicluster-engine -n multicluster-engine
  ```
  
- If the multicluster engine custom resource is not being removed, remove any potential remaining artifacts by running the clean-up script
  ```
  #!/bin/bash
  oc delete apiservice v1.admission.cluster.open-cluster-management.io v1.admission.work.open-cluster-management.io
  oc delete validatingwebhookconfiguration multiclusterengines.multicluster.openshift.io
  oc delete mce --all
  ```
