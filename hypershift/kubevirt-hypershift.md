## Running an OpenShift Hosted Cluster with OpenShift Virtualization

### Introduction
* Hosted control planes for Red Hat OpenShift with the KubeVirt provider makes it possible to host OpenShift tenant clusters on bare metal machines at scale. It can be installed on an existing bare metal OpenShift cluster (OCP) environment allowing you to quickly provision multiple guest clusters using KubeVirt virtual machines. The current model allows running hosted control planes and KubeVirt virtual machines on the same underlying base OCP cluster. Unlike the standalone OpenShift cluster where some of the Kubernetes services in the control plane are running as systemd services, the control planes that HyperShift deploys are just another workload which can be scheduled on any available nodes placed in their dedicated namespaces. This post will show the detailed steps of installing HyperShift with the KubeVirt provider on an existing bare metal cluster and configuring the necessary components to launch guest clusters in a matter of minutes.


    <img src="https://github.com/user-attachments/assets/70b165a1-adb2-4de4-be9c-386883b0d31a" alt="image" width="70%">


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


2. **Configure Environment Variables**
   ```
   # Contains the namespace of HostedCluster and NodePool custom resources. The default namespace is clusters
   export HOSTED_CLUSTER_NAMESPACE="clusters" # Contains the namespace of HostedCluster and NodePool custom resources. The default namespace is clusters.
   export HOSTED_CLUSTER_NAME="my-cluster-1"
   export HOSTED_CONTROL_PLANE_NAMESPACE="$HOSTED_CLUSTER_NAMESPACE-$HOSTED_CLUSTER_NAME"
   export OCP_VERSION="4.16.12"
   export PULL_SECRET="$HOME/pull-secret" 
   export MEM="8Gi"
   export CPU="2"
   export WORKER_COUNT="2"
   ```

3. **Create the Hosted Cluster**
   ```
   # oc new-project $HOSTED_CLUSTER_NAMESPACE
   
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
     #--root-volume-storage-class <root_volume_storage_class>
     #--root-volume-size <volume_size>
     #--infra-storage-class-mapping=<infrastructure_storage_class>/<hosted_storage_class> # Mapping KubeVirt CSI storage classes
     #--infra-volumesnapshot-class-mapping=<infrastructure_volume_snapshot_class>/<hosted_volume_snapshot_class>
     #--base-domain <base-domain>
   ```

4. **Monitor Resources**
   ```
   oc wait --for=condition=Ready --namespace $HOSTED_CONTROL_PLANE_NAMESPACE vm --all --timeout=600s
   
   oc get vm -n $HOSTED_CONTROL_PLANE_NAMESPACE
   oc get pvc -n $HOSTED_CONTROL_PLANE_NAMESPACE
   oc get nodepool -n $HOSTED_CONTROL_PLANE_NAMESPACE
   ```

5. **Examine the Hosted Cluster**
   - Verify the status of guest cluster:
     ```
     oc get hc -A
     ```
   - Inspect the control plane pods:
     ```
     oc get pod -n $HOSTED_CONTROL_PLANE_NAMESPACE
     ```
   - Check the status of VMs:
     ```
     oc get vm -n $HOSTED_CONTROL_PLANE_NAMESPACE
     ```

6. **Scaling a node pool**
     ```
     oc get nodepool -n $HOSTED_CLUSTER_NAMESPACE

     oc -n $HOSTED_CLUSTER_NAMESPACE scale nodepool $HOSTED_CLUSTER_NAME --replicas=3
     ```

7. **Adding node pools**
     ```
     export NODEPOOL_NAME=${CLUSTER_NAME}-example
     export WORKER_COUNT="2"
     export MEM="6Gi"
     export CPU="4"
     export DISK="16"
     
     hcp create nodepool kubevirt \
       --cluster-name $HOSTED_CLUSTER_NAME \
       --name $NODEPOOL_NAME \
       --node-count $WORKER_COUNT \
       --memory $MEM \
       --cores $CPU \
       --root-volume-size $DISK

     oc get nodepools --namespace $HOSTED_CLUSTER_NAMESPACE
     ```    
####  Accessing a hosted cluster
* Generate Kubeconfig file and access the customer cluster
   ```
   hcp create kubeconfig --name="$HOSTED_CLUSTER_NAME" > "$HONME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig"
   # or
   oc extract -n $HOSTED_CLUSTER_NAMESPACE secret/${HOSTED_CLUSTER_NAME}-admin-kubeconfig --to=- > $HONME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   
   export KUBECONFIG=$HONME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   ```
* Log in to the Guest Cluster using the Kubeadmin account
   ```
   export HOSTED_CLUSTER_API=https://$(oc get hostedcluster -n $HOSTED_CLUSTER_NAMESPACE ${HOSTED_CLUSTER_NAME} -ojsonpath={.status.controlPlaneEndpoint.host}):6443
   export KUBEADMIN_PASSWORD=$(oc get -n $HOSTED_CLUSTER_NAMESPACE secret/${HOSTED_CLUSTER_NAME}-kubeadmin-password --template='{{ .data.password }}' | base64 -d)

   oc login $HOSTED_CLUSTER_API -u kuebadmin -p $KUBEADMIN_PASSWORD
   ```

* Log in to the Guest Cluster OCP Console using the kubeadmin account
   ```
   oc get route -n $HOSTED_CONTROL_PLANE_NAMESPACE oauth -o jsonpath='https://{.spec.host}'
   echo "https://console-openshift-console.apps.$HOSTED_CLUSTER_NAME.$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')"

   oc get -n $HOSTED_CLUSTER_NAMESPACE secret/${HOSTED_CLUSTER_NAME}-kubeadmin-password --template='{{ .data.password }}' | base64 -d
   ```

#### Quickly switch kubeconfig between OCP Hub and Hypershift
*  Quickly switch kubeconfig through alias
   ```
   echo "alias ctx1='export KUBECONFIG=/$HOME/.kube/hub-kubeconfig'" >> ~/.bashrc
   echo "alias ctx2='export KUBECONFIG=/$HOME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig'" >> ~/.bashrc
   source ~/.bashrc
   ```
   
*  Quickly switch environments through context   
   ```
   export KUBECONFIG=/$HOME/hub-kubeconfig:/$HOME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   oc config view --merge --flatten > /$HOME/kubeconfig
   export KUBECONFIG=/$HOME/kubeconfig
   
   oc config get-contexts
   oc config use-context <name>
   ```


#### Configuring HTPasswd-based user authentication
1. **Create a file with the username and password**
   ```
   htpasswd -b -c users.htpasswd admin redhat
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
   oc adm policy add-cluster-role-to-user cluster-admin admin --kubeconfig=$HOME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   ```
   
7. **Access Verification**
   ```
   export HOSTED_CLUSTER_API=https://$(oc get hostedcluster -n $HOSTED_CLUSTER_NAMESPACE ${HOSTED_CLUSTER_NAME} -ojsonpath={.status.controlPlaneEndpoint.host}):6443

   unset KUBECONFIG
   oc login $HOSTED_CLUSTER_API -u admin -p redhat
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
