#!/bin/bash

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))
    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}


PRINT_TASK "TASK [Add uninstall note]"

oc annotate storagecluster -n openshift-storage ocs-storagecluster uninstall.ocs.openshift.io/cleanup-policy="delete" --overwrite
oc annotate storagecluster -n openshift-storage ocs-storagecluster uninstall.ocs.openshift.io/mode="forced" --overwrite

PRINT_TASK "TASK [Delete volumesnapshot]"
oc get volumesnapshot --all-namespaces -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers | while read ns name; do
  timeout 1s oc delete volumesnapshot "$name" -n "$ns"
done

for ns in $(oc get volumesnapshot --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' | sort -u); do oc get volumesnapshot -n $ns -o name | while read vs; do oc patch $vs -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge; done; done


RBD_PROVISIONER="openshift-storage.rbd.csi.ceph.com"
CEPHFS_PROVISIONER="openshift-storage.cephfs.csi.ceph.com"
NOOBAA_PROVISIONER="openshift-storage.noobaa.io/obc"
RGW_PROVISIONER="openshift-storage.ceph.rook.io/bucket"
NOOBAA_DB_PVC="noobaa-db"
NOOBAA_BACKINGSTORE_PVC="noobaa-default-backing-store-noobaa-pvc"

# Get all OCS StorageClasses
OCS_STORAGECLASSES=$(oc get storageclasses | grep -e "$RBD_PROVISIONER" -e "$CEPHFS_PROVISIONER" -e "$NOOBAA_PROVISIONER" -e "$RGW_PROVISIONER" | awk '{print $1}')

# Enhanced PVC deletion function with timeout and finalizer cleanup
delete_pvc() {
    local namespace=$1
    local pvc_name=$2
    
    # First attempt: Try normal deletion with 1s timeout
    if timeout 1 oc delete pvc/$pvc_name -n $namespace >/dev/null 2>&1; then
        echo "PVC $namespace/$pvc_name deleted successfully"
        return 0
    fi

    # If timeout or failure, remove finalizers
    echo "Removing finalizers from PVC $namespace/$pvc_name"
    oc patch pvc/$pvc_name -n $namespace --type=json \
        -p '[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1
    
    # Second attempt: Force delete after finalizer removal
    echo "Force deleting PVC $namespace/$pvc_name"
    oc delete pvc/$pvc_name -n $namespace --force --grace-period=0 >/dev/null 2>&1
    
    # Final verification
    if oc get pvc/$pvc_name -n $namespace >/dev/null 2>&1; then
        echo "[ERROR] Failed to delete PVC $namespace/$pvc_name"
        return 1
    else
        echo "PVC $namespace/$pvc_name force deleted successfully"
        return 0
    fi
}

# Process each StorageClass
for SC in $OCS_STORAGECLASSES; do
    PRINT_TASK "TASK [$SC StorageClass PVCs and OBCs]"

    # Process PVCs
    PVC_LIST=$(oc get pvc --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STORAGECLASS:.spec.storageClassName --no-headers 2>/dev/null | 
               awk -v sc="$SC" -v db="$NOOBAA_DB_PVC" -v bs="$NOOBAA_BACKINGSTORE_PVC" '$3 == sc && $2 != db && $2 != bs {print $1,$2}')
    
    if [ -n "$PVC_LIST" ]; then
        while read -r namespace pvc_name; do
            delete_pvc "$namespace" "$pvc_name"
        done <<< "$PVC_LIST"
    else
        echo "No related PVCs found"
    fi

    # Process OBCs (Added timeout logic for OBC deletion)
    OBC_LIST=$(oc get obc --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STORAGECLASS:.spec.storageClassName --no-headers 2>/dev/null | 
               awk -v sc="$SC" '$3 == sc {print $1,$2}')
    
    if [ -n "$OBC_LIST" ]; then
        while read -r namespace obc_name; do
            echo "Deleting OBC $namespace/$obc_name"
            # Added timeout logic for OBC deletion
            timeout 1 oc delete obc/$obc_name -n $namespace >/dev/null 2>&1 || {
                oc patch obc/$obc_name -n $namespace --type=json \
                    -p '[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1
                oc delete obc/$obc_name -n $namespace --force --grace-period=0 >/dev/null 2>&1
            }
        done <<< "$OBC_LIST"
    else
        echo "No related OBCs found"
    fi

    echo
done



PRINT_TASK "TASK [Delete storagesystem and storageclusters]"
timeout 5s oc delete -n openshift-storage storagesystem --all
oc patch storagesystem ocs-storagecluster-storagesystem -n openshift-storage --type merge -p '{"metadata": {"finalizers": null}}'

timeout 5s oc delete -n openshift-storage storageclusters --all
oc patch storageclusters ocs-storagecluster -n openshift-storage --type merge -p '{"metadata": {"finalizers": null}}'


PRINT_TASK "TASK [Delete the /var/lib/rook directory in the ODF node]"
for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name  }'); do oc debug node/${i} -- chroot /host  rm -rf /var/lib/rook; done


