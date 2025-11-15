#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export COLLECTOR="fluentd"
#export COLLECTOR="vector"
export SUB_CHANNEL="stable"
export CATALOG_SOURCE=redhat-operators
export STORAGE_CLASS_NAME="managed-nfs-storage"


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

# Uninstall first
echo "info: [uninstall old rhsso resources...]"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-fluentd.yaml | envsubst | oc delete -f - >/dev/null 2>&1 || true
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-vector.yaml | envsubst | oc delete -f - >/dev/null 2>&1 || true

oc delete sub elasticsearch-operator -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete sub cluster-logging -n openshift-operators >/dev/null 2>&1 || true

oc get csv -n openshift-operators-redhat -o name | grep elasticsearch-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get csv -n openshift-logging -o name | grep cluster-logging | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-logging >/dev/null 2>&1 || true

oc delete ns openshift-operators-redhat >/dev/null 2>&1 || true
oc delete ns openshift-logging >/dev/null 2>&1 || true


# Step 1:
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
  name: "elasticsearch-operator"
  namespace: "openshift-operators-redhat" 
spec:
  channel: ${SUB_CHANNEL}
  installPlanApproval: "Manual"
  source: ${CATALOG_SOURCE}
  sourceNamespace: "openshift-marketplace"
  name: "elasticsearch-operator"

EOF
run_command "[create a elasticsearch operator]"

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
  channel: ${SUB_CHANNEL}
  installPlanApproval: "Manual"
  name: cluster-logging
  source: $CATALOG_SOURCE
  sourceNamespace: openshift-marketplace
EOF
run_command "[create a cluster-logging operator]"

# Approval IP
export OPERATOR_NS="openshift-logging"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve cluster-logging install plan]"

export OPERATOR_NS="openshift-operators-redhat"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve elasticsearch-operator install plan]"

sleep 30

if [ "$COLLECTOR" == "fluentd" ]; then
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-fluentd.yaml | envsubst | oc apply -f - >/dev/null 2>&1
elif [ "$COLLECTOR" == "vector" ]; then
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-vector.yaml | envsubst | oc apply -f - >/dev/null 2>&1
else
  echo "Invalid collector type specified"
fi

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
