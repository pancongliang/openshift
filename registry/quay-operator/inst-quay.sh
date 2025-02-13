#!/bin/bash
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export CHANNEL_NAME="stable-3.13"
#export STORAGE_CLASS_NAME="managed-nfs-storage"
export STORAGE_CLASS_NAME="gp2-csi"
export STORAGE_SIZE="50Gi"


# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}
# ====================================================

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}
# ====================================================

export NAMESPACE="quay-enterprise"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/03-quay-registry.yaml | envsubst | oc delete -f - >/dev/null 2>&1
export NAMESPACE="openshift-operators"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/01-operator.yaml | envsubst | oc delete -f - >/dev/null 2>&1

oc delete ns quay-enterprise >/dev/null 2>&1


# Print task title
PRINT_TASK "[TASK: Deploying Minio Tool]"

# Deploy Minio with the specified YAML template
export NAMESPACE="minio"
oc delete ns $NAMESPACE >/dev/null 2>&1

# Determine the operating system and architecture
OS_TYPE=$(uname -s)
ARCH=$(uname -m)

echo "info: [Client Operating System: $OS_TYPE]"
echo "info: [Client Architecture: $ARCH]"

# Set the download URL based on the OS and architecture
if [ "$OS_TYPE" = "Darwin" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        download_url="https://dl.min.io/client/mc/release/darwin-amd64/mc"
    elif [ "$ARCH" = "arm64" ]; then
        download_url="https://dl.min.io/client/mc/release/darwin-arm64/mc"
    fi
elif [ "$OS_TYPE" = "Linux" ]; then
    download_url="https://dl.min.io/client/mc/release/linux-amd64/mc"
else
    echo "error: [MC tool installation failed]"
fi

# Download MC
curl -sOL "$download_url" 
run_command "[Downloaded MC tool]"

# Install MC and set permissions
rm -f /usr/local/bin/mc > /dev/null
mv mc /usr/local/bin/ > /dev/null
run_command "[Installed MC tool to /usr/local/bin/]"

chmod +x /usr/local/bin/mc > /dev/null
run_command "[Set execute permissions for MC tool]"

mc --version > /dev/null
run_command "[MC tool installation complete]"

echo 

# Print task title
PRINT_TASK "[TASK: Deploying Minio Object Storage]"

# Deploy Minio with the specified YAML template
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f - >/dev/null 2>&1
run_command "[Applied Minio object]"

# Wait for Minio pods to be in 'Running' state
# Initialize progress_started as false
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [Minio pods are in 'running' state]"
        break
    fi
done


# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n ${NAMESPACE} -o jsonpath='{.spec.host}')
run_command "[Retrieved Minio route host: $BUCKET_HOST]"

sleep 3

# Set Minio client alias
mc --no-color alias set my-minio http://${BUCKET_HOST} minioadmin minioadmin > /dev/null
run_command "[Configured Minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket"; do
    mc --no-color mb my-minio/$BUCKET_NAME > /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done

# Print Minio address and credentials
echo "info: [Minio address: http://$BUCKET_HOST]"
echo "info: [Minio default ID/PW: minioadmin/minioadmin]"

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Deploying Quay Operator]"

# Create a Subscription
cat << EOF | oc apply -f - >/dev/null
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: quay-operator
  namespace: openshift-operators
spec:
  channel: ${CHANNEL_NAME}
  installPlanApproval: "Manual"
  name: quay-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
run_command "[Installing Quay Operator...]"

# Approval IP
export NAMESPACE="openshift-operators"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[Approve openshift-operators install plan]"

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
            echo -n "info: [Waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [Quay operator pods are in 'running' state]"
        break
    fi
done


# Create a namespace
export NAMESPACE="quay-enterprise"
oc new-project $NAMESPACE >/dev/null
run_command "[Create a $NAMESPACE namespac]"

# Create a quay config
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='{.spec.host}')
export ACCESS_KEY_ID="minioadmin"
export ACCESS_KEY_SECRET="minioadmin"
export BUCKET_NAME="quay-bucket"

cat << EOF > config.yaml
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

sleep 3
# Create a secret containing the quay config
oc create secret generic quay-config --from-file=config.yaml -n $NAMESPACE >/dev/null
run_command "[Create a secret containing quay-config]"

rm -rf config.yaml  >/dev/null

# Create a Quay Registry
cat << EOF | oc apply -f - >/dev/null
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
run_command "[Create a QuayRegistry]"

sleep 15

# Check quay pod status
# Initialize progress_started as false
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers |grep -v Completed | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 10
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [Quay pods are in 'running' state]"
        break
    fi
done

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Configuring additional trust stores for image registry access]"

# Export the router-ca certificate
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator >/dev/null 2>&1
run_command "[Export the router-ca certificate]"

sleep 30

# Create a configmap containing the CA certificate
export QUAY_HOST=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}')

sleep 10

oc delete configmap registry-config -n openshift-config >/dev/null 2>&1
oc create configmap registry-config --from-file=$QUAY_HOST=tls.crt -n openshift-config >/dev/null
run_command "[Create a configmap containing the Route CA certificate]"

# Additional trusted CA
oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null
run_command "[Additional trusted CA]"

rm -rf tls.crt >/dev/null

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Update pull-secret]"

# Export pull-secret
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret
run_command "[Export pull-secret]"

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
  cat <<EOF > $AUTHFILE
{
    "auths": {
        "$REGISTRY": {
            "auth": "$AUTH"
        }
    }
}
EOF
fi
echo "ok: [Authentication information for Quay Registry added to $AUTHFILE]"

# Update pull-secret 
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret >/dev/null
run_command "[Update pull-secret for the cluster]"

rm -rf tmp-authfile >/dev/null
rm -rf pull-secret >/dev/null

echo 
# ====================================================

# Check cluser operator status
# Print task title
PRINT_TASK "[TASK: Check status]"

# Check cluster operator status
progress_started=false
while true; do
    operator_status=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    
    if echo "$operator_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [Waiting for all cluster operators to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
progress_started=false

while true; do
    mcp_status=$(oc get mcp --no-headers | awk '{print $3, $4, $5}')

    if echo "$mcp_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [Waiting for all MCPs to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All MCP have reached the expected state]"
        break
    fi
done

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Manually create a user]"

echo "note: [***You need to create a user in the Quay console with an ID of <quayadmin> and a PW of <password>***]"
echo "note: [***You need to create a user in the Quay console with an ID of <quayadmin> and a PW of <password>***]"
echo "note: [***You need to create a user in the Quay console with an ID of <quayadmin> and a PW of <password>***]"
