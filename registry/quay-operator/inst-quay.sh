#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export CHANNEL_NAME="stable-3.13"
export STORAGE_CLASS_NAME="managed-nfs-storage"
#export STORAGE_CLASS_NAME="gp2-csi"
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
PRINT_TASK "TASK [Deploying Minio Object Storage]"

# Delete custom resources
echo "info: [uninstall custom resources...]"
export NAMESPACE="quay-enterprise" || true
oc delete quayregistry example-registry -n $NAMESPACE >/dev/null 2>&1 || true
oc delete secret quay-config -n $NAMESPACE >/dev/null 2>&1 || true
oc delete subscription quay-operator -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep quay-operator | awk -F/ '{print $2}'  | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true
oc delete ns quay-enterprise >/dev/null 2>&1 || true
oc delete ns minio >/dev/null 2>&1 || true

sleep 15

# Deploy Minio with the specified YAML template
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
        sleep 3
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
oc rsh -n minio deployments/minio mc --no-color mb my-minio/quay-bucket >/dev/null 2>&1
run_command "[created bucket: quay-bucket]"

# Print Minio address and credentials
echo "info: [minio address: $BUCKET_HOST]"
echo "info: [minio default id/pw: minioadmin/minioadmin]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Deploying Quay Operator]"

# Create a Subscription
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: quay-operator
  namespace: openshift-operators
spec:
  channel: ${CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: quay-operator
  source: $CATALOG_SOURCE_NAME
  sourceNamespace: openshift-marketplace
EOF
run_command "[installing quay operator...]"

# Approval IP
export NAMESPACE="openshift-operators"
sudo curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[approve openshift-operators install plan]"

sleep 10

# Initialize progress_started as false
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers | grep "quay-operator" | awk '{print $2, $3}')
    
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
        echo "ok: [quay operator pods are in 'running' state]"
        break
    fi
done

# Create a namespace
export NAMESPACE="quay-enterprise"
oc new-project $NAMESPACE >/dev/null 2>&1
run_command "[create a $NAMESPACE namespace]"

# Create a quay config
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='{.spec.host}')
export ACCESS_KEY_ID="minioadmin"
export ACCESS_KEY_SECRET="minioadmin"
export BUCKET_NAME="quay-bucket"

sudo cat << EOF > config.yaml
DISTRIBUTED_STORAGE_CONFIG:
  default:
    - RadosGWStorage
    - access_key: ${ACCESS_KEY_ID}
      secret_key: ${ACCESS_KEY_SECRET}
      bucket_name: ${BUCKET_NAME}
      hostname: ${BUCKET_HOST}
      is_secure: false
      port: 80
      storage_path: /
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
    - default
SUPER_USERS:
    - quayadmin
DEFAULT_TAG_EXPIRATION: 1m
TAG_EXPIRATION_OPTIONS:
    - 1m
EOF
run_command "[create a quay config file]"

sleep 10

# Create a secret containing the quay config
oc create secret generic quay-config --from-file=config.yaml -n $NAMESPACE >/dev/null 2>&1
run_command "[create a secret containing quay-config]"

sudo rm -rf config.yaml >/dev/null 2>&1

# Create a Quay Registry
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: quay.redhat.com/v1
kind: QuayRegistry
metadata:
  name: example-registry
  namespace: $NAMESPACE
spec:
  configBundleSecret: quay-config
  components:
    - kind: objectstorage
      managed: false
    - kind: horizontalpodautoscaler
      managed: false
    - kind: quay
      managed: true
      overrides:
        replicas: 1
    - kind: clair
      managed: true
      overrides:
        replicas: 1
    - kind: mirror
      managed: true
      overrides:
        replicas: 1
EOF
run_command "[create a quay registry]"

sleep 10

# Check quay pod status
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers |grep -v Completed | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 20
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [quay pods are in 'running' state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Configuring additional trust stores for image registry access]"

# Export the router-ca certificate
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator >/dev/null 2>&1
run_command "[export the router-ca certificate]"

sleep 10

# Create a configmap containing the CA certificate
export QUAY_HOST=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}') >/dev/null 2>&1

sleep 10

# Check if the registry-cas field exists
REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if [[ -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-config --from-file=$QUAY_HOST=tls.crt -n openshift-config >/dev/null 2>&1
  run_command  "[create a configmap containing the registry CA certificate: registry-config]"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null 2>&1
  run_command  "[trust the registry-config configmap]"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-cas --from-file=$QUAY_HOST=tls.crt -n openshift-config >/dev/null 2>&1
  run_command  "[create a configmap containing the registry CA certificate: registry-cas]"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge >/dev/null 2>&1
  run_command  "[trust the registry-cas configmap]"
fi

sudo rm -rf tls.crt >/dev/null

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Update pull-secret]"

# Export pull-secret
sudo rm -rf pull-secret
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret
run_command "[export pull-secret]"

# Update pull-secret file
export AUTHFILE="pull-secret"
export REGISTRY=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}')

# Base64 encode the username:password
AUTH=cXVheWFkbWluOnBhc3N3b3Jk

if [ -f "$AUTHFILE" ]; then
  jq --arg registry "$REGISTRY" \
     --arg auth "$AUTH" \
     '.auths[$registry] = {auth: $auth}' \
     "$AUTHFILE" > tmp-authfile && mv -f tmp-authfile "$AUTHFILE"
else
sudo cat <<EOF > $AUTHFILE
{
    "auths": {
        "$REGISTRY": {
            "auth": "$AUTH"
        }
    }
}
EOF
fi
echo "ok: [authentication information for quay registry added to $AUTHFILE]"

# Update pull-secret 
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret >/dev/null 2>&1
run_command "[update pull-secret for the cluster]"

sudo rm -rf tmp-authfile >/dev/null 2>&1
sudo rm -rf pull-secret >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Checking the cluster status]"

# Check cluster operator status
progress_started=false
while true; do
    operator_status=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    
    if echo "$operator_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 20
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
progress_started=false

while true; do
    mcp_status=$(oc get mcp --no-headers | awk '{print $3, $4, $5}')

    if echo "$mcp_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all mcps to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 20
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all mcp have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Manually create a user]"

echo "note: [***you need to create a user in the quay console with an id of <quayadmin> and a pw of <password>***]"
echo "note: [***you need to create a user in the quay console with an id of <quayadmin> and a pw of <password>***]"
echo "note: [***you need to create a user in the quay console with an id of <quayadmin> and a pw of <password>***]"
