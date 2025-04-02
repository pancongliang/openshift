#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export LOGGING_CHANNEL_NAME="stable-6.1"
export LOKI_CHANNEL_NAME="stable-6.1"
export OBSERVABILITY_CHANNEL_NAME="stable"
export CATALOG_SOURCE_NAME=redhat-operators
export STORAGE_CLASS_NAME="managed-nfs-storage"
export STORAGE_SIZE="50Gi"


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

# Step 0:
PRINT_TASK "TASK [Uninstall old logging resources...]"

# Uninstall first
echo "info: [uninstall old logging resources...]"
oc delete uiplugin logging >/dev/null 2>&1 || true
oc delete clusterlogforwarder collector -n openshift-logging >/dev/null 2>&1 || true
oc delete lokistack logging-loki -n openshift-logging >/dev/null 2>&1 || true
oc delete secret loki-bucket-credentials -n openshift-logging >/dev/null 2>&1 || true

oc delete sub loki-operator -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete sub cluster-logging -n openshift-operators >/dev/null 2>&1 || true
oc delete sub cluster-observability-operator -n openshift-cluster-observability-operator >/dev/null 2>&1 || true

oc get csv -n openshift-operators-redhat -o name | grep loki-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get csv -n openshift-logging -o name | grep cluster-logging | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-logging >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep cluster-observability-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true

oc delete operatorgroups openshift-operators-redhat -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete operatorgroups cluster-observability-operator -n cluster-observability-operator >/dev/null 2>&1 || true
oc delete operatorgroups cluster-logging -n openshift-logging >/dev/null 2>&1 || true

oc delete ns openshift-logging >/dev/null 2>&1 || true
oc delete ns openshift-cluster-observability-operator >/dev/null 2>&1 || true

sleep 5

# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Deploying Minio Object Storage]"

# Check if the Deployment exists
if oc get deployment minio -n minio >/dev/null 2>&1; then
    echo "ok: [minio already exists, skipping deployment]"
else
    echo "info: [minio not found, starting deployment...]"

    # Deploy MinIO
    sudo curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/minio-persistent.yaml | envsubst | oc apply -f - >/dev/null 2>&1
    run_command "[deploying minio object storage]"
fi

sleep 5

# Wait for Minio pods to be in 'Running' state
NAMESPACE="minio"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=minio

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all $pod_name pods are in 'running' state]"
        break
    fi
done


# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
run_command "[minio route host: $BUCKET_HOST]"

sleep 20

# Set Minio client alias
oc rsh -n minio deployments/minio mc alias set my-minio ${BUCKET_HOST} minioadmin minioadmin >/dev/null 2>&1
run_command "[configured minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
oc rsh -n minio deployments/minio mc --no-color rb --force my-minio/loki-bucket >/dev/null 2>&1 || true
oc rsh -n minio deployments/minio mc --no-color mb my-minio/loki-bucket >/dev/null 2>&1
run_command "[created bucket loki-bucket]"

# Set environment variables
export ACCESS_KEY_ID="minioadmin"
export ACCESS_KEY_SECRET="minioadmin"
export BUCKET_NAME="loki-bucket"

echo "ok: [minio default id/pw: minioadmin/minioadmin]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Install OpenShift Logging]"

# Create a namespace
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-logging
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
EOF
run_command "[create a openshift-logging namespace]"

cat << EOF | oc apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators-redhat 
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true" 
EOF
run_command "[create a openshift-operators-redhat namespace]"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cluster-observability-operator
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
EOF
run_command "[create a openshift-cluster-observability-operator namespace]"

# Create a OperatorGroup
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-logging
  namespace: openshift-logging 
spec:
  targetNamespaces:
  - openshift-logging 
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging 
spec:
  channel: ${LOGGING_CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: cluster-logging
  source: $CATALOG_SOURCE_NAME
  sourceNamespace: openshift-marketplace
EOF
run_command "[create a cluster-logging-operator]"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-operators-redhat
  namespace: openshift-operators-redhat 
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: "loki-operator"
  namespace: "openshift-operators-redhat" 
spec:
  channel: ${LOKI_CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: loki-operator
  source: $CATALOG_SOURCE_NAME
  sourceNamespace: openshift-marketplace
EOF
run_command "[create a loki-operator]"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  channel: ${OBSERVABILITY_CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: cluster-observability-operator
  source: $CATALOG_SOURCE_NAME
  sourceNamespace: openshift-marketplace
EOF
run_command "[create a cluster-observability-operator]"

# Approval IP
export NAMESPACE="openshift-logging"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve cluster-logging-operator install plan]"

export NAMESPACE="openshift-operators-redhat"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve loki-operator install plan]"

export NAMESPACE="openshift-cluster-observability-operator"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve cluster-observability-operator install plan]"

