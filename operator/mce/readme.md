## Install and Configure Multi Cluster Engine Operator

### Install Multi Cluster Engine Operator

* To install the Operator using the default namespace, follow these steps:

  ```bash
  export SUB_CHANNEL="stable-2.10"

  cat << EOF | oc apply -f -
  apiVersion: v1
  kind: Namespace
  metadata:
    name: multicluster-engine
  ---
  apiVersion: operators.coreos.com/v1
  kind: OperatorGroup
  metadata:
    name: multicluster-engine
    namespace: multicluster-engine
  spec:
    targetNamespaces:
    - multicluster-engine
  ---
  apiVersion: operators.coreos.com/v1alpha1
  kind: Subscription
  metadata:
    name: multicluster-engine
    namespace: multicluster-engine
  spec:
    sourceNamespace: openshift-marketplace
    source: redhat-operators
    channel: ${SUB_CHANNEL}
    installPlanApproval: "Automatic"
    name: multicluster-engine
  EOF
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
  ```bash
  oc get mce -o=jsonpath='{.items[0].status.phase}' -n multicluster-engine
  ```

* Check pod
  ```bash
  oc get pods -n multicluster-engine
  oc get pods -n open-cluster-management
  oc get pods -n open-cluster-management-agent
  oc get pods -n open-cluster-management-agent-addon
  ```

### Uninstalling

- Removing MultiClusterHub resources by using commands 
  ```bash
  oc delete mce multiclusterengine -n multicluster-engine
  ```

- Remove Multicluster Engine and ClusterServiceVersion
  ```bash
  oc get csv -n multicluster-engine | grep multicluster | awk '{print $1}' | xargs -I {} oc delete csv {} -n multicluster-engine
  oc delete sub multicluster-engine -n multicluster-engine
  ```
  
- If the multicluster engine custom resource is not being removed, remove any potential remaining artifacts by running the clean-up script
  ```bash
  oc delete apiservice v1.admission.cluster.open-cluster-management.io v1.admission.work.open-cluster-management.io
  oc delete validatingwebhookconfiguration multiclusterengines.multicluster.openshift.io
  oc delete mce --all
  ```
