#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export NFS_SERVER_IP="10.184.134.30"
export NFS_DIR="/nfs"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
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

PRINT_TASK "TASK [Install and Configure NFS Server]"

# Install nfs-utils
sudo rpm -q nfs-utils >/dev/null 2>&1 || sudo dnf install -y nfs-utils
run_command "Install nfs-utils package"

# Check if NFS_DIR exists and create it if missing
if [[ -d "${NFS_DIR}" ]]; then
    echo -e "$INFO_MSG Directory ${NFS_DIR} already exists, skipping creation"
else
    mkdir -p "${NFS_DIR}"
    echo -e "$INFO_MSG Directory ${NFS_DIR} created successfully"
fi

# Add nfsnobody user if not exists
if id "nfsnobody" >/dev/null 2>&1; then
    echo -e "$INFO_MSG User nfsnobody exists"
else
    sudo useradd nfsnobody
    echo -e "$INFO_MSG Create the nfsnobody user"
fi

# Change ownership and permissions
sudo chown -R nfsnobody.nfsnobody ${NFS_DIR} >/dev/null 2>&1
run_command "Set ownership of nfs directory"

sudo chmod -R 777 ${NFS_DIR} >/dev/null 2>&1
run_command "Set permissions of nfs directory"

# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo -e "$INFO_MSG Export configuration for nfs already exists"
else
    echo "$export_config_line" >> "/etc/exports"
    echo -e "$INFO_MSG Setting up nfs export configuration"
fi

# Enable and start service
systemctl enable nfs-server >/dev/null 2>&1
run_command "Enable nfs server service at boot"

systemctl restart nfs-server >/dev/null 2>&1
run_command "Restart nfs server service"

# Add an empty line after the task
echo

# Task: Install NFS storage class
PRINT_TASK "TASK [Install NFS Storage Class]"

export NAMESPACE="nfs-client-provisioner"
if oc get project ${NAMESPACE} >/dev/null 2>&1; then
    echo -e "$INFO_MSG Deleting ${NAMESPACE} project..."
    oc delete project ${NAMESPACE} >/dev/null 2>&1
fi

oc delete clusterrole nfs-client-provisioner-runner > /dev/null 2>&1 || true
oc delete clusterrolebinding run-nfs-client-provisioner > /dev/null 2>&1 || true
oc delete storageclass managed-nfs-storage > /dev/null 2>&1 || true

# Create namespace
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
run_command "Create new namespace: ${NAMESPACE}"

# Create sa and rbac
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    # replace with namespace where provisioner is deployed
    namespace: ${NAMESPACE}
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    # replace with namespace where provisioner is deployed
    namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io
EOF
run_command "Create RBAC configuration"

# Add scc
oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:${NAMESPACE}:nfs-client-provisioner >/dev/null
run_command "Add scc hostmount-anyuid to nfs-client-provisioner user"

# deployment
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-client-provisioner
  labels:
    app: nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nfs-client-provisioner
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: nfs-storage-provisioner
            - name: NFS_SERVER
              value: ${NFS_SERVER_IP}
            - name: NFS_PATH
              value: ${NFS_DIR}
      volumes:
        - name: nfs-client-root
          nfs:
            server: ${NFS_SERVER_IP}
            path: ${NFS_DIR}
EOF
run_command "Deploy nfs-client-provisioner pod"

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=500               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=${NAMESPACE}
pod_name=nfs-client-provisioner

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

# Storage Class
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-nfs-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs-storage-provisioner     
parameters:
  archiveOnDelete: "false"
  reclaimPolicy: Retain
EOF
run_command "Create nfs storage class"

echo -e "$INFO_MSG Installation complete"

# Add an empty line after the task
echo
