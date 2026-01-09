#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Define the device pattern to search for
# Ensure the OCP cluster has at least three worker nodes, each with at least one 100GB disk.
export DISK_KNAME_PATTERN="sd[b-z]"
export ODF_DISK_SIZE="100Gi"         # At least 100GB of disk space, By default, it will format the non-root disk and reference the second disk (sd*).
export ODF_NODES="worker01.ocp.example.com worker02.ocp.example.com worker03.ocp.example.com"

# Install version
export ODF_CHANNEL_NAME="stable-4.16"
export CATALOG_SOURCE_NAME="redhat-operators"

# Whether to create OBC and its object storage secret
export CREATE_OBC_AND_CREDENTIALS="false"                      # true or false
export OBC_NAMESPACE="test" 
export OBC_NAME="test"
export OBC_STORAGECLASS_S3="openshift-storage.noobaa.io"      # openshift-storage.noobaa.io or ocs-storagecluster-ceph-rgw

# Set the label variable
export ODF_NODES_LABEL="cluster.ocs.openshift.io/openshift-storage"
export LSO_NODES_LABEL="local.storage.openshift.io/openshift-local-storage"
export LSO_NODES="$ODF_NODES"

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
        echo -e "\e[96mINFO\e[0m $1"
    else
        echo -e "\e[31mFAILED\e[0m $1"
        exit 1
    fi
}

# Define color output variables
INFO_MSG="\e[96mINFO\e[0m"
FAIL_MSG="\e[31mFAIL\e[0m"
MSG_WARN="\e[33mWARN\e[0m"
WARN_MSG="\e[33mWARN\e[0m"

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

    echo -e "$INFO_MSG Attempting to delete $type $namespace/$name"
    
    # 1. Attempt normal deletion with a 3-second timeout
    if timeout 3s oc delete $type $name -n $namespace >/dev/null 2>&1; then
        echo -e "$INFO_MSG $type $namespace/$name deleted successfully"
        return 0
    fi

    # 2. If normal deletion fails, remove finalizers to unstick the resource
    # echo -e "$INFO_MSG Removing finalizers from $type $namespace/$name"
    oc patch secrets $name -n $namespace --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1 || true
    oc patch $type $name -n $namespace --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null 2>&1 || true
    
    # 3. Force delete the resource immediately
    # echo -e "$INFO_MSG Force deleting $type $namespace/$name"
    timeout 3s oc delete $type $name -n $namespace --force --grace-period=0 >/dev/null 2>&1 || true
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

