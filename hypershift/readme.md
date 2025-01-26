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
   export HOSTED_CLUSTER_NAMESPACE="clusters"
   oc new-project $HOSTED_CLUSTER_NAMESPACE
   ```

3. **Configure Environment Variables**
   ```
   export HOSTED_CLUSTER_NAME=my-cluster-1
   export OCP_VERSION=4.16.12
   export PULL_SECRET="$HOME/pull-secret" 
   export MEM="8Gi"
   export CPU="2"
   export WORKER_COUNT="2"
   ```

4. **Create the Hosted Cluster**
   ```
   hcp create cluster kubevirt \
     --name $HOSTED_CLUSTER_NAME \
     --release-image quay.io/openshift-release-dev/ocp-release:$OCP_VERSION-x86_64 \
     --node-pool-replicas $WORKER_COUNT \
     --pull-secret $PULL_SECRET \
     --memory $MEM \
     --cores $CPU \
     --auto-repair \
     --namespace $HOSTED_CLUSTER_NAMESPACE
     #--etcd-storage-class ocs-storagecluster-ceph-rbd \
     #--control-plane-availability-policy SingleReplica \
     #--infra-availability-policy SingleReplica
   ```

5. **Monitor Resources**
   ```
   oc wait --for=condition=Ready --namespace $HOSTED_CLUSTER_NAMESPACE-$HOSTED_CLUSTER_NAME vm --all --timeout=600s
   
   oc get vm -n $HOSTED_CLUSTER_NAMESPACE-$HOSTED_CLUSTER_NAME
   oc get pvc -n $HOSTED_CLUSTER_NAMESPACE-$HOSTED_CLUSTER_NAME
   oc get nodepool -n $HOSTED_CLUSTER_NAMESPACE
   ```

6. **Examine the Hosted Cluster**
   - Verify the status of guest cluster:
     ```
     oc get hc -A
     ```
   - Inspect the control plane pods:
     ```
     oc get pod -n $HOSTED_CLUSTER_NAMESPACE-$HOSTED_CLUSTER_NAME
     ```
   - Check the status of VMs:
     ```
     oc get vm -n $HOSTED_CLUSTER_NAMESPACE-$HOSTED_CLUSTER_NAME
     ```
     

####  Accessing a hosted cluster
1. **Generate Kubeconfig for Guest Cluster**
   ```
   hcp create kubeconfig --name="$HOSTED_CLUSTER_NAME" > "${HOSTED_CLUSTER_NAME}-kubeconfig"
   ```
   
2. **View worker nodes and in the guest cluster**
   ```
   oc --kubeconfig ${HOSTED_CLUSTER_NAME}-kubeconfig get nodes
   ```
   
3. **Verify monitoring and networking stacks**
   ```
   oc --kubeconfig ${HOSTED_CLUSTER_NAME}-kubeconfig get pod -A | grep 'prometh\|ovn\|ingress'
   ```

4. **View kubeadmin password for Guest Cluster OCP Console**
   ```
   oc get route -n clusters-my-cluster-1 oauth -o jsonpath='https://{.spec.host}'
echo "https://console-openshift-console.apps.$HOSTED_CLUSTER_NAME.$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')"

   oc get secret ${HOSTED_CLUSTER_NAME}-kubeadmin-password -n local-cluster --template='{{ .data.password }}' | base64 -d
   ```

####  Configuring HTPasswd-based user authentication
1. **Create a file with the username and password**
   ```
   htpasswd -b -c users.htpasswd admin password
   ```
   
2. **Create a Secret object from a file**
   ```
   oc create secret generic ${HOSTED_CLUSTER_NAME}-htpass-secret --from-file=htpasswd=users.htpasswd -n $HOSTED_CLUSTER_NAMESPACE
   ```
   
3. **Create an HTPasswd-based identityProvider configuration file**
   ```
   cat << EOF > patch.yaml
   spec:
     configuration:
       oauth:
         identityProviders:
           - htpasswd:
               fileData:
                 name: ${HOSTED_CLUSTER_NAME}-htpass-secret
             mappingMethod: claim
             name: my_htpasswd_provider
             type: HTPasswd
   EOF
   ```
   
4. **Use patch.yaml to update the hostedcluster configuration named $HOSTED_CLUSTER_NAME**
   ```
   oc patch hostedcluster ${HOSTED_CLUSTER_NAME} -n $HOSTED_CLUSTER_NAMESPACE --type merge --patch-file patch.yaml
   ```
   
5. **View oauth-openshift related pod updates**
   ```
   oc get pod -n $HOSTED_CLUSTER_NAME-${HOSTED_CLUSTER_NAME} | grep oauth-openshift -w
   ```
   
6. **Configuring access permissions for hosted cluster users**
   ```
   KUBECONFIG=$HOME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   oc adm policy add-cluster-role-to-user cluster-admin admin --kubeconfig=$HOME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   unset KUBECONFIG
   ```
   
7. **Access Verification**
   ```
   export HOSTED_CLUSTER_API=https://$(oc get hostedcluster -n $HOSTED_CLUSTER_NAMESPACE ${HOSTED_CLUSTER_NAME} -ojsonpath={.status.controlPlaneEndpoint.host}):6443

   oc login $HOSTED_CLUSTER_API -u admin -p password
   ```

8. **Get the hosted cluster's oauth and console urls**
   ```
   oc get route -n clusters-my-cluster-1 oauth -o jsonpath='https://{.spec.host}'
   echo "https://console-openshift-console.apps.$HOSTED_CLUSTER_NAME.$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')"
   ```
   
### Deleting a Hosted Cluster
1. **Deleting a Hosted Cluster**
   ```
   oc delete managedcluster $HOSTED_CLUSTER_NAME
   ```
2. **Destroy an HCP Hosted Cluster on KubeVirt**
   ```
   hcp destroy cluster kubevirt --name $HOSTED_CLUSTER_NAME
   ```
