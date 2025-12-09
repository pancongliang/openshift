#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export SUB_CHANNEL="stable-3.14"
export DEFAULT_STORAGE_CLASS="managed-nfs-storage"
export STORAGE_SIZE="50Gi"
export NAMESPACE="quay-enterprise"
export OPERATOR_NS=openshift-operators
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
PRINT_TASK "TASK [Uninstall old quay resources]"

# Delete custom resources
if oc get quayregistry example-registry -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting QuayRegistry example-registry..."
    oc delete quayregistry example-registry -n "$NAMESPACE" >/dev/null 2>&1
else
    echo -e "\e[96mINFO\e[0m QuayRegistry does not exist"
fi

oc delete secret quay-config -n $NAMESPACE >/dev/null 2>&1 || true
oc delete subscription quay-operator -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep quay-operator | awk -F/ '{print $2}'  | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true

if oc get ns $NAMESPACE >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting quay operator..."
   echo -e "\e[96mINFO\e[0m Deleting $NAMESPACE project..."
   oc delete ns $NAMESPACE >/dev/null 2>&1
else
   echo -e "\e[96mINFO\e[0m The $NAMESPACE project does not exist"
fi

# Add an empty line after the task
echo

# Step 1:
# Deploying Minio Object Storage
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/minio/minio.sh |sh

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
  channel: ${SUB_CHANNEL}
  installPlanApproval: "Manual"
  name: quay-operator
  source: $CATALOG_SOURCE
  sourceNamespace: openshift-marketplace
EOF
run_command "Installing quay operator..."

# Approval IP
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the quay operator install plan"

sleep 10

# Wait for quay-operator pods to be in 'Running' state
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=quay-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$OPERATOR_NS" --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for $pod_name pods to be in 'Running' state"
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
        echo -e "\e[96mINFO\e[0m All $pod_name pods are in the Running state"
        break
    fi
done

# Create a namespace
oc new-project $NAMESPACE >/dev/null 2>&1
run_command "Create a $NAMESPACE namespace"

# Set environment variables
export ACCESS_KEY_ID="minioadmin"
export ACCESS_KEY_SECRET="minioadmin"
export BUCKET_NAME="quay-bucket"
export MINIO_HOST=$(oc get route minio -n minio -o jsonpath='{.spec.host}')

# Create a quay config
cat << EOF > config.yaml
DISTRIBUTED_STORAGE_CONFIG:
  default:
    - RadosGWStorage
    - access_key: ${ACCESS_KEY_ID}
      secret_key: ${ACCESS_KEY_SECRET}
      bucket_name: ${BUCKET_NAME}
      hostname: ${MINIO_HOST}
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
run_command "Create a quay config file"

sleep 10

# Create a secret containing the quay config
oc create secret generic quay-config --from-file=config.yaml -n $NAMESPACE >/dev/null 2>&1
run_command "Create a secret containing quay-config"

rm -rf config.yaml >/dev/null 2>&1

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
run_command "Create a quay registry"

sleep 10

# Wait for quay pods to be in 'Running' state
MAX_RETRIES=60
SLEEP_INTERVAL=10
progress_started=false
retry_count=0

while true; do
    # Get the READY column of all pods that are not Completed
    output=$(oc get po -n $NAMESPACE --no-headers 2>/dev/null | grep -v Completed | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$output" | awk -F/ '$1 != $2')

    if [[ -n "$not_ready" ]]; then
        # Print info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for $NAMESPACE namespace pods to be in Running state"
            progress_started=true
        fi

        # Print a progress dot
        echo -n '.'

        # Sleep before the next check
        sleep "$SLEEP_INTERVAL"

        # Increment retry counter
        retry_count=$((retry_count + 1))

        # Exit if max retries are exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo
            echo -e "\e[31mFAILED\e[0m Reached max retries namespace pods may still be initializing"
            exit 1
        fi
    else
        # All pods are ready, print success message
        if $progress_started; then
            echo
        fi
        echo -e "\e[96mINFO\e[0m All $NAMESPACE namespace pods are in Running state"
        break
    fi
done

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Configuring additional trust stores for image registry access]"

# Export the router-ca certificate
rm -rf tls.crt >/dev/null
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator >/dev/null 2>&1
run_command "Export the router-ca certificate"

sleep 2

sudo rm -rf /etc/pki/ca-trust/source/anchors/ingress-ca.crt >/dev/null 2>&1
sudo cp tls.crt /etc/pki/ca-trust/source/anchors/ingress-ca.crt >/dev/null 2>&1
run_command "Copy rootCA certificate to trusted anchors"

rm -rf tls.crt >/dev/null

# Trust the rootCA certificate
sudo update-ca-trust
run_command "Trust the rootCA certificate"

sleep 10

# Create a configmap containing the CA certificate
export QUAY_HOST=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}') >/dev/null 2>&1

REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if [[ -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-config --from-file=${QUAY_HOST}=/etc/pki/ca-trust/source/anchors/ingress-ca.crt -n openshift-config >/dev/null 2>&1
  run_command "Create a configmap containing the registry CA certificate: registry-config"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null 2>&1
  run_command "Trust the registry-config configmap"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-cas --from-file=${QUAY_HOST}=/etc/pki/ca-trust/source/anchors/ingress-ca.crt -n openshift-config >/dev/null 2>&1
  run_command "Create a configmap containing the registry CA certificate: registry-cas"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge >/dev/null 2>&1
  run_command "Trust the registry-cas configmap"
fi

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Update pull-secret]"

# Export pull-secret
rm -rf pull-secret
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret
run_command "Export pull-secret"

sleep 5

# Update pull-secret file
export AUTHFILE="pull-secret"

# Base64 encode the username:password
AUTH=cXVheWFkbWluOnBhc3N3b3Jk
export REGISTRY=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}')

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
echo -e "\e[96mINFO\e[0m Authentication information for quay registry added to $AUTHFILE"

# Update pull-secret 
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret >/dev/null 2>&1
run_command "Update pull-secret for the cluster"

rm -rf tmp-authfile >/dev/null 2>&1
rm -rf pull-secret >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Checking the cluster status]"

# Check cluster operator status
MAX_RETRIES=30
SLEEP_INTERVAL=20
progress_started=false
retry_count=0

while true; do
    # Get the status of all cluster operators
    output=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    
    # Check cluster operators status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for all cluster operators to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries cluster operator may still be initializing"
            break
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m All cluster operators have reached the expected state"
        break
    fi
done

# Check MCP status
MAX_RETRIES=20
SLEEP_INTERVAL=15
progress_started=false
retry_count=0

while true; do
    # Get the status of all mcp
    output=$(oc get mcp --no-headers | awk '{print $3, $4, $5}')
    
    # Check mcp status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for all MCP to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries MCP may still be initializing"
            break
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m All MCP have reached the expected state"
        break
    fi
done

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Manually create a user]"
echo -e "\e[96mINFO\e[0m Quay console: https://$QUAY_HOST"
echo -e "\e[96mINFO\e[0m podman login --tls-verify=false $QUAY_HOST -u quayadmin -p password"
echo -e "\e[33mACTION\e[0m You need to create a user in the quay console with an id of <quayadmin> and a pw of <password>"
