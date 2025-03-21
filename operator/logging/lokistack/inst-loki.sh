#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export CHANNEL_NAME="stable-6.1"
export STORAGE_CLASS_NAME="managed-nfs-storage"
export STORAGE_SIZE="50Gi"
export CATALOG_SOURCE_NAME=redhat-operators

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
PRINT_TASK "TASK [Uninstall old logging resources...]"

# Uninstall first
echo "info: [uninstall old logging resources...]"
oc delete -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/lokistack/04-clf-ui.yaml >/dev/null 2>&1 || true
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/lokistack/03-loki-stack-v6.yaml | envsubst | oc delete -f - >/dev/null 2>&1 || true
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/lokistack/02-config.yaml | envsubst | oc delete -f - >/dev/null 2>&1 || true

oc delete sub loki-operator -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete sub cluster-logging -n openshift-operators >/dev/null 2>&1 || true
oc delete sub cluster-observability-operator -n openshift-operators >/dev/null 2>&1 || true

oc get csv -n openshift-operators-redhat -o name | grep loki-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get csv -n openshift-logging -o name | grep cluster-logging | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-logging >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep cluster-observability-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true

oc delete ns openshift-operators-redhat >/dev/null 2>&1 || true
oc delete ns openshift-logging >/dev/null 2>&1 || true

# Deploy Minio with the specified YAML template
oc delete ns minio >/dev/null 2>&1 || true

sleep 20

# Step 1:
PRINT_TASK "TASK [Deploying Minio Object Storage]"

sudo curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f - >/dev/null 2>&1
run_command "[deploying minio object storage]"

# Wait for Minio pods to be in 'Running' state
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n minio --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [minio pods are in 'running' state]"
        break
    fi
done

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
run_command "[retrieved minio route host: $BUCKET_HOST]"

sleep 20

# Set Minio client alias
oc rsh -n minio deployments/minio mc alias set my-minio ${BUCKET_HOST} minioadmin minioadmin >/dev/null 2>&1
run_command "[configured minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
oc rsh -n minio deployments/minio mc --no-color mb my-minio/loki-bucket >/dev/null 2>&1
run_command "[created bucket loki-bucket]"

# Print Minio address and credentials
echo "info: [minio address: $BUCKET_HOST]"
echo "info: [minio default id/pw: minioadmin/minioadmin]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "[TASK: Install OpenShift Logging]"

# Create a namespace
cat << EOF | oc apply -f - >/dev/null 2>&1
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
  name: openshift-logging
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
EOF
run_command "[create a openshift-logging namespace]"

# Create a OperatorGroup
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
  channel: ${CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: loki-operator
  source: $CATALOG_SOURCE_NAME
  sourceNamespace: openshift-marketplace
EOF
run_command "[create a loki operator]"

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
  channel: ${CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: cluster-logging
  source: $CATALOG_SOURCE_NAME
  sourceNamespace: openshift-marketplace
EOF
run_command "[create a cluster-logging operator]"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-operators
spec:
  channel: development
  installPlanApproval: "Manual"
  name: cluster-observability-operator
  source: $CATALOG_SOURCE_NAME
  sourceNamespace: openshift-marketplace
EOF
run_command "[create a cluster observability operator]"

# Approval IP
export NAMESPACE="openshift-logging"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve cluster-logging install plan]"

export NAMESPACE="openshift-operators-redhat"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve loki-operator install plan]"

export NAMESPACE="openshift-operators"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve cluster-observability-operator install plan]"

sleep 30

# Create Object Storage secret credentials
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
export ACCESS_KEY_ID="minioadmin"
export ACCESS_KEY_SECRET="minioadmin"
export BUCKET_NAME="loki-bucket"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/lokistack/02-config.yaml | envsubst | oc create -f - >/dev/null 2>&1
run_command "[create object storage secret credentials]"

# Create loki stack
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/lokistack/03-loki-stack-v6.yaml | envsubst | oc create -f - >/dev/null 2>&1
run_command "[create loki stack instance]"

sleep 30

# Wait for openshift-logging pods to be in 'Running' state
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n openshift-logging --no-headers |grep -v Completed | awk '{print $3}')
    
    # Check if any pod is not in the "Running" state
    if echo "$output" | grep -vq "Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 10
    else
        # Close the progress indicator if it was started
        if $progress_started; then
            echo "]"
        fi

        echo "ok: [all openshift-logging pods are in 'running' state]"
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
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/lokistack/04-clf-ui.yaml >/dev/null 2>&1
run_command "[creating clf cr and uiplugin]"

sleep 30

# Wait for openshift-logging pods to be in 'Running' state
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n openshift-logging --no-headers |grep -v Completed | awk '{print $3}')
    
    # Check if any pod is not in the "Running" state
    if echo "$output" | grep -vq "Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 10
    else
        # Close the progress indicator if it was started
        if $progress_started; then
            echo "]"
        fi

        echo "ok: [all openshift-logging pods are in 'running' state]"
        break
    fi
done
