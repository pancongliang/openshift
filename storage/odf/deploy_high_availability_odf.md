### Requirements for installing OpenShift Data Foundation using local storage devices 

#### Node requirements
The cluster must consist of at least three OpenShift Container Platform worker nodes with locally attached-storage devices on each of them.

* Each of the three selected nodes must have at least one raw block device available. OpenShift Data Foundation uses the one or more available raw block devices.
* The devices you use must be empty, the disks must not include Physical Volumes (PVs), Volume Groups (VGs), or Logical Volumes (LVs) remaining on the disk.

### Step 1: Installing the Local Storage Operator

* Create the`openshift-local-storage` namespace.
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: Namespace
   metadata:
     name: openshift-local-storage
   spec: {}
   EOF
   ~~~

* Create the `openshift-local-storage` for Local Storage Operator.
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: operators.coreos.com/v1
   kind: OperatorGroup
   metadata:
     name: local-operator-group
     namespace: openshift-local-storage
   spec:
     targetNamespaces:
     - openshift-local-storage
   EOF
   ~~~

* Subscribe to the `local-storage-operator`.
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: operators.coreos.com/v1alpha1
   kind: Subscription
   metadata:
     name: local-storage-operator
     namespace: openshift-local-storage
   spec:
     channel: "4.10"  # <-- Channel should be used corresponding to the OCP version being used.
     installPlanApproval: Automatic
     name: local-storage-operator
     source: redhat-operators  # <-- Modify the name of the redhat-operators catalogsource if not default
     sourceNamespace: openshift-marketplace
   EOF
   ~~~


### Step 2: Preparing Nodes
* Add raw block devices to the three selected worker nodes. Each raw block device must be the same size and shall not be less than 100GB.
   ~~~
  ssh core@<Worker-Node-Name> sudo lsblk
   ~~~

* Each worker node that has local storage devices to be used by OpenShift Container Storage must have a specific label to deploy OpenShift Container Storage pods. To label the nodes, use the following command:

   ~~~
  oc label node <Worker-Node-Name> cluster.ocs.openshift.io/openshift-storage=''
   ~~~


#### Auto Discovering Devices and creating Persistent Volumes

* Local Storage Operator discovery of devices on OpenShift Container Platform nodes with the OpenShift  Data Foundation label `cluster.ocs.openshift.io/openshift-storage=""`. Create the `LocalVolumeDiscovery` resource using this file after the OpenShift Container Platform nodes are labeled with the OpenShift Container Storage label.
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: local.storage.openshift.io/v1alpha1
   kind: LocalVolumeDiscovery
   metadata:
     name: auto-discover-devices
     namespace: openshift-local-storage
   spec:
     nodeSelector:
       nodeSelectorTerms:
         - matchExpressions:
           - key: cluster.ocs.openshift.io/openshift-storage
             operator: In
             values:
               - ""
   EOF
   ~~~

* After this resource is created you should see a new `localvolumediscovery` resource and there is a `localvolumediscoveryresults` for each OpenShift Container Platform node labeled with the OpenShift Data Foundation label. Each `localvolumediscoveryresults` will have the detail for each disk on the node including the `by-id`, size and type of disk.

* Can check the `localvolumediscovery` resource and `localvolumediscoveryresults` by running the command given below:
   ~~~
   $ oc get localvolumediscoveries -n openshift-local-storage
   NAME                    AGE
   auto-discover-devices   5m15s

   $ oc get localvolumediscoveryresults -n openshift-local-storage
   NAME                           AGE
   discovery-result-compute-0     19m
   discovery-result-compute-1     19m
   discovery-result-compute-2     19m
   ~~~
 

#### Create LocalVolumeSet

* Use  the`localvolumeset.yaml`file to create the `LocalVolumeSet`. Configure the parameters with comments to meet the needs of your environment. If not required, the parameters with comments can be deleted.
   ~~~
   cat << EOF | oc apply -f -
   apiVersion: local.storage.openshift.io/v1alpha1
   kind: LocalVolumeSet
   metadata:
     name: local-block
     namespace: openshift-local-storage
   spec:
     nodeSelector:
       nodeSelectorTerms:
         - matchExpressions:
             - key: cluster.ocs.openshift.io/openshift-storage
               operator: In
               values:
                 - ""
     storageClassName: localblock
     volumeMode: Block
     fstype: ext4
     maxDeviceCount: 1     # Maximum number of devices per node to be used
     deviceInclusionSpec:
       deviceTypes:
       - disk
       - part              # Remove this if not using partitions
       deviceMechanicalProperties:
       - NonRotational
       #minSize: 0Ti       # Uncomment and modify to limit the minimum size of disk used
       #maxSize: 0Ti       # Uncomment and modify to limit the maximum size of disk used
   EOF
   ~~~

