#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export STORAGE_SIZE="50Gi"   # Requires default storage class
export BUCKETS=("loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket")

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
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 1:
PRINT_TASK "TASK [Deploying Minio Object Storage]"

# Deploy Minio with the specified YAML template
echo "info: [Uninstall minio resources...]"
oc delete project minio >/dev/null 2>&1 || true
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
      storage: ${STORAGE_SIZE}
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
run_command "[Deploying minio object storage]]"

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
            echo -n "info: [Waiting for pods to be in 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [Minio pods are in 'Running' state]"
        break
    fi
done

sleep 3

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')

# Set Minio client alias
oc rsh -n minio deployments/minio mc alias set my-minio ${BUCKET_HOST} minioadmin minioadmin > /dev/null
run_command "[Configured minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "${BUCKETS[@]}"; do
    oc rsh -n minio deployments/minio \
        mc --no-color mb my-minio/$BUCKET_NAME > /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done

grep -qxF "alias mc='oc -n minio exec -it deployment/minio -- mc'" ~/.bashrc || \
echo "alias mc='oc -n minio exec -it deployment/minio -- mc'" >> ~/.bashrc
run_command "[Add mc cli alias to $HOME/.bashrc]"

# Print Minio address and credentials
echo "info: [Minio Host: $BUCKET_HOST]"
echo "info: [Minio default Id/PW: minioadmin/minioadmin]"
echo "info: [Run source ~/.bashrc to make the mc alias take effect]"
