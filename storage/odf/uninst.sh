#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Define the device pattern to search for
# Ensure the OCP cluster has at least three worker nodes, each with at least one 100GB disk.
export DISK_KNAME_PATTERN="sd[a-z]"
export ODF_NODES="worker01.ocp.example.com worker02.ocp.example.com worker03.ocp.example.com"


# Set the label variable
export ODF_NODES_LABEL="cluster.ocs.openshift.io/openshift-storage"
export LSO_NODES_LABEL="local.storage.openshift.io/openshift-local-storage"
export LSO_NODES="$ODF_NODES"

# Add user's local bin to PATH
export PATH="$HOME/.local/bin:$PATH"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Function to check command success and display appropriate message
run_command() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo -e "\e[36mINFO\e[0m $1"
    else
        echo -e "\e[31mFAIL\e[0m $1"
        exit 1
    fi
}

# Define color output variables
INFO_MSG="\e[36mINFO\e[0m"
FAIL_MSG="\e[31mFAIL\e[0m"
ACTION_MSG="\e[33mACTION\e[0m"

# Step 0:
PRINT_TASK "TASK [Delete old ODF and LSO resources]"

# 1. Cleanup Logic: ODF (OpenShift Data Foundation)

echo -e "$INFO_MSG Starting ODF cleanup process..."

# Function to check if an API exists
api_exists() {
    local resource=$1
    oc api-resources --no-headers -o name 2>/dev/null | grep -wq "$resource"
}

# Annotate StorageCluster for forced cleanup
oc annotate storagecluster -n openshift-storage ocs-storagecluster uninstall.ocs.openshift.io/cleanup-policy="delete" --overwrite >/dev/null 2>&1 || true
oc annotate storagecluster -n openshift-storage ocs-storagecluster uninstall.ocs.openshift.io/mode="forced" --overwrite >/dev/null 2>&1 || true

# Delete VolumeSnapshots
if api_exists volumesnapshot; then
    if oc get volumesnapshot --all-namespaces >/dev/null 2>&1; then
        echo -e "$INFO_MSG Deleting all VolumeSnapshots..."
        oc get volumesnapshot --all-namespaces -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null || true
        while read ns name; do
            timeout 1s oc delete volumesnapshot "$name" -n "$ns" >/dev/null 2>&1 || true
            oc patch volumesnapshot "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
        done
    fi
fi

# Define OCS related Provisioner keywords for matching
OCS_KEYWORDS="noobaa|ceph|rbd|rook"
NOOBAA_DB_PVC="noobaa-db"
NOOBAA_BACKINGSTORE_PVC="noobaa-default-backing-store-noobaa-pvc"

# Function to force delete resources (clears finalizers and deletes)
force_delete_resource() {
    local type=$1
    local namespace=$2
    local name=$3
   
    # 1. Attempt normal deletion with a 3-second timeout
    if timeout 3s oc delete $type $name -n $namespace >/dev/null 2>&1; then
        echo -e "$INFO_MSG Delete the $type named $name in the $namespace"
        return 0
    fi

    # 2. If normal deletion fails, remove finalizers to unstick the resource
    # echo -e "$INFO_MSG Removing finalizers from $type $namespace/$name"
    oc patch secrets $name -n $namespace --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1 || true
    oc patch $type $name -n $namespace --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1 || true
    
    # 3. Force delete the resource immediately
    # echo -e "$INFO_MSG Force deleting $type $namespace/$name"
    timeout 3s oc delete $type $name -n $namespace --force --grace-period=0 >/dev/null 2>&1 || true
    echo -e "$INFO_MSG Delete the $type named $name in the $namespace"
}

# Process PVCs 
# echo -e "$INFO_MSG Checking for OCS-related PVCs..."
# Get all PVCs and filter by StorageClass name containing OCS keywords, excluding system-critical DB/BS PVCs
PVC_LIST=$(oc get pvc --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName --no-headers 2>/dev/null | \
           awk -v kw="$OCS_KEYWORDS" -v db="$NOOBAA_DB_PVC" -v bs="$NOOBAA_BACKINGSTORE_PVC" \
           '$3 ~ kw && $2 != db && $2 != bs {print $1,$2}')

