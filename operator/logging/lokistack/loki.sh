#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# LokiStack environment variables
export STORAGE_SIZE="50Gi"
export LOKI_SIZING="1x.demo"                     # 1x.demo / 1x.pico [6.1+ only]/ 1x.extra-small / 1x.small / 1x.medium

# Operator environment variables
export LOGGING_SUB_CHANNEL="stable-6.2"
export LOKI_SUB_CHANNEL="stable-6.2"
export OBSERVABILITY_SUB_CHANNEL="stable"
export CATALOG_SOURCE="redhat-operators"

# Option 1:  If ODF is not installed, automatically create MinIO (default StorageClass required).
export DEFAULT_STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

# Option 2:  If ODF is installed, create the OBC and credentials.
export ODF_CREATE_OBC_AND_CREDENTIALS="true"                 # If there is MCG/ODF object storage: true, otherwise false
export OBC_STORAGECLASS_S3="openshift-storage.noobaa.io"     # openshift-storage.noobaa.io or ocs-storagecluster-ceph-rgw
export ODF_STORAGECLASS="ocs-storagecluster-ceph-rbd"        # ocs-storagecluster-ceph-rbd or ocs-storagecluster-cephfs
export OBC_NAMESPACE="openshift-logging" 
export OBC_NAME="loki"

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
oc delete sub loki-operator -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete sub cluster-logging -n openshift-operators >/dev/null 2>&1 || true
oc delete sub cluster-observability-operator -n openshift-cluster-observability-operator >/dev/null 2>&1 || true

oc get csv -n openshift-operators-redhat -o name | grep loki-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get csv -n openshift-logging -o name | grep cluster-logging | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-logging >/dev/null 2>&1 || true
oc get csv -n openshift-cluster-observability-operator -o name | grep cluster-observability-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-cluster-observability-operator >/dev/null 2>&1 || true

oc get ip -n openshift-operators-redhat  --no-headers 2>/dev/null|grep loki-operator|awk '{print $1}'|xargs -r oc delete ip -n openshift-operators-redhat >/dev/null 2>&1 || true
oc get ip -n openshift-logging --no-headers 2>/dev/null|grep cluster-logging|awk '{print $1}'|xargs -r oc delete ip -n openshift-logging >/dev/null 2>&1 || true
oc get ip -n openshift-cluster-observability-operator  --no-headers 2>/dev/null|grep observability|awk '{print $1}'|xargs -r oc delete ip -n openshift-cluster-observability-operator >/dev/null 2>&1 || true

oc delete operatorgroups --all -n openshift-operators-redhat >/dev/null 2>&1 || true
oc delete operatorgroups cluster-observability-operator -n cluster-observability-operator >/dev/null 2>&1 || true
oc delete operatorgroups cluster-logging -n openshift-logging >/dev/null 2>&1 || true

timeout 2s oc delete pvc --all -n openshift-logging >/dev/null 2>&1 || true 

