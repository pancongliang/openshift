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


# Step 0:
PRINT_TASK "TASK [Delete old logging resources]"

# Delete custom resources
if oc get clusterLogging instance -n openshift-logging >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting clusterLogging instance..."
    oc delete clusterLogging instance -n openshift-logging >/dev/null 2>&1 || true
    echo -e "\e[96mINFO\e[0m Deleting logging and elasticsearch operator..."
else
    echo -e "\e[96mINFO\e[0m ClusterLogging does not exist"
fi

oc delete sub elasticsearch-operator -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete sub cluster-logging -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators-redhat -o name | grep elasticsearch-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get csv -n openshift-logging -o name | grep cluster-logging | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-logging >/dev/null 2>&1 || true

oc get ip -n openshift-operators-redhat  --no-headers 2>/dev/null|grep elasticsearch-operator|awk '{print $1}'|xargs -r oc delete ip -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get ip -n openshift-logging --no-headers 2>/dev/null|grep cluster-logging|awk '{print $1}'|xargs -r oc delete ip -n openshift-logging >/dev/null 2>&1 || true

if oc get ns openshift-logging >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Delete openshift-logging project..."
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
run_command "Install the elasticsearch operator"

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
run_command "Install the cluster-logging operator"

# Approval IP
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
export OPERATOR_NS="openshift-logging"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the cluster-logging install plan"

export OPERATOR_NS="openshift-operators-redhat"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the elasticsearch-operator install plan"

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=150    # Maximum number of retries
SLEEP_INTERVAL=2   # Sleep interval in seconds
LINE_WIDTH=120     # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
project=openshift-logging
pod_name=cluster-logging-operator

while true; do
    # Get the status of all pods in the pod_name project
    PODS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$PODS" | awk -F/ '$1 != $2')

    if [[ -z "$not_ready" ]]; then
        # All pods are ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
        fi
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit if maximum retries reached
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
            exit 1
        fi
    fi
done

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=150    # Maximum number of retries
SLEEP_INTERVAL=2   # Sleep interval in seconds
LINE_WIDTH=120     # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
project=openshift-operators-redhat
pod_name=elasticsearch-operator

while true; do
    # Get the status of all pods in the pod_name project
    PODS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$PODS" | awk -F/ '$1 != $2')

    if [[ -z "$not_ready" ]]; then
        # All pods are ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
        fi
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit if maximum retries reached
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
            exit 1
        fi
    fi
done

sleep 10

if [ "$COLLECTOR" == "fluentd" ]; then
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-fluentd.yaml | envsubst | oc apply -f - >/dev/null 2>&1
elif [ "$COLLECTOR" == "vector" ]; then
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-vector.yaml | envsubst | oc apply -f - >/dev/null 2>&1
else
  echo -e "\e[96mINFO\e[0m Invalid collector type specified"
fi

sleep 30

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150    # Maximum number of retries
SLEEP_INTERVAL=2   # Sleep interval in seconds
LINE_WIDTH=120    # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
namespace=openshift-logging

while true; do
    # Get READY column of all pods that are not Completed
    PODS=$(oc -n "$namespace" get po --no-headers 2>/dev/null | grep -v Completed | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$PODS" | awk -F/ '$1 != $2')

    if [[ -z "$not_ready" ]]; then
        # All pods are ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                   "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
        else
            echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
        fi
        break
    else
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for %s namespace pods to be Running... %s" "$namespace" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for %s namespace pods to be Running... %s" "$namespace" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit if maximum retries reached
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
                   "$namespace" $((LINE_WIDTH - ${#namespace} - 31)) ""
            exit 1
        fi
    fi
done

echo -e "\e[96mINFO\e[0m Installation complete"

# Add an empty line after the task
echo
