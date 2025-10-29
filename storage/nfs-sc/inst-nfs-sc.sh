#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export NFS_SERVER_IP="10.184.134.128"
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
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}


PRINT_TASK "TASK [Configure and Verify NFS Service]"

# Install nfs-utils
rpm -q nfs-utils >/dev/null 2>&1 || sudo dnf install -y nfs-utils
run_command "[Install nfs-utils package]"

# Create NFS directories
rm -rf ${NFS_DIR} >/dev/null 2>&1
sleep 1
mkdir -p ${NFS_DIR} >/dev/null 2>&1
run_command "[Create ${NFS_DIR} directory]"

# Add nfsnobody user if not exists
if id "nfsnobody" >/dev/null 2>&1; then
    echo "ok: [User nfsnobody exists]"
else
    useradd nfsnobody
    echo "ok: [Create the nfsnobody user]"
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_DIR} >/dev/null 2>&1
run_command "[Set ownership of nfs directory]"

chmod -R 777 ${NFS_DIR} >/dev/null 2>&1
run_command "[Set permissions of nfs directory]"

# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "ok: [Export configuration for nfs already exists]"
else
    echo "$export_config_line" >> "/etc/exports"
    echo "ok: [Setting up nfs export configuration]"
fi

# Enable and start service
systemctl enable nfs-server >/dev/null 2>&1
run_command "[Enable nfs server service at boot]"

systemctl restart nfs-server >/dev/null 2>&1
run_command "[Restart nfs server service]"

# Add an empty line after the task
echo

# Task: Install NFS storage class
PRINT_TASK "TASK [Install NFS storage class]"

echo "info: [Uninstall nfs storage class resources...]"
export NAMESPACE="nfs-client-provisioner"
oc delete ns $NAMESPACE > /dev/null 2>&1 || true
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
run_command "[Create new namespace: ${NAMESPACE}]"

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
run_command "[Create RBAC configuration]"

# Add scc
oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:${NAMESPACE}:nfs-client-provisioner >/dev/null
run_command "[Add scc hostmount-anyuid to nfs-client-provisioner user]"

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
run_command "[Deploy nfs-client-provisioner]"


# Wait for nfs-client-provisioner pods to be in 'Running' state
export NAMESPACE="nfs-client-provisioner"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=nfs-client-provisioner

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name pods to be in 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name pods are in 'Running' state]"
        break
    fi
done

# storage class
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
run_command "[create nfs storage class]"
