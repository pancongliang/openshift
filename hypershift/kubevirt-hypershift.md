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
1. Install [ODF](/storage/odf/readme.md) using local storage devices for Hypershift ETCD Storage, Node Root Volume Storage, and KubeVirt CSI Storage.
3. Annotate a default storage class for HyperShift to persist VM workers and guest cluster etcd pods:
   ```
   oc patch storageclass ocs-storagecluster-ceph-rbd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

### Installing OpenShift Virtualization
- Install the OpenShift [Virtualization](/virtualization/readme.md) Operator and use KubeVirt to create virtual machines (worker nodes) for the managed cluster.

### Installing MetalLB Operator
- Install the [MetalLB](/operator/metallb/readme.md) Operator to provide a network load balancer for the Hosted Clusters API.
   
### Configuring Multi Cluster Engine Operator
- Install the ACM or [MCE](/operator/mce/readme.md) Operator. The MCE Operator lifecycle manages the creation, import, administration, and destruction of Kubernetes clusters across various cloud providers, private clouds, and on-premises data centers.
  
### Setting Up Cluster Manager
- The local-cluster ManagedCluster allows the MCE components to treat the cluster it runs on as a host for guest clusters:
  > Note: The command might fail initially if the ManagedCluster CRD is not yet registered. Retry after a few minutes.
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
### Ingress and DNS configuration

#### Optional A: Default Ingress and DNS Behavior
* Configuring the default ingress and DNS for hosted control planes on OpenShift Virtualization:
   > By default, OpenShift clusters include an ingress controller that requires a wildcard DNS record. When using the KubeVirt provider with HyperShift, Hosted Clusters are created as subdomains of the RHACM hub's domain.  
   > For example, if the RHACM hub uses `*.apps.ocp4.example.com` as the default ingress domain, a Hosted Cluster named `my-cluster-1` will use a subdomain like `*.apps.my-cluster-1.ocp4.example.com` when deployed with the HyperShift KubeVirt provider.
   ```
   oc patch ingresscontroller -n openshift-ingress-operator default --type=json -p '[{ "op": "add", "path": "/spec/routeAdmission", "value": {"wildcardPolicy": "WildcardsAllowed"}}]'
   ```
   > **Note:**
   > When you use the default hosted cluster ingress, connectivity is limited to HTTPS traffic over port 443. Plain HTTP traffic over port 80 is rejected. This limitation applies to only the default ingress behavior.


#### Optional B: [Customized Ingress and DNS Behavior]
* [Deploying a hosted cluster that specifies the base domain](ingress-and-dns.md)
* [Official Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/hosted_control_planes/deploying-hosted-control-planes#hcp-virt-ingress-dns-custom)


### Demo
* This demo will create a hosted cluster with the KubeVirt platform using the default ingress and DNS.

####  Creating a hosted cluster with the KubeVirt platform

1. **Downlod the HCP CLI and pull-secret**
   ```
   curl -Lk $(oc get consoleclidownload hcp-cli-download -o json | jq -r '.spec.links[] | select(.text=="Download hcp CLI for Linux for x86_64").href') | tar xvz -C /usr/local/bin/
   ```
   
2. **Download the [pull secret](https://console.redhat.com/openshift/install/pull-secret)*


3. **Configure Environment Variables**
   ```
   export HOSTED_CLUSTER_NAMESPACE="clusters" # Contains the namespace of HostedCluster and NodePool custom resources. The default namespace is clusters.
   export HOSTED_CLUSTER_NAME="my-cluster-1"
   export HOSTED_CONTROL_PLANE_NAMESPACE="$HOSTED_CLUSTER_NAMESPACE-$HOSTED_CLUSTER_NAME"
   export OCP_VERSION="4.16.12"
   export PULL_SECRET="$HOME/pull-secret" 
   export MEM="8Gi"
   export CPU="2"
   export WORKER_COUNT="2"
   ```

4. **Create the Hosted Cluster**
   > **Note:**  
   > If do not provide any advanced storage configuration, the default storage class is used for the KubeVirt virtual machine (VM) images, the KubeVirt Container Storage Interface (CSI) mapping, and the etcd volumes.
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

5. **Monitor Resources**
   ```
   oc wait --for=condition=Ready --namespace $HOSTED_CONTROL_PLANE_NAMESPACE vm --all --timeout=600s
   ```

6. **Examine the Hosted Cluster**
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
   - Check the status of VMI:
     ```
     oc get vmi -n $HOSTED_CONTROL_PLANE_NAMESPACE
     ```
   - Check node pool
     ```
     oc get nodepool -n $HOSTED_CLUSTER_NAMESPACE
     ```
   - Check the dataVolume of VMs:
     ```
     oc get dataVolume -n $HOSTED_CONTROL_PLANE_NAMESPACE
     ```
   - Check the pvc used by etcd and vm:    
     ```
     oc get pvc -n $HOSTED_CONTROL_PLANE_NAMESPACE
     ```

####  Scaling and Adding a node pool

1. **Scaling a node pool**
     ```
     oc get nodepool -n $HOSTED_CLUSTER_NAMESPACE

     oc -n $HOSTED_CLUSTER_NAMESPACE scale nodepool $HOSTED_CLUSTER_NAME --replicas=3

     oc get vm -n $HOSTED_CONTROL_PLANE_NAMESPACE
     ```

2. **Adding node pools**
     ```
     export NODEPOOL_NAME=${HOSTED_CLUSTER_NAME}-work
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

     oc get vm -n $HOSTED_CONTROL_PLANE_NAMESPACE
     ```
     
####  Accessing a hosted cluster
* Generate Kubeconfig file and access the customer cluster
   ```
   hcp create kubeconfig --name="$HOSTED_CLUSTER_NAME" > "$HOME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig"
   # or
   oc extract -n $HOSTED_CLUSTER_NAMESPACE secret/${HOSTED_CLUSTER_NAME}-admin-kubeconfig --to=- > $HOME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   
   export KUBECONFIG=$HONME/.kube/${HOSTED_CLUSTER_NAME}-kubeconfig
   ```
* Log in to the Guest Cluster using the Kubeadmin account
   ```
   export HOSTED_CLUSTER_API=https://$(oc get hostedcluster -n $HOSTED_CLUSTER_NAMESPACE ${HOSTED_CLUSTER_NAME} -ojsonpath={.status.controlPlaneEndpoint.host}):6443
   export KUBEADMIN_PASSWORD=$(oc get -n $HOSTED_CLUSTER_NAMESPACE secret/${HOSTED_CLUSTER_NAME}-kubeadmin-password --template='{{ .data.password }}' | base64 -d)

   unset KUBECONFIG
   oc login $HOSTED_CLUSTER_API -u kubeadmin -p $KUBEADMIN_PASSWORD
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
   oc get pod -n $HOSTED_CONTROL_PLANE_NAMESPACE | grep oauth-openshift -w
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
   oc get route -n $HOSTED_CONTROL_PLANE_NAMESPACE oauth -o jsonpath='https://{.spec.host}'
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

### Reference Documentation
[Effortlessly And Efficiently Provision OpenShift Clusters With OpenShift Virtualization](https://www.redhat.com/en/blog/effortlessly-and-efficiently-provision-openshift-clusters-with-openshift-virtualization)

[Create a Kubevirt cluster](https://hypershift-docs.netlify.app/how-to/kubevirt/create-kubevirt-cluster/)
