#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export COLLECTOR="fluentd"
#export COLLECTOR="vector"
export LOGGING_SUB_CHANNEL="stable"
export ES_SUB_CHANNEL="stable"
export CATALOG_SOURCE=redhat-operators
export STORAGE_CLASS="managed-nfs-storage"


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


# Step 1:
PRINT_TASK "TASK [Deploying Minio Object Storage]"

# Delete custom resources
if oc get clusterLogging instance -n openshift-logging >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting clusterLogging instance..."
    oc delete clusterLogging instance -n openshift-logging >/dev/null 2>&1 || true
else
    echo -e "\e[96mINFO\e[0m clusterLogging does not exist"
fi

oc delete sub elasticsearch-operator -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete sub cluster-logging -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators-redhat -o name | grep elasticsearch-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get csv -n openshift-logging -o name | grep cluster-logging | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-logging >/dev/null 2>&1 || true

if oc get ns openshift-operators-redhat >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting logging and elasticsearch operator..."
   echo -e "\e[96mINFO\e[0m Deleting openshift-operators-redhat project..."
   oc delete ns openshift-operators-redhat >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The openshift-operators-redhat project does not exist"
fi

if oc get ns openshift-logging >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting openshift-logging project..."
   oc delete ns openshift-logging >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The openshift-logging project does not exist"
fi

# Add an empty line after the task
echo

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
run_command "Create a openshift-operators-redhat namespace"

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
  channel: ${ES_SUB_CHANNEL}
  installPlanApproval: "Manual"
  source: ${CATALOG_SOURCE}
  sourceNamespace: "openshift-marketplace"
  name: "elasticsearch-operator"

EOF
run_command "Create a elasticsearch operator"

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
run_command "Create a cluster-logging operator"

# Approval IP
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
export OPERATOR_NS="openshift-logging"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the cluster-logging install plan"

export OPERATOR_NS="openshift-operators-redhat"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the elasticsearch-operator install plan"

sleep 30

if [ "$COLLECTOR" == "fluentd" ]; then
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-fluentd.yaml | envsubst | oc apply -f - >/dev/null 2>&1
elif [ "$COLLECTOR" == "vector" ]; then
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-vector.yaml | envsubst | oc apply -f - >/dev/null 2>&1
else
  echo -e "\e[96mINFO\e[0m Invalid collector type specified"
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
            echo -n -e "\e[96mINFO\e[0m waiting for pods to be in 'running' state"
            progress_started=true  # Prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 10
    else
        # Close the progress indicator if it was started
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi

        echo -e "\e[96mINFO\e[0m all openshift-logging pods are in 'running' state"
        break
    fi
done
