#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Define the device pattern to search for
# Ensure the OCP cluster has at least three worker nodes, each with at least one 100GB disk.
export DISK_KNAME_PATTERN="sd[b-z]"
export ODF_DISK_SIZE="100Gi"         # At least 100GB of disk space, By default, it will format the non-root disk and reference the second disk (sd*).
export LSO_NODES="worker01.ocp.example.com worker02.ocp.example.com worker03.ocp.example.com"

# Install version
export CATALOG_SOURCE_NAME="redhat-operators"

# Set the label variable
export LSO_NODES_LABEL="local.storage.openshift.io/openshift-local-storage"

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
        echo -e "\e[31mFAIL\e[0m $1"
        exit 1
    fi
}

# Define color output variables
INFO_MSG="\e[96mINFO\e[0m"
FAIL_MSG="\e[31mFAIL\e[0m"
ACTION_MSG="\e[33mACTION\e[0m"

# Step 0:
PRINT_TASK "TASK [Delete old ODF and LSO resources]"

# 1. Cleanup Logic: LSO (Local Storage Operator)
echo -e "$INFO_MSG Starting LSO cleanup process..."

# Delete local volume and pv, sc
timeout 2s oc -n openshift-local-storage delete LocalVolumeDiscovery --all >/dev/null 2>&1 || true
timeout 2s oc -n openshift-local-storage delete LocalVolumeSet --all >/dev/null 2>&1 || true
(oc get localvolumes -n openshift-local-storage -o name 2>/dev/null | xargs -r -I {} oc -n openshift-local-storage delete {} 2>/dev/null) >/dev/null 2>&1 || true
(oc get localvolume -n openshift-local-storage -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | xargs -r -I {} oc patch localvolume {} -n openshift-local-storage --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null) >/dev/null 2>&1 || true
oc get pv | grep local | awk '{print $1}' | xargs -I {} oc patch pv {} -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
oc get pv | grep local | awk '{print $1}' | xargs -I {} oc delete pv {} >/dev/null 2>&1 || true

if oc get sc local-sc >/dev/null 2>&1; then
   echo -e "$INFO_MSG Deleting local-sc storageclasse..."
   oc delete sc local-sc >/dev/null 2>&1 || true
#else
#  echo -e "$INFO_MSG The local-sc storageclasse does not exist"
fi

if oc get sub local-storage-operator -n openshift-local-storage >/dev/null 2>&1 || true; then
   echo -e "$INFO_MSG Deleting local-storage-operator subscription..."
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

# 2. Disk Wiping Logic
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
        printf "\r$INFO_MSG Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r$FAIL_MSG The %s namespace has no unapproved install plans%*s\n" \
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
        printf "\r$INFO_MSG Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
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
            printf "\r$INFO_MSG The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "$INFO_MSG The $pod_name pods are Running"
        fi
        break
    else
        # Still waiting or pod not found yet
        CHAR=${SPINNER[$((retry_count % 4))]}
        # Provide different messages if pods are missing vs. starting
        MSG="Waiting for $pod_name pods to be Running..."
        [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."

        if ! $progress_started; then
            printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
        fi

        # 4. Retry management
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG The %s pods are not Running%*s\n" \
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
            printf "\r$INFO_MSG The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "$INFO_MSG The $pod_name pods are Running"
        fi
        break
    else
        # Still waiting or pod not found yet
        CHAR=${SPINNER[$((retry_count % 4))]}
        # Provide different messages if pods are missing vs. starting
        MSG="Waiting for $pod_name pods to be Running..."
        [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."

        if ! $progress_started; then
            printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
        fi

        # 4. Retry management
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG The %s pods are not Running%*s\n" \
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
