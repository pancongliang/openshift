## Running an OpenShift Hosted Cluster with OpenShift Virtualization

### The list below highlights the benefits of using HyperShift KubeVirt provider:
* Enhance resource utilization by packing multiple hosted control planes and hosted clusters in the same underlying bare metal infrastructure.
* Strong isolation by separating hosted control planes and guest clusters.
* Reduce cluster provision time by eliminating baremetal node bootstrapping process.
* Manage multiple different releases under the same base OCP cluster

### Cluster Preparation
#### OCP 4.16+ is running as the underlying base OCP cluster on top of 6 bare metal nodes (3 masters + 3 workers). Required operators and controllers are listed as follows:
* OpenShift Data Foundation (ODF) using local storage devices
* OpenShift Virtualization
* MetalLB
* Multicluster Engine([MCE](https://github.com/pancongliang/openshift/blob/main/operator/mce/readme.md))
* Cluster Manager
* HyperShift

### Install OpenShift Data Foundation
* Install OpenShift Data Foundation ([ODF](https://github.com/pancongliang/openshift/blob/main/storage/odf/readme.md))  using local storage devices
* Once ODF is setup, annotate a default storage class for HyperShift to persist VM workers and guest cluster etcd pods:
  ~~~
  oc patch storageclass ocs-storagecluster-ceph-rbd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  ~~~

### Install OpenShift Virtualization
* Install OpenShift [Virtualization](https://github.com/pancongliang/openshift/blob/main/virtualization/readme.md) Operator
  
### Install MetalLB Operator
* Install [MetalLB](https://github.com/pancongliang/openshift/blob/main/operator/metallb/readme.md) Operator


### Multicluster Engine Operator
* Multicluster Engine([MCE](https://github.com/pancongliang/openshift/blob/main/operator/mce/readme.md)) Operator


### Cluster Manager
* The local-cluster ManagedCluster allows the MCE components to treat the cluster it runs on as a host for guest clusters. Note that the creation of this object might fail initially. This failure occurs if the MultiClusterEngine is still being initialized and hasn’t registered the “ManagedCluster” CRD yet. It might take a few minutes of retrying this command before it succeeds.
  ~~~
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
  ~~~


### HyperShift
* Apply the following yaml to enable HyperShift operator within the local cluster:
  ~~~
  oc apply -f - <<EOF
  apiVersion: addon.open-cluster-management.io/v1alpha1
  kind: ManagedClusterAddOn
  metadata:
    name: hypershift-addon
    namespace: local-cluster
  spec:
    installNamespace: open-cluster-management-agent-addon
  EOF
  ~~~
* The hypershift operator pods can be viewed within the “hypershift” namespace. To verify the operator pod in running in this namespace:
  ~~~
  oc get pods -n hypershift
  ~~~
  
* Allow OpenShift's ingresscontroller to use wildcard DNS routes. This is required to access the console of the Hosted Cluster.
  ~~~
  oc patch ingresscontroller -n openshift-ingress-operator default --type=json -p '[{ "op": "add", "path": "/spec/routeAdmission", "value": {wildcardPolicy: "WildcardsAllowed"}}]'
  ~~~

### Demo
#### The following sections will take you through the steps of:
* Create a project named clusters, which is the namespace associated with the Hosted Cluster
* Install HCP command client
* Configure Environment Variables
* Create HyperShift KubeVirt Hosted Cluster
* Create Ingress Service
* Create Ingress Route
* Examine Hosted Cluster

* Create a project named clusters, which is the namespace associated with the Hosted Cluster
  ~~~
  export NAMESPACE="clusters"
  oc new-project $NAMESPACE
  ~~~

* Install HCP command client
  ~~~
  curl -Lk $(oc get consoleclidownload hcp-cli-download -o json | jq -r '.spec.links[] | select(.text=="Download hcp CLI for Linux for x86_64").href') | tar xvz -C /usr/local/bin/
  ~~~

* Download [pull secret](https://console.redhat.com/openshift/install/pull-secret)

* Configure Environment Variables
  ~~~
  export PULL_SECRET="$HOME/pull-secret"
  export MEM="8Gi"
  export CPU="2"
  export WORKER_COUNT="2"
  export KUBEVIRT_CLUSTER_NAME=my-cluster-1
  export OCP_VERSION=4.16.23
  ~~~

* Create HyperShift KubeVirt Hosted Cluster
  ~~~
  hcp create cluster kubevirt \
  --name $KUBEVIRT_CLUSTER_NAME \
  --release-image quay.io/openshift-release-dev/ocp-release:$OCP_VERSION-x86_64 \
  --node-pool-replicas $WORKER_COUNT \
  --pull-secret $PULL_SECRET \
  --memory $MEM \
  --cores $CPU \
  --auto-repair
  --namespace $NAMESPACE
  ~~~

* View the creation of resources related to the my-cluster-1 Hosted Cluster
  ~~~
  oc get vm -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME
  oc get pvc -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME
  oc get nodepool -n $NAMESPACE
  ~~~

* Once the VM workers are ready, we can generate the guest cluster kubeconfig file which is useful when we want to examine the guest cluster.
  ~~~
  hypershift create kubeconfig --name="$KUBEVIRT_CLUSTER_NAME" > "${KUBEVIRT_CLUSTER_NAME}-kubeconfig"
  ~~~

* Examine The Hosted Cluster
  Once all the guest cluster operators are deployed successfully, the status of the Available column should be True and the PROGRESS column should be changed to Completed. We created three guest clusters with different releases just to show that it is possible to manage multi-version hosted clusters in HyperShift with the KubeVirt provider:
  ~~~
  $ oc get hc -A
  NAMESPACE   NAME    VERSION   KUBECONFIG               PROGRESS    AVAILABLE   PROGRESSING   MESSAGE
  clusters    my-cluster-1   4.12.2    my-cluster-1-admin-kubeconfig   Completed   True        False         The hosted control plane is available
  ~~~

  If we take a closer look, there is a dedicated namespace `$NAMESPACE-$KUBEVIRT_CLUSTER_NAME` being created for the hosted control plane. Under this namespace, we should be able see control plane pods such as etcd and  kube-api-server are running:
  ~~~
  $ oc get pod -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME | grep 'kube-api\|etcd'
  etcd-0                                                2/2     Running     0          47h
  kube-apiserver-864764b74b-t2tcl                       3/3     Running     0          47h
  ~~~

  There are two virt-launcher pods for the KubeVirt virtual machines since we specified `node-pool-replicas=2`:
  ~~~
  $ oc get pod -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME | grep 'virt-launcher'
  virt-launcher-my-cluster-1-j45fr-mt5lc                       1/1     Running     0          2d1h
  virt-launcher-my-cluster-1-l7f27-fk9tj                       1/1     Running     0          2d1h
  ~~~

  To check the status of those two VMs:
  ~~~
  $ oc get vm -n $NAMESPACE-$KUBEVIRT_CLUSTER_NAME
  NAME          AGE    STATUS    READY
  my-cluster-1-j45fr   2d1h   Running   True
  my-cluster-1-l7f27   2d1h   Running   True
  ~~~

  To examine our guest clusters, we need to have the oc tool pointing to the guest kubeconfig. From OCP’s perspective, these two virtual machines will be the worker nodes:
  ~~~
  $ oc --kubeconfig ${KUBEVIRT_CLUSTER_NAME}-kubeconfig get nodes
  NAME          STATUS   ROLES    AGE    VERSION
  my-cluster-1-j45fr   Ready    worker   2d1h   v1.25.4+77bec7a
  my-cluster-1-l7f27   Ready    worker   2d1h   v1.25.4+77bec7a
  ~~~

  We should also be able to see that there is a dedicated monitoring and networking stack for each guest cluster:
  ~~~
  $ oc --kubeconfig ${KUBEVIRT_CLUSTER_NAME}-kubeconfig get pod -A | grep 'prometh\|ovn\|ingress'
  openshift-ingress-canary                           ingress-canary-j4lq4                                     1/1     Running     0              2d1h
  openshift-ingress-canary                           ingress-canary-zd28w                                     1/1     Running     0              2d1h
  openshift-ingress                                  router-default-68df75f88d-dszb2                          1/1     Running     0              2d1h
  openshift-monitoring                               prometheus-adapter-6fd546d669-c2dw6                      1/1     Running     0              2d1h
  openshift-monitoring                               prometheus-k8s-0                                         6/6     Running     0              2d1h
  openshift-monitoring                               prometheus-operator-688459b4f4-45775                     2/2     Running     0              2d1h
  openshift-monitoring                               prometheus-operator-admission-webhook-849b6cd6bf-52rpq   1/1     Running     0              2d1h
  openshift-ovn-kubernetes                           ovnkube-node-4hmgz                                       5/5     Running     4 (2d1h ago)   2d1h
  openshift-ovn-kubernetes                           ovnkube-node-87nk7                                       5/5     Running     0              2d1h
  ~~~
