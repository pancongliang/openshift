#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# [REQUIRED] Default StorageClass must exist
export PVC_SIZE="50Gi"
export BUCKETS=("loki-bucket" "quay-bucket" "oadp-bucket")

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

PRINT_TASK "TASK [Deploying Minio Object Storage]"

if oc get project minio >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting minio project..."
    oc delete project minio >/dev/null 2>&1
fi
oc get pv -o json | jq -r '.items[] | select(.spec.claimRef.namespace=="minio") | .metadata.name' | xargs -r oc delete pv >/dev/null 2>&1 || true

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: minio
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  selector:
    matchLabels:
      app: minio
  replicas: 1
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        command:
        - /bin/bash
        - -c
        args: 
        - minio server /data --console-address :9090
        volumeMounts:
        - mountPath: /data
          name: minio-pvc
      volumes:
      - name: minio-pvc
        persistentVolumeClaim:
          claimName: minio-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pvc
  namespace: minio
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_SIZE}
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  selector:
    app: minio
  ports:
    - name: 9090-tcp
      protocol: TCP
      port: 9090
      targetPort: 9090
    - name: 9000-tcp
      protocol: TCP
      port: 9000
      targetPort: 9000
---
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: minio-console
  namespace: minio
  labels:
    app: minio
spec:
  to:
    kind: Service
    name: minio
  port:
    targetPort: 9090
---
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: minio
  namespace: minio
  labels:
    app: minio
spec:
  to:
    kind: Service
    name: minio
  port:
    targetPort: 9000
EOF
run_command "Deploying Minio Object Storage"

# Wait for Minio pods to be in 'Running' state
# Initialize progress_started as false
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n minio --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for pods to be in 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m Minio pods are in 'Running' state"
        break
    fi
done

echo -e "\e[96mINFO\e[0m Installation complete"

sleep 3

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')

# Set Minio client alias
MINIO_POD=$(oc get pod -n minio -l app=minio -o jsonpath='{.items[0].metadata.name}')
# oc exec -n minio "$MINIO_POD" -- mc alias set my-minio "${BUCKET_HOST}" minioadmin minioadmin > /dev/null
# oc exec -n minio deploy/minio -- mc alias set my-minio "${BUCKET_HOST}" minioadmin minioadmin > /dev/null
run_command "Configured Minio client alias"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "${BUCKETS[@]}"; do
    oc exec -n minio deploy/minio -- mc --no-color mb my-minio/$BUCKET_NAME > /dev/null
    run_command "Create bucket $BUCKET_NAME"
done

grep -qxF "alias mc='oc -n minio exec -it deployment/minio -- mc'" ~/.bashrc || \
echo "alias mc='oc -n minio exec deploy/minio -- mc'" >> ~/.bashrc
run_command "Add mc cli alias to $HOME/.bashrc"

# Print Minio address and credentials
echo -e "\e[96mINFO\e[0m Minio Host: $BUCKET_HOST"
echo -e "\e[96mINFO\e[0m Minio default ID/PW: minioadmin/minioadmin"
echo -e "\e[96mINFO\e[0m Apply the mc alias by running: source ~/.bashrc"
