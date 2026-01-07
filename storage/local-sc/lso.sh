#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Define the device pattern to search for
export DEVICE_PATTERN="sd*"
export CATALOG_SOURCE_NAME="redhat-operators"

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

# Step 0:
PRINT_TASK "TASK [Delete old Local Storage Operator resources]"

# Delete local volume and pv, sc
(oc get localvolumes -n openshift-local-storage -o name 2>/dev/null | xargs -r -I {} oc -n openshift-local-storage delete {} 2>/dev/null) >/dev/null 2>&1 || true
(oc get localvolume -n openshift-local-storage -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | xargs -r -I {} oc patch localvolume {} -n openshift-local-storage --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null) >/dev/null 2>&1 || true
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
#else
#   echo -e "\e[96mINFO\e[0m The local-storage-operator subscription does not exist"
fi

if oc get ns openshift-local-storage >/dev/null 2>&1 || true; then
   echo -e "\e[96mINFO\e[0m Deleting openshift-local-storage namespace..."
   oc delete ns openshift-local-storage >/dev/null 2>&1 || true
#else
#   echo -e "\e[96mINFO\e[0m The openshift-local-storage namespace does not exist"
fi

# Clean up local storage (Only prints if files were deleted)
for Hostname in $(oc get nodes -l node-role.kubernetes.io/worker= \
  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do

  ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$Hostname "
    if [ -d /mnt/local-storage ] && [ \"\$(ls -A /mnt/local-storage 2>/dev/null)\" ]; then
      echo -e \"\e[96mINFO\e[0m $Hostname delete /mnt/local-storage files\"
      sudo rm -rf /mnt/local-storage/*
    else
      echo -e \"\e[96mINFO\e[0m $Hostname /mnt/local-storage not exist or empty, skip\"
    fi
  "
done

# Wiped second attached disk /dev/$disk
for Hostname in $(oc get nodes -l node-role.kubernetes.io/worker= -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
  ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$Hostname "
    # Find the first attached disk that is not the system/root disk
    disk=\$(lsblk -dnlo NAME,TYPE | awk '\$2==\"disk\" {print \$1}' | while read d; do
        # Skip system/root disk (with partitions or mounted paths)
        if ! lsblk /dev/\$d | grep -q '/boot\|/var\|/ \|part'; then
            echo \$d
            break
        fi
    done)

    if [ -n \"\$disk\" ]; then
        sudo wipefs -a /dev/\$disk >/dev/null 2>&1
        echo -e \"\e[96mINFO\e[0m $Hostname Wiped second attached disk /dev/\$disk\"
    else
        echo -e \"\e[96mINFO\e[0m $Hostname No second attached disk found, skip\"
    fi
  "
done

# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Automating discovery for local storage devices]"

# ===============================================
# Define the output environment file name
OUTPUT_ENV_FILE="generated_vars.env"

# Define color output variables
INFO_MSG="\e[96mINFO\e[0m"
FAIL_MSG="\e[31mFAILED\e[0m"
MSG_WARN="\e[33mWARN\e[0m"

# Initialize or clear the output file
rm -rf "$OUTPUT_ENV_FILE"

echo -e "$INFO_MSG Starting discovery for unused devices matching pattern: '$DEVICE_PATTERN'"

# Generate the remote execution script
cat << EOF > find-secondary-device.sh
#!/bin/bash
set -uo pipefail

NODE_NAME="\$(hostname)" 
COUNTER=\$1

# Internal color variables for remote node output
MSG_INFO="\e[96mINFO\e[0m"
MSG_FAIL="\e[31mFAILED\e[0m"
MSG_WARN="\e[33mWARN\e[0m"

# Enable nullglob to prevent errors if no devices match
shopt -s nullglob

# Iterate over devices
for device in /dev/$DEVICE_PATTERN; do
  # Check if device is valid (blkid returns 2 means no filesystem, i.e., empty disk)
  /usr/sbin/blkid "\${device}" &> /dev/null
  if [ \$? == 2 ]; then
    # Get the /dev/disk/by-path/ identifier
    DEVICE_PATH=\$(ls -l /dev/disk/by-path/ | awk -v dev="\${device##*/}" '\$0 ~ dev {print "/dev/disk/by-path/" \$9}')

    # Output the export statement to stdout (will be captured into the local env file)
    echo "export DEVICE_PATH_\$COUNTER=\$DEVICE_PATH"
    
    # Output the info message to stderr (will be displayed on the screen)
    echo -e "\$MSG_INFO \$NODE_NAME: Found unused device \$DEVICE_PATH" >&2
    
    exit 0
  fi
done

# If no device is found after the loop
echo -e "\$MSG_WARN \$NODE_NAME: No secondary block device found matching $DEVICE_PATTERN" >&2
EOF

# Get the list of worker nodes
echo -e "$INFO_MSG Fetching worker nodes list..."
NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o=jsonpath='{.items[*].metadata.name}')

if [ -z "$NODES" ]; then
    echo -e "$FAIL_MSG No worker nodes found via 'oc' command."
    rm -f find-secondary-device.sh
    exit 1
fi

# Counter initialization
COUNTER=1

# Loop through each node
for node in $NODES; do
  # Execute via SSH
  # stdout (variables) >> appended to local file
  # stderr (colored logs) -> displayed on bastion screen
  ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET core@$node "sudo bash -s $COUNTER" < find-secondary-device.sh >> "$OUTPUT_ENV_FILE"
  
  # Increment counter
  COUNTER=$((COUNTER + 1))
done

# Clean up the temporary script
rm -f find-secondary-device.sh

echo -e "$INFO_MSG Discovery process finished"

# Check if the environment file has content and source it
if [ -s "$OUTPUT_ENV_FILE" ]; then
    echo -e "$INFO_MSG Applying variables from $OUTPUT_ENV_FILE"
    
    # Sourcing the file within the script
    source "./$OUTPUT_ENV_FILE"
else
    echo -e "$FAIL_MSG No variables were generated. The env file is empty."
fi

# Initialize or clear the output file
rm -rf "$OUTPUT_ENV_FILE"

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

# Add the local-storage tag to the worker node
oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} local.storage.openshift.io/openshift-local-storage='' >/dev/null 2>&1 
run_command "Add the local-storage tag to the worker node"

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
        - key: local.storage.openshift.io/openshift-local-storage
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
oc get pv -o jsonpath='{range .items[?(@.spec.local)]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' | \
while read pv status; do
  if [[ "$status" != "Available" && "$status" != "Bound" ]]; then
    echo -e "$FAIL_MSG $pv status: $status"
  else
    echo -e "$INFO_MSG $pv status: $status"
  fi
done

echo -e "\e[96mINFO\e[0m Installation complete"

# Add an empty line after the task
echo