if [ -n "$PVC_LIST" ]; then
    while read -r ns name; do
        force_delete_resource "pvc" "$ns" "$name"
    done <<< "$PVC_LIST"
#else
#    echo -e "$INFO_MSG No OCS PVCs found."
fi

# Process OBCs (Object Bucket Claims)
# echo -e "$INFO_MSG Checking for OCS-related OBCs..."
# Check if OBC API exists before processing
if oc get obc --all-namespaces >/dev/null 2>&1; then
    # Get all OBCs and filter by StorageClass keywords (handles cases like openshift-storage.noobaa.io)
    OBC_LIST=$(oc get obc --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName --no-headers 2>/dev/null | \
               awk -v kw="$OCS_KEYWORDS" '$3 ~ kw || $3 == "" {print $1,$2}')

    if [ -n "$OBC_LIST" ]; then
        while read -r ns name; do
            force_delete_resource "obc" "$ns" "$name"
        done <<< "$OBC_LIST"
#    else
#        echo -e "$INFO_MSG No OCS OBCs found."
    fi
#else
#    echo -e "$INFO_MSG OBC API not present or no OBCs exist."
fi

# Delete all resources in the namespace
RESOURCES=(
  storagesystems.odf.openshift.io
  storageclusters.ocs.openshift.io
  cephclusters.ceph.rook.io
  cephfilesystems.ceph.rook.io
  cephblockpools.ceph.rook.io
  cephobjectstores.ceph.rook.io
  cephobjectstoreusers.ceph.rook.io
  cephfilesystemsubvolumegroups.ceph.rook.io
  noobaas.noobaa.io
  backingstores.noobaa.io
  bucketclasses.noobaa.io
  objectbucketclaims.objectbucket.io
  objectbuckets.objectbucket.io
  csiaddonsnodes.csiaddons.openshift.io
  volumereplications.replication.storage.openshift.io
  secrets
  configmaps
)

NAMESPACE="openshift-storage"

for res in "${RESOURCES[@]}"; do
    objs=$(oc get "$res" -n "$NAMESPACE" -o name 2>/dev/null || true)
    for obj in $objs; do
        # Remove finalizers
        oc patch "$obj" -n "$NAMESPACE" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
        # Delete resource forcibly
        oc delete "$obj" -n "$NAMESPACE" --force --grace-period=0 >/dev/null 2>&1 || true
    done
done

oc patch secret rook-ceph-mon -n openshift-storage -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
oc patch cm rook-ceph-mon-endpoints -n openshift-storage -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
oc patch cm ocs-client-operator-config -n openshift-storage -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete pods --all -n openshift-storage --force --grace-period=0 >/dev/null 2>&1 || true

for pvc in $(oc get pvc -n openshift-storage -o name); do
    oc patch "$pvc" -n openshift-storage -p '{"metadata":{"finalizers":null}}' --type=merge2 >/dev/null 2>&1 || true
    timeout 2s oc delete "$pvc" -n openshift-storage --force --grace-period=02 >/dev/null 2>&1 || true
done

oc patch ns "$NAMESPACE" --type=merge -p '{"spec":{"finalizers":null}}' >/dev/null 2>&1 || true
timeout 2s oc delete ns "$NAMESPACE" --force --grace-period=0 >/dev/null 2>&1 || true

# Delete StorageClasses individually
timeout 2s oc delete sc ocs-storagecluster-ceph-rbd ocs-storagecluster-ceph-rbd-virtualization ocs-storagecluster-ceph-rgw ocs-storagecluster-cephfs openshift-storage.noobaa.io >/dev/null 2>&1 || true