timeout 2s oc delete secret loki-bucket-credentials -n openshift-logging >/dev/null 2>&1 || true
oc patch secret loki-bucket-credentials -n openshift-logging -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete secret loki -n openshift-logging >/dev/null 2>&1 || true
oc patch secret loki -n openshift-logging -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete objectbucket obc-${OBC_NAMESPACE}-${OBC_NAME} -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch objectbucket obc-${OBC_NAMESPACE}-${OBC_NAME} -n ${OBC_NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete objectbucketclaim ${OBC_NAME} -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch objectbucketclaim ${OBC_NAME} -n ${OBC_NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

timeout 2s oc delete cm ${OBC_NAME} -n ${OBC_NAMESPACE} >/dev/null 2>&1 || true
oc patch cm ${OBC_NAME} -n ${OBC_NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true

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
# If ODF does not exist, a default StorageClass is required (for MinIO).
if [ "$ODF_CREATE_OBC_AND_CREDENTIALS" = "false" ]; then
    DEFAULT_STORAGE_CLASS=$(oc get sc \
      -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

    if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
        PRINT_TASK "TASK [Check the default storage class]"
        echo -e "\e[31mFAILED\e[0m No default StorageClass found!"
        exit 1
    else
        PRINT_TASK "TASK [Check the default storage class]"
        echo -e "\e[96mINFO\e[0m Default StorageClass found: $DEFAULT_STORAGE_CLASS"
        # Add an empty line after the task
        echo
    fi
fi

# Step 2:
# Deploying Object Storage
# Only run this block if ODF_CREATE_OBC_AND_CREDENTIALS is false
if [[ "$ODF_CREATE_OBC_AND_CREDENTIALS" == "false" ]]; then

    # Check if the MinIO Pod exists and is running
    MINIO_POD=$(oc get pod -n "minio" -l app=minio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -n "$MINIO_POD" ]]; then
        POD_STATUS=$(oc get pod "$MINIO_POD" -n "minio" -o jsonpath='{.status.phase}')
    else
        POD_STATUS=""
    fi

    # Check if the bucket exists
    export BUCKET_NAME="loki-bucket"
    export MINIO_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}' 2>/dev/null)

    BUCKET_EXISTS=false
    if [[ -n "$MINIO_POD" ]] && [[ "$POD_STATUS" == "Running" ]]; then
        oc exec -n "minio" "$MINIO_POD" -- mc alias set my-minio "${MINIO_HOST}" minioadmin minioadmin >/dev/null 2>&1 || true
        if oc exec -n "minio" "$MINIO_POD" -- mc ls my-minio 2>/dev/null | grep -q "$BUCKET_NAME"; then
           BUCKET_EXISTS=true
        fi
    fi

    # Deploy MinIO if necessary
    if [[ -n "$MINIO_POD" ]] && [[ "$POD_STATUS" == "Running" ]] && [[ "$BUCKET_EXISTS" == true ]]; then
        PRINT_TASK "TASK [Deploying Minio Object Storage]"
        echo -e "\e[96mINFO\e[0m MinIO already exists and bucket exists, skipping deployment"
    else
        curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/minio/minio.sh | sh
    fi

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

    # Create object storage secret credentials
    export ACCESS_KEY_ID="minioadmin"
    export ACCESS_KEY_SECRET="minioadmin"
    export BUCKET_NAME="loki-bucket"
    export MINIO_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}' 2>/dev/null)
    cat <<EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: ${BUCKET_NAME}-minio-credentials
  namespace: openshift-logging
stringData:
  access_key_id: ${ACCESS_KEY_ID}
  access_key_secret: ${ACCESS_KEY_SECRET}
  bucketnames: ${BUCKET_NAME}
  endpoint: ${MINIO_HOST}
  region: minio
EOF
    run_command "Create object storage secret ${BUCKET_NAME}-minio-credentials in openshift-logging namespace"
fi

# Only run this block if ODF_CREATE_OBC_AND_CREDENTIALS is true
export OBC_NAMESPACE="openshift-logging" 
export OBC_NAME="loki"

if [[ "$ODF_CREATE_OBC_AND_CREDENTIALS" == "true" ]]; then
    PRINT_TASK "TASK [Create ObjectBucketClaim and object storage credentials]"
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
    
    # Create ObjectBucketClaim
    cat <<EOF | oc apply -f - >/dev/null 2>&1
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  finalizers:
  - objectbucket.io/finalizer
  labels:
    app: noobaa
    bucket-provisioner: openshift-storage.noobaa.io-obc
    noobaa-domain: openshift-storage.noobaa.io
  name: ${OBC_NAME}
  namespace: ${OBC_NAMESPACE}
spec:
  additionalConfig:
    bucketclass: noobaa-default-bucket-class
  generateBucketName: ${OBC_NAME}
  objectBucketName: obc-${OBC_NAMESPACE}-${OBC_NAME}
  storageClassName: ${OBC_STORAGECLASS_S3}
EOF
    run_command "Create an ObjectBucketClaim named ${OBC_NAME} in ${OBC_NAMESPACE} namespace"

    # Wait for ConfigMap to exist
    MAX_RETRIES=180
    SLEEP_INTERVAL=5
    SPINNER=('/' '-' '\' '|')
    retry_count=0
    progress_started=false
    CONFIGMAP_NAME=${OBC_NAME}
    NAMESPACE=${OBC_NAMESPACE}

    while true; do
        configmap_exists=$(oc get configmap -n "$NAMESPACE" "$CONFIGMAP_NAME" --no-headers 2>/dev/null || true)
        CHAR=${SPINNER[$((retry_count % 4))]}

        if [[ -n "$configmap_exists" ]]; then
            printf "\r"; tput el
            echo -e "\e[96mINFO\e[0m The configmap '$CONFIGMAP_NAME' has been created"
            break
        else
            printf "\r\e[96mINFO\e[0m Waiting for configmap '%s' %s" "$CONFIGMAP_NAME" "$CHAR"
            tput el
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r"; tput el
            echo -e "\e[31mFAILED\e[0m Reached max retries, configmap '$CONFIGMAP_NAME' not created"
            exit 1
        fi
    done

    # Extract bucket info from ConfigMap
    export BUCKET_HOST=$(oc get -n ${OBC_NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
    export BUCKET_NAME=$(oc get -n ${OBC_NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
    export BUCKET_PORT=$(oc get -n ${OBC_NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')

    # Extract access credentials from Secret
    export ACCESS_KEY_ID=$(oc get -n ${OBC_NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
    export ACCESS_KEY_SECRET=$(oc get -n ${OBC_NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

    # Create Kubernetes Secret for Object Storage
    cat <<EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: ${OBC_NAME}-obc-credentials
  namespace: ${OBC_NAMESPACE}
stringData:
  access_key_id: ${ACCESS_KEY_ID}
  access_key_secret: ${ACCESS_KEY_SECRET}
  bucketnames: ${BUCKET_NAME}
  endpoint: "https://${BUCKET_HOST}:${BUCKET_PORT}"
  region: minio
EOF
    run_command "Create object storage secret ${OBC_NAME}-obc-credentials in ${OBC_NAMESPACE} namespace"
fi

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Install OpenShift Logging]"

# Install OpenShift Logging
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

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=openshift-logging

MSG="Waiting for unapproved install plans in namespace $OPERATOR_NS"
while true; do
    # Get unapproved InstallPlans
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)

    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true

        # Overwrite previous INFO line with final approved message
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace has no unapproved install plans%*s\n" \
               "$OPERATOR_NS" $((LINE_WIDTH - ${#OPERATOR_NS} - 45)) ""
        break
    fi
done

sleep 5

# Stage 2: Quickly approve all remaining unapproved InstallPlans
while true; do
    # Get all unapproved InstallPlans; if none exist, exit the loop
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)
    if [[ -z "$INSTALLPLAN" ]]; then
        break
    fi
    # Loop through and approve each InstallPlan
    for NAME in $INSTALLPLAN; do
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
    done
    # Slight delay to avoid excessive polling
    sleep 3
done

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=openshift-operators-redhat

MSG="Waiting for unapproved install plans in namespace $OPERATOR_NS"
while true; do
    # Get unapproved InstallPlans
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)

    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true

        # Overwrite previous INFO line with final approved message
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace has no unapproved install plans%*s\n" \
               "$OPERATOR_NS" $((LINE_WIDTH - ${#OPERATOR_NS} - 45)) ""
        break
    fi
done

sleep 5

# Stage 2: Quickly approve all remaining unapproved InstallPlans
while true; do
    # Get all unapproved InstallPlans; if none exist, exit the loop
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)
    if [[ -z "$INSTALLPLAN" ]]; then
        break
    fi
    # Loop through and approve each InstallPlan
    for NAME in $INSTALLPLAN; do
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
    done
    # Slight delay to avoid excessive polling
    sleep 3
done

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=openshift-cluster-observability-operator

MSG="Waiting for unapproved install plans in namespace $OPERATOR_NS"
while true; do
    # Get unapproved InstallPlans
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)

    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true

        # Overwrite previous INFO line with final approved message
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace has no unapproved install plans%*s\n" \
               "$OPERATOR_NS" $((LINE_WIDTH - ${#OPERATOR_NS} - 45)) ""
        break
    fi
done

sleep 5

# Stage 2: Quickly approve all remaining unapproved InstallPlans
while true; do
    # Get all unapproved InstallPlans; if none exist, exit the loop
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)
    if [[ -z "$INSTALLPLAN" ]]; then
        break
    fi
    # Loop through and approve each InstallPlan
    for NAME in $INSTALLPLAN; do
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
    done
    # Slight delay to avoid excessive polling
    sleep 3
done

sleep 15

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=openshift-logging
pod_name=cluster-logging-operator

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

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=openshift-operators-redhat
pod_name=loki-operator

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

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=300              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=openshift-cluster-observability-operator

while true; do
    # 1. Get the READY column for all pods, excluding Completed ones
    POD_STATUS_LIST=$(oc -n "$namespace" get po --no-headers 2>/dev/null | grep -v "Completed" | awk '{print $2}' || true)

    # 2. Check if any pods exist and if they are all ready
    if [[ -n "$POD_STATUS_LIST" ]]; then
        # Check for pods where Ready count (left) is not equal to Total count (right)
        not_ready_exists=$(echo "$POD_STATUS_LIST" | awk -F/ '$1 != $2')
        
        if [[ -z "$not_ready_exists" ]]; then
            # SUCCESS: Pods exist AND all of them are ready
            if $progress_started; then
                printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                       "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
            else
                echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
            fi
            break
        fi
    fi

    # 3. If we reach here, either no pods exist yet or some are not ready
    CHAR=${SPINNER[$((retry_count % 4))]}
    
    # Define feedback message based on whether pods are missing or starting
    MSG="Waiting for $namespace namespace pods to be Running..."
    [[ -z "$POD_STATUS_LIST" ]] && MSG="Waiting for $namespace pods to be created..."

    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # 4. Handle timeout and retry
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 45)) ""
        exit 1
    fi
done

sleep 5

# Create loki stack instance
if [[ "$ODF_CREATE_OBC_AND_CREDENTIALS" == "false" ]]; then
    # MinIO (HTTP, no TLS)
    cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  size: ${LOKI_SIZING}
  storage:
    schemas:
    - effectiveDate: '2024-10-01'
      version: v13
    secret:
      name: ${BUCKET_NAME}-minio-credentials
      type: s3
  storageClassName: ${DEFAULT_STORAGE_CLASS}
  tenants:
    mode: openshift-logging
EOF

    run_command "Create LokiStack instance (MinIO)"

else
    # ODF / NooBaa (HTTPS + Service CA)
    cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  size: ${LOKI_SIZING}
  storage:
    schemas:
    - effectiveDate: '2024-10-01'
      version: v13
    secret:
      name: ${OBC_NAME}-obc-credentials
      type: s3
    tls:
      caName: openshift-service-ca.crt
  storageClassName: ${ODF_STORAGECLASS}
  tenants:
    mode: openshift-logging
EOF
    run_command "Create LokiStack instance"
fi


sleep 25

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=openshift-logging

while true; do
    # 1. Get the READY column for all pods, excluding Completed ones
    POD_STATUS_LIST=$(oc -n "$namespace" get po --no-headers 2>/dev/null | grep -v "Completed" | awk '{print $2}' || true)

    # 2. Check if any pods exist and if they are all ready
    if [[ -n "$POD_STATUS_LIST" ]]; then
        # Check for pods where Ready count (left) is not equal to Total count (right)
        not_ready_exists=$(echo "$POD_STATUS_LIST" | awk -F/ '$1 != $2')
        
        if [[ -z "$not_ready_exists" ]]; then
            # SUCCESS: Pods exist AND all of them are ready
            if $progress_started; then
                printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                       "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
            else
                echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
            fi
            break
        fi
    fi

    # 3. If we reach here, either no pods exist yet or some are not ready
    CHAR=${SPINNER[$((retry_count % 4))]}
    
    # Define feedback message based on whether pods are missing or starting
    MSG="Waiting for $namespace namespace pods to be Running..."
    [[ -z "$POD_STATUS_LIST" ]] && MSG="Waiting for $namespace pods to be created..."

    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # 4. Handle timeout and retry
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 45)) ""
        exit 1
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

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=openshift-logging

while true; do
    # 1. Get the READY column for all pods, excluding Completed ones
    POD_STATUS_LIST=$(oc -n "$namespace" get po --no-headers 2>/dev/null | grep -v "Completed" | awk '{print $2}' || true)

    # 2. Check if any pods exist and if they are all ready
    if [[ -n "$POD_STATUS_LIST" ]]; then
        # Check for pods where Ready count (left) is not equal to Total count (right)
        not_ready_exists=$(echo "$POD_STATUS_LIST" | awk -F/ '$1 != $2')
        
        if [[ -z "$not_ready_exists" ]]; then
            # SUCCESS: Pods exist AND all of them are ready
            if $progress_started; then
                printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                       "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
            else
                echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
            fi
            break
        fi
    fi

    # 3. If we reach here, either no pods exist yet or some are not ready
    CHAR=${SPINNER[$((retry_count % 4))]}
    
    # Define feedback message based on whether pods are missing or starting
    MSG="Waiting for $namespace namespace pods to be Running..."
    [[ -z "$POD_STATUS_LIST" ]] && MSG="Waiting for $namespace pods to be created..."

    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # 4. Handle timeout and retry
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 45)) ""
        exit 1
    fi
done

echo -e "\e[96mINFO\e[0m Installation complete"

# Add an empty line after the task
echo
