

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

* Run the following command to get the custom resource. It can take up to 10 minutes for the MultiClusterHub custom resource status to display as Running in the status.phase field after you run the command
  ```
  oc get mch -o=jsonpath='{.items[0].status.phase}' -n open-cluster-management
  oc get mce -o=jsonpath='{.items[0].status.phase}' -n multicluster-engine
  ```

* Check pod
  ```
  oc get pods -n multicluster-engine
  oc get pods -n open-cluster-management
  oc get pods -n open-cluster-management-agent
  oc get pods -n open-cluster-management-agent-addon
  ```

### Uninstalling

- Removing MultiClusterHub resources by using commands 
  ```
  oc delete mch multiclusterhub -n open-cluster-management
  oc patch mch multiclusterhub -n open-cluster-management -p '{"metadata":{"finalizers":[]}}' --type=merge
  ```

- Cleaning up artifacts before reinstalling
  ```
  ACM_NAMESPACE=open-cluster-management
  oc delete mch --all -n $ACM_NAMESPACE
  oc delete apiservice v1.admission.cluster.open-cluster-management.io v1.admission.work.open-cluster-management.io
  oc delete clusterimageset --all
  oc delete clusterrole multiclusterengines.multicluster.openshift.io-v1-admin multiclusterengines.multicluster.openshift.io-v1-crdview multiclusterengines.multicluster.openshift.io-v1-edit multiclusterengines.multicluster.openshift.io-v1-view open-cluster-management:addons:application-manager open-cluster-management:admin-aggregate open-cluster-management:cert-policy-controller-hub open-cluster-management:cluster-manager-admin-aggregate open-cluster-management:config-policy-controller-hub open-cluster-management:edit-aggregate open-cluster-management:policy-framework-hub open-cluster-management:view-aggregate
  oc delete crd klusterletaddonconfigs.agent.open-cluster-management.io placementbindings.policy.open-cluster-management.io policies.policy.open-cluster-management.io userpreferences.console.open-cluster-management.io discoveredclusters.discovery.open-cluster-management.io discoveryconfigs.discovery.open-cluster-management.io
  oc delete mutatingwebhookconfiguration ocm-mutating-webhook managedclustermutators.admission.cluster.open-cluster-management.io multicluster-observability-operator
  oc delete validatingwebhookconfiguration channels.apps.open.cluster.management.webhook.validator application-webhook-validator multiclusterhub-operator-validating-webhook ocm-validating-webhook multicluster-observability-operator multiclusterengines.multicluster.openshift.io
  ```

- Remove Multicluster Engine and ClusterServiceVersion
  ```
  oc get csv -n open-cluster-management | grep advanced-cluster-management | awk '{print $1}' | xargs -I {} oc delete csv {} -n open-cluster-management
  oc delete sub advanced-cluster-management -n open-cluster-management
  ```

- Remove Project
  ```
  oc delete ns open-cluster-management open-cluster-management-agent open-cluster-management-agent-addon multicluster-engine hive
  oc delete ns local-cluster clusters
  oc delete managedclusteraddons.addon.open-cluster-management.io --all -n local-cluster
  oc delete manifestworks.work.open-cluster-management.io --all -n local-cluster
  oc delete rolebindings.authorization.openshift.io --all -n local-cluster
  oc delete rolebindings.rbac.authorization.k8s.io --all -n local-cluster
  oc delete rolebinding open-cluster-management:managedcluster:local-cluster:work -n local-cluster
  
  oc patch managedclusteraddons.addon.open-cluster-management.io hypershift-addon -n local-cluster -p '{"metadata":{"finalizers":[]}}' --type=merge
  oc patch manifestworks.work.open-cluster-management.io addon-hypershift-addon-deploy-0 -n local-cluster -p '{"metadata":{"finalizers":[]}}' --type=merge
  oc patch manifestworks.work.open-cluster-management.io local-cluster-klusterlet -n local-cluster -p '{"metadata":{"finalizers":[]}}' --type=merge
  oc patch manifestworks.work.open-cluster-management.io local-cluster-klusterlet-crds -n local-cluster -p '{"metadata":{"finalizers":[]}}' --type=merge
  oc patch rolebindinopen-cluster-management:managedcluster:local-cluster:work -n local-cluster  -p '{"metadata":{"finalizers":[]}}' --type=merge
  ```