sleep 15

# Wait for logging-operator pods to be in 'Running' state
NAMESPACE="openshift-logging"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=logging-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep cluster-logging-operator | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all $pod_name pods are in 'running' state]"
        break
    fi
done

# Wait for loki-operator pods to be in 'Running' state
NAMESPACE="openshift-operators-redhat"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=loki-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep loki-operator | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "2/2 Running" state
    if echo "$output" | grep -vq "2/2 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all $pod_name pods are in 'running' state]"
        break
    fi
done

# Wait for observability-operator pods to be in 'Running' state
NAMESPACE="openshift-cluster-observability-operator"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=observability-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep -v Completed | awk '{print $3}' || true)
    
    # Check if any pod is not in the "Running" state
    if echo "$output" | grep -vq "Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all $pod_name pods are in 'running' state]"
        break
    fi
done


# create object storage secret credentials
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: ${BUCKET_NAME}-credentials
  namespace: openshift-logging
stringData:
  access_key_id: ${ACCESS_KEY_ID}
  access_key_secret: ${ACCESS_KEY_SECRET}
  bucketnames: ${BUCKET_NAME}
  endpoint: ${BUCKET_HOST}
  region: minio
EOF
run_command "[create object storage secret credentials]"

sleep 5

# Create loki stack instance
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  size: 1x.demo
  storage:
    schemas:
    - effectiveDate: '2024-10-01'
      version: v13
    secret:
      name: ${BUCKET_NAME}-credentials
      type: s3
  storageClassName: ${STORAGE_CLASS_NAME}
  tenants:
    mode: openshift-logging
EOF
run_command "[create loki stack instance]"

sleep 25

# Wait for openshift-logging pods to be in 'Running' state
NAMESPACE="openshift-logging"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=observability-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep -v Completed | awk '{print $3}' || true)

    # Check if any pod is not in the "Running" state
    if echo "$output" | grep -vq "Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all $pod_name pods are in 'running' state]"
        break
    fi
done

oc project openshift-logging >/dev/null 2>&1

oc create sa collector -n openshift-logging >/dev/null 2>&1
run_command "[create a service account for the collector]"

oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z collector >/dev/null 2>&1
run_command "[allow the collector’s service account to write data to the lokistack cr]"

oc adm policy add-cluster-role-to-user collect-application-logs -z collector >/dev/null 2>&1
run_command "[allow the collector’s service account to collect app logs]"

oc adm policy add-cluster-role-to-user collect-audit-logs -z collector >/dev/null 2>&1
run_command "[allow the collector’s service account to collect audit logs]"

oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z collector >/dev/null 2>&1
run_command "[allow the collector’s service account to collect infra logs]"

# Creating CLF CR and UIPlugin
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
EOF
run_command "[creating uiplugin resources]"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  serviceAccount:
    name: collector
  outputs:
  - name: default-lokistack
    type: lokiStack
    lokiStack:
      authentication:
        token:
          from: serviceAccount
      target:
        name: logging-loki
        namespace: openshift-logging
    tls:
      ca:
        key: service-ca.crt
        configMapName: openshift-service-ca.crt
  pipelines:
  - name: default-logstore
    inputRefs:
    - application
    - infrastructure
    outputRefs:
    - default-lokistack
EOF
run_command "[creating cluster log forwarder resources]"

sleep 25

# Wait for openshift-logging pods to be in 'Running' state
NAMESPACE="openshift-logging"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=observability-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep -v Completed | awk '{print $3}' || true)

    # Check if any pod is not in the "Running" state
    if echo "$output" | grep -vq "Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all $pod_name pods are in 'running' state]"
        break
    fi
done

# Add an empty line after the task
echo