* After the `localvolumesets` resource is created check that `Available` *PVs* are created for each disk on OpenShift Container Platform nodes with the OpenShift Container Storage label. It can take a few minutes until all disks appear as PVs while the Local Storage Operator is preparing the disks.

   Check for diskmaker-manager pods
   ~~~
   oc get pods -n openshift-local-storage | grep "diskmaker-manager"
   diskmaker-manager-8l2bq                   2/2     Running   0          3m42s
   diskmaker-manager-bsklr                   2/2     Running   0          3m42s
   diskmaker-manager-fzbnx                   2/2     Running   0          3m42s
   ~~~

   Check for PV's created

   ~~~
   $ oc get pv -n openshift-local-storage
   NAME                CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
   local-pv-1f003b14   2328Gi     RWO            Delete           Available           localblock              11s
   local-pv-4d7de45    2328Gi     RWO            Delete           Available           localblock              11s
   local-pv-77dbe0a6   2328Gi     RWO            Delete           Available           localblock              10s
   ~~~

### Step 3: Installing OpenShift Data Foundation

#### Install Operator

* Create the `openshift-storage` namespace.
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: Namespace
   metadata:
     labels:
       openshift.io/cluster-monitoring: "true"
     name: openshift-storage
   spec: {}
   EOF
   ~~~

* Create the `openshift-storage-operatorgroup` for Operator.
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: operators.coreos.com/v1
   kind: OperatorGroup
   metadata:
     name: openshift-storage-operatorgroup
     namespace: openshift-storage
   spec:
     targetNamespaces:
     - openshift-storage
   EOF
   ~~~

* Subscribe to the `odf-operator` for version 4.10 or above
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: operators.coreos.com/v1alpha1
   kind: Subscription
   metadata:
     name: odf-operator
     namespace: openshift-storage
   spec:
     channel: "stable-4.10"
     installPlanApproval: Automatic
     name: odf-operator
     source: redhat-operators
     sourceNamespace: openshift-marketplace
   EOF
   ~~~

#### Create Cluster

* Storage Cluster CR. For each set of 3 OSDs, increment the `count`. Below is the sample output of storagecluster.yaml
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: ocs.openshift.io/v1
   kind: StorageCluster
   metadata:
     name: ocs-storagecluster
     namespace: openshift-storage
   spec:
     manageNodes: false
     resources:
       mds:
         limits:
           cpu: "3"
           memory: "8Gi"
         requests:
           cpu: "3"
           memory: "8Gi"
     monDataDirHostPath: /var/lib/rook
     storageDeviceSets:
     - count: 1  # <-- Modify count to desired value. For each set of 3 disks increment the count by 1.
       dataPVCTemplate:
         spec:
           accessModes:
           - ReadWriteOnce
           resources:
             requests:
               storage: "100Gi"  # <-- This should be changed as per storage size. Minimum 100 GiB and Maximum 4 TiB
           storageClassName: localblock
           volumeMode: Block
       name: ocs-deviceset
       placement: {}
       portable: false
       replica: 3
       resources:
         limits:
           cpu: "2"
           memory: "5Gi"
         requests:
           cpu: "2"
           memory: "5Gi"
   EOF
   ~~~

   ODF v4.12 and later support Single Stack IPv6. If you plan to use IPv6 in your deployment, add the following to the storagecluster.yaml:
   ~~~
    spec:
     network:
       ipFamily: "IPv6"
   ~~~


### Step 4: Verifying the Installation

* Verify if all the pods are up and running 
   ~~~
   oc get pods -n openshift-storage
   ~~~
   *All the pods in the openshift-storage namespace must be in either `Running` or `Completed` state.*
   *Cluster creation might take around 5 mins to complete. Please keep monitoring until you see the expected state or you see an error or you find progress stuck even after waiting for a longer period.*

* List CSV to see that ocs-operator is in Succeeded phase

   ~~~
   $ oc get csv -n openshift-storage
   NAME                               DISPLAY                       VERSION   REPLACES                           PHASE
   mcg-operator.v4.10.14              NooBaa Operator               4.10.14   mcg-operator.v4.10.13              Succeeded
   ocs-operator.v4.10.14              OpenShift Container Storage   4.10.14   ocs-operator.v4.10.13              Succeeded
   odf-csi-addons-operator.v4.10.14   CSI Addons                    4.10.14   odf-csi-addons-operator.v4.10.13   Succeeded
   odf-operator.v4.10.14              OpenShift Data Foundation     4.10.14   odf-operator.v4.10.13              Succeeded
   ~~~

### Step 5: Creating test CephRBD PVC and CephFS PVC.
* CephRBD PVC
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: rbd-pvc
   spec:
     accessModes:
     - ReadWriteOnce
     resources:
       requests:
         storage: 1Gi
     storageClassName: ocs-storagecluster-ceph-rbd
   EOF
   ~~~
* CephFS PVC
   ~~~
   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: cephfs-pvc
   spec:
     accessModes:
     - ReadWriteMany
     resources:
       requests:
         storage: 1Gi
     storageClassName: ocs-storagecluster-cephfs
   EOF
   ~~~

* Validate that the new PVCs are created.
   ~~~
   oc get pvc | grep rbd-pvc
   oc get pvc | grep cephfs-pvc
   ~~~






[Install Red Hat OpenShift Data Foundation 4.X in internal-attached mode](https://access.redhat.com/articles/5692201)

[Uninstalling OpenShift Data Foundation in Internal mode](https://access.redhat.com/articles/6525111#removing-local-storage-operator-configurations-2)

