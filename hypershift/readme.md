## Running an OpenShift Hosted Cluster with OpenShift Virtualization

### Benefits of Using the HyperShift KubeVirt Provider
- Enhanced resource utilization by hosting multiple control planes and clusters on the same bare metal infrastructure.
- Strong isolation by separating hosted control planes and guest clusters.
- Reduced cluster provisioning time by eliminating the need for bare metal node bootstrapping.
- Manage multiple OpenShift versions under the same base OCP cluster.

### Cluster Preparation
#### Requirements
- OCP 4.16+ running on 6 bare metal nodes (3 masters, 3 workers).
- Necessary operators and controllers:
  - OpenShift Data Foundation (ODF) with local storage devices
  - OpenShift Virtualization
  - MetalLB
  - Multicluster Engine (MCE)
  - Cluster Manager
  - HyperShift

### Installing OpenShift Data Foundation
1. Install OpenShift Data Foundation ([ODF](https://github.com/pancongliang/openshift/blob/main/storage/odf/readme.md)) using local storage devices.
2. Annotate a default storage class for HyperShift to persist VM workers and guest cluster etcd pods:
   ```
   oc patch storageclass ocs-storagecluster-ceph-rbd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

### Installing OpenShift Virtualization
- Install the OpenShift [Virtualization](https://github.com/pancongliang/openshift/blob/main/virtualization/readme.md) Operator.

### Installing MetalLB Operator
- Install the [MetalLB](https://github.com/pancongliang/openshift/blob/main/operator/metallb/readme.md) Operator.

### Configuring Multicluster Engine Operator
- Install the Multicluster Engine ([MCE](https://github.com/pancongliang/openshift/blob/main/operator/mce/readme.md)) Operator.

### Setting Up Cluster Manager
- The local-cluster ManagedCluster allows the MCE components to treat the cluster it runs on as a host for guest clusters:
  ```
  oc apply -f - <<EOF
  apiVersion: cluster.open-cluster-management.io/v1
  kind: ManagedCluster
  metadata:
    labels:
      local-cluster: "true"
    name: local-cluster
  spec:
    hubAcceptsClient: true
    leaseDurationSeconds: 60
  EOF
  ```
  > Note: The command might fail initially if the ManagedCluster CRD is not yet registered. Retry after a few minutes.

### Enabling HyperShift
1. Apply the following YAML to enable the HyperShift operator:
   ```
   oc apply -f - <<EOF
   apiVersion: addon.open-cluster-management.io/v1alpha1
   kind: ManagedClusterAddOn
   metadata:
     name: hypershift-addon
     namespace: local-cluster
   spec:
     installNamespace: open-cluster-management-agent-addon
   EOF
   ```
2. Verify the HyperShift operator pods are running in the "hypershift" namespace:
   ```
   oc get pods -n hypershift
   ```
3. AIngress wildcard routes are required since the guest cluster's base domain will be a subdomain of the infra cluster's `*apps` A record:
   ```
   oc patch ingresscontroller -n openshift-ingress-operator default --type=json -p '[{ "op": "add", "path": "/spec/routeAdmission", "value": {"wildcardPolicy": "WildcardsAllowed"}}]'
   ```

### Demo
####  Creating and Managing a Hosted Cluster

1. **Downlod the HCP CLI and pull-secret**
   ```
   curl -Lk $(oc get consoleclidownload hcp-cli-download -o json | jq -r '.spec.links[] | select(.text=="Download hcp CLI for Linux for x86_64").href') | tar xvz -C /usr/local/bin/
   ```
   Download the [pull secret](https://console.redhat.com/openshift/install/pull-secret).

2. **Create a Namespace for the Hosted Cluster**
   ```
   export NAMESPACE="clusters"
   oc new-project $NAMESPACE
   ```

3. **Configure Environment Variables**
   ```
   export PULL_SECRET="$HOME/pull-secret" 
   export MEM="8Gi"
   export CPU="2"
   export WORKER_COUNT="2"
   export KUBEVIRT_CLUSTER_NAME=my-cluster-1
   export OCP_VERSION=4.16.23
   ```

4. **Create the Hosted Cluster**
   ```
   hcp create cluster kubevirt \
     --name $KUBEVIRT_CLUSTER_NAME \
     --release-image quay.io/openshift-release-dev/ocp-release:$OCP_VERSION-x86_64 \
     --node-pool-replicas $WORKER_COUNT \
     --pull-secret $PULL_SECRET \
     --memory $MEM \
     --cores $CPU \
     --auto-repair \
     --namespace $NAMESPACE
   ```

5. **Monitor Resources**
   ```
   oc get vm -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME
   oc get pvc -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME
   oc get nodepool -n $NAMESPACE
   ```

6. **Generate Kubeconfig for Guest Cluster**
   ```
   hypershift create kubeconfig --name="$KUBEVIRT_CLUSTER_NAME" > "${KUBEVIRT_CLUSTER_NAME}-kubeconfig"
   ```

7. **Examine the Hosted Cluster**
   - Verify the status of guest cluster:
     ```
     oc get hc -A
     ```
   - Inspect the control plane pods:
     ```
     oc get pod -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME | grep 'kube-api\|etcd'
     ```
   - Check the status of VMs:
     ```
     oc get vm -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME
     ```
   - View worker nodes in the guest cluster:
     ```
     oc --kubeconfig ${KUBEVIRT_CLUSTER_NAME}-kubeconfig get nodes
     ```
   - Verify monitoring and networking stacks:
     ```
     oc --kubeconfig ${KUBEVIRT_CLUSTER_NAME}-kubeconfig get pod -A | grep 'prometh\|ovn\|ingress'
     ```