# Delete local rook data on ODF nodes
for Hostname in $(oc get nodes -l $ODF_NODES_LABEL= -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
    ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$Hostname "
        if [ -d /var/lib/rook ] && [ \"\$(ls -A /var/lib/rook  2>/dev/null)\" ]; then
            echo -e \"$INFO_MSG Node $Hostname delete /var/lib/rook files\"
            sudo rm -rf /var/lib/rook
        #else
        #    echo -e \"$INFO_MSG Node $Hostname /var/lib/rook not exist or empty, skip\"
        fi
    "
done

# Delete subscription
if oc get sub odf-operator -n openshift-storage >/dev/null 2>&1 || true; then
    echo -e "$INFO_MSG Deleting odf-operator subscription..."
    timeout 2s oc delete sub odf-operator -n openshift-storage >/dev/null 2>&1 || true
else
    echo -e "$INFO_MSG odf-operator subscription does not exist"
fi

# Delete project
if oc get project openshift-storage >/dev/null 2>&1; then
    echo -e "$INFO_MSG Deleting project openshift-storage..."
    timeout 5s oc delete project openshift-storage >/dev/null 2>&1 || true
else
    echo -e "$INFO_MSG Project openshift-storage does not exist"
fi

# Delete all resources in the namespace
RESOURCES=(
  storagesystems.odf.openshift.io
  storageclusters.ocs.openshift.io
  cephclusters.ceph.rook.io
  cephfilesystems.ceph.rook.io
  cephblockpools.ceph.rook.io
  cephobjectstores.ceph.rook.io
  cephobjectstoreusers.ceph.rook.io
  cephfilesystemsubvolumegroups.ceph.rook.io
  noobaas.noobaa.io
  backingstores.noobaa.io
  bucketclasses.noobaa.io
  objectbucketclaims.objectbucket.io
  objectbuckets.objectbucket.io
  csiaddonsnodes.csiaddons.openshift.io
  volumereplications.replication.storage.openshift.io
  secrets
  configmaps
)

NAMESPACE="openshift-storage"

for res in "${RESOURCES[@]}"; do
    objs=$(oc get "$res" -n "$NAMESPACE" -o name 2>/dev/null || true)
    for obj in $objs; do
        # Remove finalizers
        oc patch "$obj" -n "$NAMESPACE" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
        # Delete resource forcibly
        oc delete "$obj" -n "$NAMESPACE" --force --grace-period=0 >/dev/null 2>&1 || true
    done
done

oc patch secret rook-ceph-mon -n openshift-storage -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
oc patch cm rook-ceph-mon-endpoints -n openshift-storage -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete pods --all -n openshift-storage --force --grace-period=0 >/dev/null 2>&1 || true

oc patch ns "$NAMESPACE" --type=merge -p '{"spec":{"finalizers":null}}' >/dev/null 2>&1 || true
timeout 2s oc delete ns "$NAMESPACE" --force --grace-period=0 >/dev/null 2>&1 || true

# Remove $ODF_NODES_LABEL label
for n in $LSO_NODES; do oc label node "$n" "$ODF_NODES_LABEL-" --overwrite >/dev/null 2>&1 || true; done
for n in $LSO_NODES; do oc label node "$n" "topology.rook.io/rack-" --overwrite >/dev/null 2>&1 || true; done

# Remove the PV provided by the ocs-storagecluster-ceph-rbd storage class
for pv in $(oc get pv -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName --no-headers | awk '$2=="ocs-storagecluster-ceph-rbd"{print $1}'); do
  oc patch pv $pv -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1
  oc delete pv $pv >/dev/null 2>&1
done

# Check if namespace exists
#NAMESPACE="openshift-storage"
#if oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
#    # Start oc proxy in background silently
#    sleep 10
#    pkill -f "oc proxy" >/dev/null 2>&1 || true
#    oc proxy >/dev/null 2>&1 &
#
#    # Wait briefly for proxy to start
#    sleep 1
#
#    # Remove finalizers and save to temp file silently
#    oc get namespace "$NAMESPACE" -o json | jq '.spec = {"finalizers":[]}' > temp.json >/dev/null 2>&1 || true
#
#    # Send the updated namespace spec to Kubernetes API silently
#    curl -k -s -H "Content-Type: application/json" \
#         -X PUT --data-binary @temp.json \
#         "http://127.0.0.1:8001/api/v1/namespaces/${NAMESPACE}/finalize" >/dev/null 2>&1 || true
#
#    # Kill background oc proxy process silently
#    pkill -f "oc proxy" >/dev/null 2>&1 || true
#
#    # Remove temp file silently
#    rm -f temp.json >/dev/null 2>&1 || true
#
#    # Wait for namespace to be deleted and then show message
#    while oc get namespace "$NAMESPACE" >/dev/null 2>&1; do
#        sleep 1
#    done
#    echo -e "$INFO_MSG Namespace '$NAMESPACE' terminated and deleted successfully"
#fi

# Delete crd
for crd in \
  backingstores.noobaa.io \
  bucketclasses.noobaa.io \
  cephblockpools.ceph.rook.io \
  cephclusters.ceph.rook.io \
  cephfilesystems.ceph.rook.io \
  cephnfses.ceph.rook.io \
  cephobjectstores.ceph.rook.io \
  cephobjectstoreusers.ceph.rook.io \
  noobaas.noobaa.io \
  ocsinitializations.ocs.openshift.io \
  storageclusters.ocs.openshift.io \
  cephclients.ceph.rook.io \
  cephobjectrealms.ceph.rook.io \
  cephobjectzonegroups.ceph.rook.io \
  cephobjectzones.ceph.rook.io \
  cephrbdmirrors.ceph.rook.io \
  storagesystems.odf.openshift.io \
  cephblockpoolradosnamespaces.ceph.rook.io \
  cephbucketnotifications.ceph.rook.io \
  cephbuckettopics.ceph.rook.io \
  cephcosidrivers.ceph.rook.io \
  cephfilesystemmirrors.ceph.rook.io \
  cephfilesystemsubvolumegroups.ceph.rook.io \
  csiaddonsnodes.csiaddons.openshift.io \
  networkfences.csiaddons.openshift.io \
  reclaimspacecronjobs.csiaddons.openshift.io \
  reclaimspacejobs.csiaddons.openshift.io \
  storageclassrequests.ocs.openshift.io \
  storageconsumers.ocs.openshift.io \
  storageprofiles.ocs.openshift.io \
  volumereplicationclasses.replication.storage.openshift.io \
  volumereplications.replication.storage.openshift.io
do
  oc patch crd "$crd" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
done

# 2. Cleanup Logic: LSO (Local Storage Operator)
echo -e "$INFO_MSG Starting LSO cleanup process..."

# Delete local volume and pv, sc
timeout 2s oc -n openshift-local-storage delete LocalVolumeDiscovery --all >/dev/null 2>&1 || true
timeout 2s oc -n openshift-local-storage delete LocalVolumeSet --all >/dev/null 2>&1 || true
(oc get localvolumes -n openshift-local-storage -o name 2>/dev/null | xargs -r -I {} oc -n openshift-local-storage delete {} 2>/dev/null) >/dev/null 2>&1 || true
(oc get localvolume -n openshift-local-storage -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | xargs -r -I {} oc patch localvolume {} -n openshift-local-storage --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null) >/dev/null 2>&1 || true
#oc get pv | grep local | awk '{print $1}' | xargs -I {} oc patch pv {} -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
#oc get pv | grep local | awk '{print $1}' | xargs -I {} oc delete pv {} >/dev/null 2>&1 || true

mapfile -t PVS < <(oc get pv -o name 2>/dev/null | grep local || true)
for pv in "${PVS[@]}"; do
  oc patch "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1
  oc delete "$pv" >/dev/null 2>&1
done

if oc get sc local-sc >/dev/null 2>&1; then
   echo -e "$INFO_MSG Deleting local-sc storageclasse..."
   oc delete sc local-sc >/dev/null 2>&1 || true
#else
#  echo -e "$INFO_MSG The local-sc storageclasse does not exist"
fi

if oc get sub local-storage-operator -n openshift-local-storage >/dev/null 2>&1 || true; then
   # echo -e "$INFO_MSG Deleting local-storage-operator subscription..."
   oc delete sub local-storage-operator -n openshift-local-storage >/dev/null 2>&1 || true
else
   echo -e "$INFO_MSG The local-storage-operator subscription does not exist"
fi

if oc get ns openshift-local-storage >/dev/null 2>&1 || true; then
   echo -e "$INFO_MSG Deleting openshift-local-storage namespace..."
   oc delete ns openshift-local-storage >/dev/null 2>&1 || true
else
   echo -e "$INFO_MSG The openshift-local-storage namespace does not exist"
fi

# Clean up local storage (Only prints if files were deleted)
for Hostname in $(oc get nodes -l $LSO_NODES_LABEL= -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do

  ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$Hostname "
    if [ -d /mnt/local-storage ] && [ \"\$(ls -A /mnt/local-storage 2>/dev/null)\" ]; then
      echo -e \"$INFO_MSG Node $Hostname delete /mnt/local-storage files\"
      sudo rm -rf /mnt/local-storage
    #else
    #  echo -e \"$INFO_MSG Node $Hostname /mnt/local-storage not exist or empty, skip\"
    fi
  "
done

# 3. Disk Wiping Logic
# Add the LSO label to the worker node
for n in $LSO_NODES; do oc label node "$n" "$LSO_NODES_LABEL=" --overwrite >/dev/null 2>&1 || true; done

# Extract numeric value for size matching
TARGET_NUM=$(echo "$ODF_DISK_SIZE" | sed 's/[^0-9]//g')
MIN_GIB=$((TARGET_NUM - 5))
MAX_GIB=$((TARGET_NUM + 5))
NODES=$(oc get nodes -l "$LSO_NODES_LABEL" -o jsonpath='{.items[*].metadata.name}')

echo -e "$INFO_MSG Starting exhaustive disk wipe process on ODF nodes..."

# Execution Loop
for node in $NODES; do
    # Define node display name early
    WIPE_RESULT=$(ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$node "sudo bash -s $MIN_GIB $MAX_GIB $DISK_KNAME_PATTERN" << 'EOF'
        MIN=$1
        MAX=$2
        PATTERN=$3
        
        shopt -s nullglob
        for data_disk in /dev/$PATTERN; do
            [ ! -b "${data_disk}" ] && continue
            
            # Get size accurately
            SIZE_BYTES=$(blockdev --getsize64 "${data_disk}" 2>/dev/null || true)
            [ -z "$SIZE_BYTES" ] && continue
            GIB=$(( SIZE_BYTES / 1024 / 1024 / 1024 ))
            
            if [ "$GIB" -ge "$MIN" ] && [ "$GIB" -le "$MAX" ]; then
                if ! lsblk "${data_disk}" | grep -Eq '/boot|/var|/ |part'; then
                    
                    # A. Clear filesystem signatures and partition tables
                    wipefs -af "${data_disk}" >/dev/null 2>&1
                    blockdev --rereadpt "${data_disk}" >/dev/null 2>&1

                    # B. Zap the disk to a fresh, usable state (zap-all is important, b/c MBR has to be clean)
                    sgdisk --zap-all "${data_disk}" >/dev/null 2>&1
                    
                    # C. Wipe a large portion of the beginning&end of the disk to remove more LVM metadata that may be present
                    mb=100
                    dd if=/dev/zero of="${data_disk}" bs=1M  count=${mb} oflag=direct,dsync >/dev/null 2>&1
                    dd if=/dev/zero of="${data_disk}" bs=512 count=$(( 2048 * $mb )) seek=$(( $(blockdev --getsz ${data_disk}) - 2048 * $mb )) >/dev/null 2>&1

                    # D. SSD Discard
                    blkdiscard "${data_disk}" >/dev/null 2>&1 || true
                    sync

                    # E. Inform the OS
                    [[ -f /usr/sbin/partprobe ]] && partprobe "${data_disk}" >/dev/null 2>&1 || true
                    
                    # Final output for the local script to parse
                    echo "RESULT_SUCCESS ${data_disk##*/}"
                    exit 0
                fi
            fi
        done
        
        echo "RESULT_NOT_FOUND"
        exit 1
EOF
) || true 

    # Format result display
    if [[ "$WIPE_RESULT" == *"RESULT_SUCCESS"* ]]; then
        # Extract disk name (e.g., sdc)
        DISK_NAME=$(echo "$WIPE_RESULT" | grep "RESULT_SUCCESS" | awk '{print $2}')
        echo -e "$INFO_MSG Node ${node} successfully wiped disk: /dev/${DISK_NAME}"
    else
        echo -e "$INFO_MSG Node ${node} no matching disk found to wipe ($ODF_DISK_SIZE)"
    fi
done

# Remove label
for n in $LSO_NODES; do oc label node "$n" "$LSO_NODES_LABEL-" --overwrite >/dev/null 2>&1 || true; done

# Add an empty line after the task
echo
