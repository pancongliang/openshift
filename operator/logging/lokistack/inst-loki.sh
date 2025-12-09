#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export LOGGING_SUB_CHANNEL="stable-6.1"
export LOKI_SUB_CHANNEL="stable-6.1"
export OBSERVABILITY_SUB_CHANNEL="stable"
export STORAGE_CLASS="managed-nfs-storage"
export STORAGE_SIZE="50Gi"
export CATALOG_SOURCE=redhat-operators

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
PRINT_TASK "TASK [Delete old logging resources]"

# Uninstall first
if oc get uiplugin logging >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting uiplugin resource..."
   oc delete uiplugin logging >/dev/null 2>&1
else
   echo -e "\e[96mINFO\e[0m The uiplugin resource does not exist"
fi

if oc get clusterlogforwarder.observability instance -n openshift-logging >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting clusterlogforwarder.observability..."
   oc delete clusterlogforwarder.observability instance -n openshift-logging >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The clusterlogforwarder.observability resource does not exist"
fi

if oc get clokistack logging-loki -n openshift-logging >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting lokistack..."
   oc delete lokistack logging-loki -n openshift-logging >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The lokistack resource does not exist"
fi

echo -e "\e[96mINFO\e[0m Deleting operator..."
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

if oc get ns openshift-logging >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting openshift-logging project..."
   oc delete ns openshift-logging >/dev/null 2>&1
else
   echo -e "\e[96mINFO\e[0m The openshift-logging project does not exist"
fi

if oc get ns openshift-cluster-observability-operator >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting openshift-cluster-observability-operator project..."
   oc delete ns openshift-cluster-observability-operator >/dev/null 2>&1
else
   echo -e "\e[96mINFO\e[0m The openshift-cluster-observability-operator project does not exist"
fi

# Add an empty line after the task
echo

# Step 1:
# Deploying Minio Object Storage
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/minio/inst-minio.sh |sh

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
run_command "Create a openshift-logging namespace"

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
run_command "Create a openshift-operators-redhat namespace"

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
run_command "Create a openshift cluster-observability-operator namespace"

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
  channel: ${LOGGING_SUB_CHANNEL}
  installPlanApproval: "Manual"
  name: cluster-logging
  source: $CATALOG_SOURCE
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the cluster logging operator"

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
  channel: ${LOKI_SUB_CHANNEL}
  installPlanApproval: "Manual"
  name: loki-operator
  source: $CATALOG_SOURCE
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the loki operator"

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
  channel: ${OBSERVABILITY_SUB_CHANNEL}
  installPlanApproval: "Manual"
  name: cluster-observability-operator
  source: $CATALOG_SOURCE
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the cluster-observability-operator"

# Approval IP
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
export OPERATOR_NS="openshift-logging"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the cluster-logging-operator install plan"

export OPERATOR_NS="openshift-operators-redhat"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the loki-operator install plan"

sleep 10
export OPERATOR_NS="openshift-cluster-observability-operator"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the cluster-observability-operator install plan"

sleep 15

# Wait for logging-operator pods to be in 'Running' state
NAMESPACE="openshift-logging"
MAX_RETRIES=60
SLEEP_INTERVAL=5
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
            echo -n -e "\e[96mINFO\e[0m waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries $pod_name pods may still be initializing"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m The $pod_name pods are in the Running state"
        break
    fi
done

# Wait for loki-operator pods to be in 'Running' state
NAMESPACE="openshift-operators-redhat"
MAX_RETRIES=60
SLEEP_INTERVAL=5
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
            echo -n -e "\e[96mINFO\e[0m Waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries $pod_name pods may still be initializing"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m The $pod_name pods are in the Running state"
        break
    fi
done

# Wait for observability-operator pods to be in 'Running' state
NAMESPACE="openshift-cluster-observability-operator"
MAX_RETRIES=60
SLEEP_INTERVAL=10
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
            echo -n -e "\e[96mINFO\e[0m Waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries $pod_name pods may still be initializing"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m The $pod_name pods are in the Running state"
        break
    fi
done

# create object storage secret credentials
export MINIO_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
export ACCESS_KEY_ID="minioadmin"
export ACCESS_KEY_SECRET="minioadmin"
export BUCKET_NAME="quay-bucket"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: logging-loki-s3
  namespace: openshift-logging
stringData:
  access_key_id: ${ACCESS_KEY_ID}
  access_key_secret: ${ACCESS_KEY_SECRET}
  bucketnames: ${BUCKET_NAME}
  endpoint: ${MINIO_HOST}
  region: minio
EOF
run_command "Create object storage secret credentials"

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
      name: logging-loki-s3
      type: s3
  storageClassName: ${STORAGE_CLASS}
  tenants:
    mode: openshift-logging
EOF
run_command "Create loki stack instance"

sleep 25

# Wait for openshift-logging pods to be in 'Running' state
NAMESPACE="openshift-logging"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep -v Completed | awk '{print $3}' || true)

    # Check if any pod is not in the "Running" state
    if echo "$output" | grep -vq "Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for openshift-logging pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries openshift-logging pods may still be initializing"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m All openshift-logging pods are in the Running state"
        break
    fi
done

oc create sa logging-collector -n openshift-logging >/dev/null 2>&1
run_command "Create a service account to be used by the log collector"

oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z logging-collector -n openshift-logging >/dev/null 2>&1
run_command "Allow the collector’s service account to write data to the lokistack cr"

oc adm policy add-cluster-role-to-user collect-application-logs -z logging-collector -n openshift-logging >/dev/null 2>&1
run_command "Allow the collector’s service account to collect app logs]"

oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z collect-audit-logs -n openshift-logging >/dev/null 2>&1
run_command "Allow the collector’s service account to collect audit logs"

oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z logging-collector -n openshift-logging >/dev/null 2>&1
run_command "Allow the collector’s service account to collect infra logs"

# Creating CLF CR and UIPlugin
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  serviceAccount:
    name: logging-collector
  outputs:
  - name: lokistack-out
    type: lokiStack
    lokiStack:
      target:
        name: logging-loki
        namespace: openshift-logging
      authentication:
        token:
          from: serviceAccount
    tls:
      ca:
        key: service-ca.crt
        configMapName: openshift-service-ca.crt
  pipelines:
  - name: infra-app-logs
    inputRefs:
    - application
    - infrastructure
    outputRefs:
    - lokistack-out
EOF
run_command "Create a ClusterLogForwarder resources"

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
    logsLimit: 50
    timeout: 30s
    schema: otel
EOF
run_command "Install the logging UI plugin"

sleep 25

# Wait for openshift-logging pods to be in 'Running' state
NAMESPACE="openshift-logging"
MAX_RETRIES=60
SLEEP_INTERVAL=5
progress_started=false
retry_count=0

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep -v Completed | awk '{print $3}' || true)

    # Check if any pod is not in the "Running" state
    if echo "$output" | grep -vq "Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for openshift-logging pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries openshift-logging pods may still be initializing"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m All openshift-logging pods are in the Running state"
        break
    fi
done

echo -e "\e[96mINFO\e[0m Installation complete"

# Add an empty line after the task
echo