PRINT_TASK "TASK [Delete openshift-storage project]"
timeout 5s oc delete project openshift-storage 

timeout 2s oc delete bucketclasses.noobaa.io --all -n openshift-storage --force
timeout 2s oc delete noobaas.noobaa.io --all -n openshift-storage --force
timeout 2s oc delete cephclusters.ceph.rook.io --all -n openshift-storage --force
timeout 2s oc delete cephfilesystems.ceph.rook.io --all -n openshift-storage --force
timeout 2s oc delete cephblockpools.ceph.rook.io --all -n openshift-storage --force
timeout 2s oc delete cephobjectstores.ceph.rook.io --all -n openshift-storage --force
timeout 2s oc delete configmaps --all -n openshift-storage --force
timeout 2s oc delete pods --all -n openshift-storage --force --grace-period=0 
timeout 2s oc delete secrets --all -n openshift-storage --force


oc patch cephclusters.ceph.rook.io ocs-storagecluster-cephcluster -n openshift-storage --type merge -p '{"metadata": {"finalizers": null}}'
oc patch noobaas.noobaa.io noobaa -n openshift-storage --type merge -p '{"metadata": {"finalizers": null}}'
oc patch bucketclasses.noobaa.io noobaa-default-bucket-class -n openshift-storage --type merge -p '{"metadata": {"finalizers": null}}'
oc patch configmap rook-ceph-mon-endpoints -n openshift-storage --type merge -p '{"metadata": {"finalizers": null}}'
oc patch secret rook-ceph-mon -n openshift-storage --type merge -p '{"metadata": {"finalizers": null}}'


PRINT_TASK "TASK [Deleting Local Storage Data(/mnt/local-storage/*) from a Node]"
#!/bin/bash
for Hostname in $(oc get nodes -l node-role.kubernetes.io/worker= -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "delete the /mnt/local-storage/ file in the $Hostname node"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo rm -rf /mnt/local-storage/*
done


PRINT_TASK "TASK [Wiping unused disk from a Node]"
#!/bin/bash
for Hostname in $(oc get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
    ssh -qT -o StrictHostKeyChecking=no core@$Hostname \
        "for disk in \$(lsblk -dnlo NAME,TYPE | awk '\$2==\"disk\"{print \$1}'); do
            lsblk /dev/\$disk | grep -q '/boot\|/var\|/ \|part' || 
            { sudo wipefs -a /dev/\$disk >/dev/null 2>&1 &&
              echo \"Wiped unused /dev/\$disk on $Hostname\"; }
        done"
done

PRINT_TASK "TASK [Deleting storage class]"
oc delete sc ocs-storagecluster-ceph-rbd ocs-storagecluster-ceph-rbd-virtualization ocs-storagecluster-ceph-rgw ocs-storagecluster-cephfs openshift-storage.noobaa.io   


for ns in $(oc get pvc --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' | sort -u); do
  for pvc in $(oc get pvc -n $ns -o jsonpath='{.items[*].metadata.name}'); do
    echo "Deleting PVC $pvc in namespace $ns"
    oc delete pvc $pvc -n $ns --wait=false

    # Wait a moment and check if it's still there (stuck)
    sleep 1
    if oc get pvc $pvc -n $ns &> /dev/null; then
      echo "PVC $pvc is stuck, removing finalizers..."
      oc patch pvc $pvc -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge
    else
      echo "PVC $pvc deleted successfully"
    fi
  done
done

for pv in $(oc get pv -o jsonpath='{.items[*].metadata.name}'); do
  echo "Deleting PV $pv"
  oc delete pv $pv --wait=false

  # Wait a moment and check if it's still there (stuck)
  sleep 1
  if oc get pv $pv &> /dev/null; then
    echo "PV $pv is stuck, removing finalizers..."
    oc patch pv $pv -p '{"metadata":{"finalizers":[]}}' --type=merge
  else
    echo "PV $pv deleted successfully"
  fi
done

