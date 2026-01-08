#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Default storage class name
export DEFAULT_STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
export PVC_SIZE="50Gi"

# Name of the bucket to be created
export BUCKETS=("loki-bucket" "quay-bucket" "oadp-bucket")

# Whether to create 'minio-credentials' secret
export CREATE_MINIO_CREDENTIALS="false"  # true or false
export BUCKET_NAME="loki-bucket"
export BUCKET_NAMESPACE="openshift-logging"


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

# Delete minio project
if oc get project minio >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting minio project..."
    oc delete project minio >/dev/null 2>&1
fi

# Delete minio pv 
oc get pv -o json | jq -r '.items[] | select(.spec.claimRef.namespace=="minio") | .metadata.name' | xargs -r oc delete pv >/dev/null 2>&1 || true

# Check if Default StorageClass exists
DEFAULT_STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    echo -e "\e[31mFAILED\e[0m No default StorageClass found!"
    exit 1
else
    echo -e "\e[96mINFO\e[0m Default StorageClass found: $DEFAULT_STORAGE_CLASS"
fi

# Deploy minio resources
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

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=60                # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=minio
pod_name=minio

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

sleep 5

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
export MINIO_CONSOLE=$(oc get route minio-console -n minio -o jsonpath='http://{.spec.host}')

# Set Minio client alias
# MINIO_POD=$(oc get pod -n minio -l app=minio -o jsonpath='{.items[0].metadata.name}')
# oc exec -n minio "$MINIO_POD" -- mc alias set my-minio "${BUCKET_HOST}" minioadmin minioadmin >/dev/null 2>&1
oc exec -n minio deploy/minio -- mc alias set my-minio "${BUCKET_HOST}" minioadmin minioadmin >/dev/null 2>&1
run_command "Configured Minio client alias"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "${BUCKETS[@]}"; do
    oc exec -n minio deploy/minio -- mc --no-color mb my-minio/$BUCKET_NAME >/dev/null 2>&1
    run_command "Create bucket $BUCKET_NAME"
done

grep -qxF "alias mc='oc -n minio exec deploy/minio -- mc'" ~/.bashrc || echo "alias mc='oc -n minio exec deploy/minio -- mc'" >> $HOME/.bashrc
run_command "Add mc cli alias to $HOME/.bashrc"

# Print Minio address and credentials
echo -e "\e[96mINFO\e[0m Minio Host: $BUCKET_HOST"
echo -e "\e[96mINFO\e[0m Minio Console: $MINIO_CONSOLE"
echo -e "\e[96mINFO\e[0m Minio default ID/PW: minioadmin/minioadmin"

# Check the environment variable CREATE_MINIO_CREDENTIALS: continue if "true", exit if otherwise
if [[ "$CREATE_MINIO_CREDENTIALS" != "true" ]]; then
    exit 0
fi

# create object storage secret credentials
export MINIO_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: ${BUCKET_NAMESPACE}
stringData:
  access_key_id: minioadmin
  access_key_secret: minioadmin
  bucketnames: ${BUCKET_NAME}
  endpoint: ${MINIO_HOST}
  region: minio
EOF
run_command "Object storage secret minio-credentials created in ${BUCKET_NAMESPACE}"