# Delete local rook data on worker nodes
for Hostname in $(oc get nodes -l $ODF_NODES_LABEL= -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
    ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$Hostname "
        if [ -d /var/lib/rook ] && [ \"\$(ls -A /var/lib/rook  >/dev/null 2>&1)\" ]; then
            echo -e \"\e[96mINFO\e[0m $Hostname delete /var/lib/rook files\"
            sudo rm -rf /var/lib/rook
        #else
        #    echo -e \"\e[96mINFO\e[0m $Hostname /var/lib/rook not exist or empty, skip\"
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
#    echo -e "\e[96mINFO\e[0m Namespace '$NAMESPACE' terminated and deleted successfully"
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
oc get pv | grep local | awk '{print $1}' | xargs -I {} oc patch pv {} -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
oc get pv | grep local | awk '{print $1}' | xargs -I {} oc delete pv {} >/dev/null 2>&1 || true

if oc get sc local-sc >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting local-sc storageclasse..."
   oc delete sc local-sc >/dev/null 2>&1 || true
#else
#  echo -e "\e[96mINFO\e[0m The local-sc storageclasse does not exist"
fi

if oc get sub local-storage-operator -n openshift-local-storage >/dev/null 2>&1 || true; then
   echo -e "\e[96mINFO\e[0m Deleting local-storage-operator subscription..."
   oc delete sub local-storage-operator -n openshift-local-storage >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The local-storage-operator subscription does not exist"
fi

if oc get ns openshift-local-storage >/dev/null 2>&1 || true; then
   echo -e "\e[96mINFO\e[0m Deleting openshift-local-storage namespace..."
   oc delete ns openshift-local-storage >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The openshift-local-storage namespace does not exist"
fi

# Clean up local storage (Only prints if files were deleted)
for Hostname in $(oc get nodes -l $LSO_NODES_LABEL= -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do

  ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$Hostname "
    if [ -d /mnt/local-storage ] && [ \"\$(ls -A /mnt/local-storage 2>/dev/null)\" ]; then
      echo -e \"\e[96mINFO\e[0m Node $Hostname delete /mnt/local-storage files\"
      sudo rm -rf /mnt/local-storage
    #else
    #  echo -e \"\e[96mINFO\e[0m Node $Hostname /mnt/local-storage not exist or empty, skip\"
    fi
  "
done

# 3. Disk Wiping Logic
# 0. Add the LSO label to the worker node
for n in $LSO_NODES; do oc label node "$n" "$LSO_NODES_LABEL=" --overwrite >/dev/null 2>&1 || true; done

# 1. Extract numeric value for size matching
TARGET_NUM=$(echo "$ODF_DISK_SIZE" | sed 's/[^0-9]//g')
MIN_GIB=$((TARGET_NUM - 5))
MAX_GIB=$((TARGET_NUM + 5))
NODES=$(oc get nodes -l "$LSO_NODES_LABEL" -o jsonpath='{.items[*].metadata.name}')

echo -e "$INFO_MSG Starting exhaustive disk wipe process on ODF nodes..."

# 2. Execution Loop
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

    # 3. Format result display
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

# Step 1:
PRINT_TASK "TASK [Automating discovery for local storage devices]"

# 1. Add the LSO label to the worker node
for n in $LSO_NODES; do
  if oc label node $n $LSO_NODES_LABEL="" --overwrite >/dev/null 2>&1; then
    echo -e "$INFO_MSG Add the LSO label to the $n node"
  else
    echo -e "$FAIL_MSG Add the LSO label to the $n node"
  fi
done

# 2. Environment Preparation
# Extract numeric value and set GiB range
TARGET_NUM=$(echo "$ODF_DISK_SIZE" | sed 's/[^0-9]//g')
MIN_GIB=$((TARGET_NUM - 5))
MAX_GIB=$((TARGET_NUM + 5))

# Define the output environment file name
OUTPUT_ENV_FILE="generated_vars.env"
rm -f "$OUTPUT_ENV_FILE"
rm -f find-secondary-device.sh

# 3. Generate Remote Discovery Script
cat << 'EOF' > find-secondary-device.sh
#!/bin/bash
set -uo pipefail
shopt -s nullglob

# Retrieve parameters from command line arguments
MIN_GIB=$1
MAX_GIB=$2
PATTERN=$3

for device in /dev/$PATTERN; do
    # If it's not a block device, skip this step.
    [ ! -b "$device" ] && continue
    # Get size in bytes and convert to GiB integer
    SIZE_BYTES=$(lsblk -dn -o SIZE -b "${device}" 2>/dev/null | tr -d '[:space:]')
    [ -z "$SIZE_BYTES" ] && continue
    
    CURRENT_GIB=$(( SIZE_BYTES / 1024 / 1024 / 1024 ))

    # Check if disk size is within the allowed range
    if [ "$CURRENT_GIB" -ge "$MIN_GIB" ] && [ "$CURRENT_GIB" -le "$MAX_GIB" ]; then
        # Check if the device is raw/empty (blkid returns 2 if no filesystem)
        /usr/sbin/blkid "${device}" &> /dev/null
        if [ $? -eq 2 ]; then
            # Get the persistent by-path identifier
            DEVICE_PATH=$(ls -l /dev/disk/by-path/ | awk -v dev="${device##*/}" '$0 ~ dev {print "/dev/disk/by-path/" $9}')
            if [ -n "$DEVICE_PATH" ]; then
                echo "${device##*/} $DEVICE_PATH"
                exit 0
            fi
        fi
    fi
done
EOF

# 4. Iterate through Nodes and Collect Device Paths
NODES=$(oc get nodes -l "$LSO_NODES_LABEL" -o=jsonpath='{.items[*].metadata.name}')
COUNTER=1

echo -e "$INFO_MSG Starting discovery for unused disks matching pattern: '$DISK_KNAME_PATTERN'"

for node in $NODES; do
    # Execute discovery script on remote nodes via SSH
    # Pass MIN, MAX, and PATTERN as positional arguments
    RAW_OUT=$(ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET "core@$node" "sudo bash -s $MIN_GIB $MAX_GIB $DISK_KNAME_PATTERN" < find-secondary-device.sh)
    DISK_NAME=$(echo "$RAW_OUT" | awk '{print $1}')
    FOUND_PATH=$(echo "$RAW_OUT" | awk '{print $2}')
    # Append to local env file; empty paths will be filtered later
    echo "export DEVICE_PATH_$COUNTER=$FOUND_PATH" >> "$OUTPUT_ENV_FILE"
    
    if [ -n "$FOUND_PATH" ]; then
        echo -e "$INFO_MSG Node $node node found device: $FOUND_PATH ($DISK_NAME)" 
    else
        # Critical Error: If any node fails to find a disk, stop the script immediately
        echo -e "$FAIL_MSG Node $node no matching unused disk found ($ODF_DISK_SIZE)"
        rm -f find-secondary-device.sh
        exit 1
    fi
    COUNTER=$((COUNTER + 1))
done

# 5. Final Processing: Deduplication and Empty Value Removal
if [ -s "$OUTPUT_ENV_FILE" ]; then
    echo -e "$INFO_MSG Deduplicating and cleaning $OUTPUT_ENV_FILE"
    # Filter: 1. Value must not be empty ($2 != "") 2. Value must be unique (!seen[$2]++)
    TEMP_FILE=$(mktemp)
    awk -F'=' '$2 != "" && !seen[$2]++' "$OUTPUT_ENV_FILE" > "$TEMP_FILE"
    mv -f "$TEMP_FILE" "$OUTPUT_ENV_FILE"
    # Source variables into current session
    source "./$OUTPUT_ENV_FILE"
    echo -e "$INFO_MSG Final variables applied successfully"
else
    echo -e "$FAIL_MSG No secondary block devices were discovered"
fi

# Cleanup temporary files
rm -f find-secondary-device.sh
rm -f "$OUTPUT_ENV_FILE"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Deploying Local Storage Operator]"

# Create namespace, operator group, subscription
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-local-storage
  annotations:
    openshift.io/node-selector: ""
    workload.openshift.io/allowed: management
EOF
run_command "Create a openshift-local-storage namespace"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: local-operator-group
  namespace: openshift-local-storage
spec:
  targetNamespaces:
    - openshift-local-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: local-storage-operator
  namespace: openshift-local-storage
spec:
  channel: stable
  installPlanApproval: "Manual"
  source: ${CATALOG_SOURCE_NAME}
  name: local-storage-operator
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the local storage operator"

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=openshift-local-storage

MSG="Waiting for unapproved install plans in namespace $OPERATOR_NS"
while true; do
    # Get unapproved InstallPlans
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)

    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true

        # Overwrite previous INFO line with final approved message
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace has no unapproved install plans%*s\n" \
               "$OPERATOR_NS" $((LINE_WIDTH - ${#OPERATOR_NS} - 45)) ""
        break
    fi
done

sleep 5

# Stage 2: Quickly approve all remaining unapproved InstallPlans
while true; do
    # Get all unapproved InstallPlans; if none exist, exit the loop
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)
    if [[ -z "$INSTALLPLAN" ]]; then
        break
    fi
    # Loop through and approve each InstallPlan
    for NAME in $INSTALLPLAN; do
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
    done
    # Slight delay to avoid excessive polling
    sleep "$SLEEP_INTERVAL"
done

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=900                # Maximum number of retries
SLEEP_INTERVAL=2               # Sleep interval in seconds
LINE_WIDTH=120                 # Control line width
SPINNER=('/' '-' '\' '|')      # Spinner animation characters
retry_count=0                  # Number of status check attempts
progress_started=false         # Tracks whether the spinner/progress line has been started
project=$OPERATOR_NS
pod_name=local-storage-operator

while true; do
    # 1. Capture the Ready status column (e.g., "1/1", "0/2") for pods matching the name
    RAW_STATUS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # 2. Logic to determine if pods are ready
    if [[ -z "$RAW_STATUS" ]]; then
        # If RAW_STATUS is empty, it means no pods were found
        is_ready=false
    else
        # Check if any pod has 'ready' count not equal to 'total' count
        not_ready_count=$(echo "$RAW_STATUS" | awk -F/ '$1 != $2' | wc -l)
        if [[ $not_ready_count -eq 0 ]]; then
            is_ready=true
        else
            is_ready=false
        fi
    fi

    # 3. Handle UI output and loop control
    if $is_ready; then
        # Successfully running
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        # Still waiting or pod not found yet
        CHAR=${SPINNER[$((retry_count % 4))]}
        # Provide different messages if pods are missing vs. starting
        MSG="Waiting for $pod_name pods to be Running..."
        [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."

        if ! $progress_started; then
            printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        fi

        # 4. Retry management
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
            exit 1
        fi
    fi
done

# Create the local volume resource
oc create -f - <<EOF >/dev/null 2>&1 
apiVersion: "local.storage.openshift.io/v1"
kind: "LocalVolume"
metadata:
  name: "local-disk"
  namespace: "openshift-local-storage" 
spec:
  nodeSelector: 
    nodeSelectorTerms:
    - matchExpressions:
        - key: $LSO_NODES_LABEL
          operator: In
          values:
          - ""
  storageClassDevices:
    - storageClassName: "local-sc" 
      forceWipeDevicesAndDestroyAllData: false
      volumeMode: Block 
      devicePaths: 
$(for v in $(compgen -A variable | grep -E '^DEVICE_PATH_[0-9]+$' | sort -V); do
    echo "        - ${!v}"
done)
EOF
run_command "Create the local volume resource"

sleep 10

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=500               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=$OPERATOR_NS
pod_name=diskmaker-manager

while true; do
    # 1. Capture the Ready status column (e.g., "1/1", "0/2") for pods matching the name
    RAW_STATUS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # 2. Logic to determine if pods are ready
    if [[ -z "$RAW_STATUS" ]]; then
        # If RAW_STATUS is empty, it means no pods were found
        is_ready=false
    else
        # Check if any pod has 'ready' count not equal to 'total' count
        not_ready_count=$(echo "$RAW_STATUS" | awk -F/ '$1 != $2' | wc -l)
        if [[ $not_ready_count -eq 0 ]]; then
            is_ready=true
        else
            is_ready=false
        fi
    fi

    # 3. Handle UI output and loop control
    if $is_ready; then
        # Successfully running
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        # Still waiting or pod not found yet
        CHAR=${SPINNER[$((retry_count % 4))]}
        # Provide different messages if pods are missing vs. starting
        MSG="Waiting for $pod_name pods to be Running..."
        [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."

        if ! $progress_started; then
            printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        fi

        # 4. Retry management
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
            exit 1
        fi
    fi
done

sleep 3

# Check if a StorageClass named `local-sc` exists
oc get sc local-sc >/dev/null 2>&1 
run_command "Check if a StorageClass named local-sc exists"

# Check Local PV status
export SECOND_DISK_NODE_COUNT=$(echo $LSO_NODES | wc -w)
MAX_RETRIES=60                         # Maximum number of retries
SLEEP_INTERVAL=2                       # Sleep interval in seconds
SPINNER=('/' '-' '\' '|')              # Spinner animation characters
retry_count=0                          # Number of status check attempts
progress_started=false                 # Tracks whether the spinner/progress line has been started
MIN_PV_COUNT=$SECOND_DISK_NODE_COUNT   # Expected number of Local PVs
INFO_MSG="\e[96mINFO\e[0m"
FAIL_MSG="\e[31mFAILED\e[0m"

while true; do
    # Get Local PVs
    mapfile -t pv_list < <(oc get pv -o jsonpath='{range .items[?(@.spec.local)]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}')
    pv_count=${#pv_list[@]}

    CHAR=${SPINNER[$((retry_count % 4))]}

    if [[ $pv_count -ge $MIN_PV_COUNT ]]; then
        all_ok=true
        for pv_entry in "${pv_list[@]}"; do
            pv_name=$(echo "$pv_entry" | awk '{print $1}')
            pv_status=$(echo "$pv_entry" | awk '{print $2}')
            if [[ "$pv_status" != "Available" && "$pv_status" != "Bound" ]]; then
                all_ok=false
            fi
        done

        if $all_ok; then
            printf "\r"  # Move to beginning of line
            tput el      # Clear line
            echo -e "$INFO_MSG All $MIN_PV_COUNT Local PVs are Available/Bound"
            break
        fi
    fi

    # Print spinner line
    if ! $progress_started; then
        progress_started=true
    fi
    printf "\r$INFO_MSG Waiting for $MIN_PV_COUNT Local PVs to be ready %s" "$CHAR"
    tput el

    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r"
        tput el
        echo -e "$FAIL_MSG Timeout waiting for $MIN_PV_COUNT Local PVs"
        exit 1
    fi
done

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Deploying OpenShift Data Foundation]"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-storage
spec: {}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: odf-operator
  namespace: openshift-storage
spec:
  channel: ${ODF_CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: odf-operator
  source: ${CATALOG_SOURCE_NAME}
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the odf operator"

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=openshift-storage

MSG="Waiting for unapproved install plans in namespace $OPERATOR_NS"
while true; do
    # Get unapproved InstallPlans
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)

    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true

        # Overwrite previous INFO line with final approved message
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace has no unapproved install plans%*s\n" \
               "$OPERATOR_NS" $((LINE_WIDTH - ${#OPERATOR_NS} - 45)) ""
        break
    fi
done

sleep 5

# Stage 2: Quickly approve all remaining unapproved InstallPlans
while true; do
    # Get all unapproved InstallPlans; if none exist, exit the loop
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)
    if [[ -z "$INSTALLPLAN" ]]; then
        break
    fi
    # Loop through and approve each InstallPlan
    for NAME in $INSTALLPLAN; do
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
    done
    # Slight delay to avoid excessive polling
    sleep "$SLEEP_INTERVAL"
done

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=900                # Maximum number of retries
SLEEP_INTERVAL=2               # Sleep interval in seconds
LINE_WIDTH=120                 # Control line width
SPINNER=('/' '-' '\' '|')      # Spinner animation characters
retry_count=0                  # Number of status check attempts
progress_started=false         # Tracks whether the spinner/progress line has been started
project=$OPERATOR_NS
pod_name=odf-operator

while true; do
    # 1. Capture the Ready status column (e.g., "1/1", "0/2") for pods matching the name
    RAW_STATUS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # 2. Logic to determine if pods are ready
    if [[ -z "$RAW_STATUS" ]]; then
        # If RAW_STATUS is empty, it means no pods were found
        is_ready=false
    else
        # Check if any pod has 'ready' count not equal to 'total' count
        not_ready_count=$(echo "$RAW_STATUS" | awk -F/ '$1 != $2' | wc -l)
        if [[ $not_ready_count -eq 0 ]]; then
            is_ready=true
        else
            is_ready=false
        fi
    fi

    # 3. Handle UI output and loop control
    if $is_ready; then
        # Successfully running
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        # Still waiting or pod not found yet
        CHAR=${SPINNER[$((retry_count % 4))]}
        # Provide different messages if pods are missing vs. starting
        MSG="Waiting for $pod_name pods to be Running..."
        [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."

        if ! $progress_started; then
            printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        fi

        # 4. Retry management
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
            exit 1
        fi
    fi
done

# Enable console plugin
oc patch console.operator cluster -n openshift-storage --type json -p '[{"op": "add", "path": "/spec/plugins", "value": ["odf-console"]}]' >/dev/null 2>&1
run_command "Enable console plugin"

# Add the $ODF_NODES_LABEL label to the ODF node
for n in $ODF_NODES; do
  if oc label node $n $ODF_NODES_LABEL="" --overwrite >/dev/null 2>&1; then
    echo -e "$INFO_MSG Add the ODF label to the $n node"
  else
    echo -e "$FAIL_MSG Add the ODF label to the $n node"
  fi
done

oc create -f - <<EOF >/dev/null 2>&1 
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
  multiCloudGateway:
    disableLoadBalancerService: true
  storageDeviceSets:
  - count: 1  # Modify count to desired value. For each set of 3 disks increment the count by 1.
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: "${ODF_DISK_SIZE}"  # This should be changed as per storage size. Minimum 100 GiB and Maximum 4 TiB
        storageClassName: local-sc
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
run_command "Create the StorageCluster resource..."

sleep 10

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=180              # Maximum number of retries
SLEEP_INTERVAL=5             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=openshift-storage

# Main loop
while true; do
    # 1. Check Deployments
    # READY column format: x/y  -> x must equal y
    DEPLOY_NOT_READY=$(oc -n "$namespace" get deploy --no-headers 2>/dev/null | \
    awk '{
        split($2, a, "/");
        if (a[1] != a[2]) print
    }' || true)

    # 2. Check DaemonSets
    # DESIRED == READY
    DS_NOT_READY=$(oc -n "$namespace" get ds --no-headers 2>/dev/null | \
    awk '$2 != $4 {print}' || true)

    # 3. Success condition
    if [[ -z "$DEPLOY_NOT_READY" && -z "$DS_NOT_READY" ]]; then
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m All Deployments and DaemonSets in %s are Ready%*s\n" \
                   "$namespace" $((LINE_WIDTH - ${#namespace} - 47)) ""
        else
            echo -e "\e[96mINFO\e[0m All Deployments and DaemonSets in $namespace are Ready"
        fi
        break
    fi

    # 4. Spinner / progress output
    CHAR=${SPINNER[$((retry_count % 4))]}
    MSG="Waiting for Deployments and DaemonSets in $namespace to be Ready..."

    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # 5. Retry & timeout handling
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m Deployments or DaemonSets in %s are not Ready%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 55)) ""

        [[ -n "$DEPLOY_NOT_READY" ]] && echo "$DEPLOY_NOT_READY" || echo "None"

        [[ -n "$DS_NOT_READY" ]] && echo "$DS_NOT_READY" || echo "None"
        exit 1
    fi
done

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=20            # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=openshift-storage

while true; do
    # 1. Get the READY column for all pods, excluding Completed ones
    POD_STATUS_LIST=$(oc -n "$namespace" get po --no-headers 2>/dev/null | grep -v "Completed" | awk '{print $2}' || true)

    # 2. Check if any pods exist and if they are all ready
    if [[ -n "$POD_STATUS_LIST" ]]; then
        # Check for pods where Ready count (left) is not equal to Total count (right)
        not_ready_exists=$(echo "$POD_STATUS_LIST" | awk -F/ '$1 != $2')
        
        if [[ -z "$not_ready_exists" ]]; then
            # SUCCESS: Pods exist AND all of them are ready
            if $progress_started; then
                printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                       "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
            else
                echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
            fi
            break
        fi
    fi

    # 3. If we reach here, either no pods exist yet or some are not ready
    CHAR=${SPINNER[$((retry_count % 4))]}
    
    # Define feedback message based on whether pods are missing or starting
    MSG="Waiting for $namespace namespace pods to be Running..."
    [[ -z "$POD_STATUS_LIST" ]] && MSG="Waiting for $namespace pods to be created..."

    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # 4. Handle timeout and retry
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 45)) ""
        exit 1
    fi
done

echo -e "\e[96mINFO\e[0m Wait until all Pods in the openshift-storage namespace are running"

# Add an empty line after the task
echo

# Check the environment variable CREATE_OBC_AND_CREDENTIALS: continue if "true", exit if otherwise
if [[ "$CREATE_OBC_AND_CREDENTIALS" != "true" ]]; then
    exit 0
fi

# Step 4:
PRINT_TASK "TASK [Create ObjectBucketClaims and S3 credentials]"

# Delete Secrets, ConfigMaps, ObjectBuckets, and ObjectBucketClaims in the ${OBC_NAMESPACE} namespace
timeout 2s oc delete pvc --all -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true 

timeout 2s oc delete secret ${OBC_NAME}-obc-credentials -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch secret loki-bucket-credentials -n openshift-logging -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete secret ${OBC_NAME} -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch secret loki -n openshift-logging -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete objectbucket obc-${OBC_NAMESPACE}-${OBC_NAME} -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch objectbucket obc-${OBC_NAMESPACE}-${OBC_NAME} -n ${OBC_NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete objectbucketclaim ${OBC_NAME} -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch objectbucketclaim ${OBC_NAME} -n ${OBC_NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete cm ${OBC_NAME} -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch cm ${OBC_NAME} -n ${OBC_NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

# Check if namespace exists; if not, create it
if ! oc get namespace "${OBC_NAMESPACE}" >/dev/null 2>&1; then
    cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: ${OBC_NAMESPACE}
  labels:
    openshift.io/cluster-monitoring: "true"
  annotations:
    openshift.io/node-selector: ""
spec: {}
EOF
    echo -e "\e[96mINFO\e[0m Namespace ${OBC_NAMESPACE} created"
else
    echo -e "\e[96mINFO\e[0m Namespace ${OBC_NAMESPACE} already exists"
fi

# Create an ObjectBucketClaim named ${OBC_NAME}
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  finalizers:
  - objectbucket.io/finalizer
  labels:
    app: noobaa
    bucket-provisioner: openshift-storage.noobaa.io-obc
    noobaa-domain: openshift-storage.noobaa.io
  name: ${OBC_NAME}
  namespace: ${OBC_NAMESPACE}
spec:
  additionalConfig:
    bucketclass: noobaa-default-bucket-class
  generateBucketName: ${OBC_NAME}
  objectBucketName: obc-${OBC_NAMESPACE}-${OBC_NAME}
  storageClassName: ${OBC_STORAGECLASS_S3}
EOF
run_command "Create an ObjectBucketClaim named ${OBC_NAME}"

# Waiting for configmap to be created
MAX_RETRIES=180              # Maximum number of retries
SLEEP_INTERVAL=5             # Sleep interval in seconds
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
CONFIGMAP_NAME=${OBC_NAME}
NAMESPACE=${OBC_NAMESPACE}

# Loop to wait for the configmap creation
while true; do
    # Check if the configmap exists
    configmap_exists=$(oc get configmap -n "$NAMESPACE" "$CONFIGMAP_NAME" --no-headers 2>/dev/null || true)
    
    CHAR=${SPINNER[$((retry_count % 4))]}

    if [ -n "$configmap_exists" ]; then
        # Overwrite the spinner line before printing the final message
        printf "\r"    # Move cursor to the beginning of the line
        tput el        # Clear the entire line
        echo -e "\e[96mINFO\e[0m The configmap '$CONFIGMAP_NAME' has been created"
        break
    else
        # Print the waiting message only once
        if ! $progress_started; then
            progress_started=true
        fi

        # Display spinner on the same line
        printf "\r\e[96mINFO\e[0m Waiting for configmap '%s' to be created %s" "$CONFIGMAP_NAME" "$CHAR"
        tput el  # Clear to the end of the line
    fi

    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Exit when max retries reached
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r"  # Move to the beginning of the line
        tput el      # Clear the entire line
        echo -e "\e[31mFAILED\e[0m Reached max retries, configmap '$CONFIGMAP_NAME' was not created"
        exit 1
    fi
done

# Get bucket properties from the associated ConfigMap
export BUCKET_HOST=$(oc get -n ${OBC_NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
export BUCKET_NAME=$(oc get -n ${OBC_NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
export BUCKET_PORT=$(oc get -n ${OBC_NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')

# Get bucket access key from the associated Secret
export ACCESS_KEY_ID=$(oc get -n ${OBC_NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
export SECRET_ACCESS_KEY=$(oc get -n ${OBC_NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

# Create the ObjectBucketClaim resource
oc create -n ${OBC_NAMESPACE} secret generic ${OBC_NAME}-obc-credentials \
   --from-literal=access_key_id="${ACCESS_KEY_ID}" \
   --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
   --from-literal=bucketnames="${BUCKET_NAME}" \
   --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}" >/dev/null 2>&1
run_command "Object storage secret '${OBC_NAME}-credentials' created in ${OBC_NAMESPACE}"
