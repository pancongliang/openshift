# Set environment variables
export CHANNEL_NAME="stable-3.13"
export STORAGE_CLASS_NAME="gp2-csi"
export STORAGE_SIZE="50Gi"

#!/bin/bash

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

# Print task title
PRINT_TASK "[TASK: Install Minio Tool]"

# Check if mc is already installed and operational
if mc --version &> /dev/null; then
    run_command "[MC tool already installed, skipping installation]"
else
    # Download the MC tool
    curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc &> /dev/null
    run_command "[Downloaded MC tool]"

    # Remove the old version (if it exists)
    rm -f /usr/local/bin/mc &> /dev/null

    # Move the new version to /usr/local/bin
    mv mc /usr/local/bin/ &> /dev/null
    run_command "[Installed MC tool to /usr/local/bin/]"

    # Set execute permissions for the tool
    chmod +x /usr/local/bin/mc &> /dev/null
    run_command "[Set execute permissions for MC tool]"

    # Verify the installation
    if mc --version &> /dev/null; then
        run_command "[MC tool installation complete]"
    else
        run_command "[Failed to install MC tool, proceeding without it]"
    fi
fi

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Deploying Minio object]"

# Deploy Minio with the specified YAML template
export NAMESPACE="minio"

curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f - &> /dev/null
run_command "[Create Minio object]"

sleep 20

# Wait for Minio pods to be in 'Running' state
while true; do
    # Check the status of pods
    if oc get pods -n "$NAMESPACE" --no-headers &> /dev/null | awk '{print $3}' | grep -v "Running" &> /dev/null; then
        echo "info: [Waiting for pods to be in 'Running' state...]"
        sleep 20
    else
        echo "ok: [Minio pods are in 'Running' state]"
        break
    fi
done

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n ${NAMESPACE} -o jsonpath='{.spec.host}')
run_command "[Retrieved Minio route host: $BUCKET_HOST]"

sleep 3

# Set Minio client alias
mc --no-color alias set my-minio http://${BUCKET_HOST} minioadmin minioadmin &> /dev/null
run_command "[Configured Minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "quay-bucket"; do
    mc --no-color mb my-minio/$BUCKET_NAME &> /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Deploying Quay Operator]"

# Create a Subscription
cat << EOF | oc apply -f - &> /dev/null
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
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash &> /dev/null
run_command "[Approve openshift-operators install plan]"

sleep 30

# Chek Quay operator pod
EXPECTED_READY="1/1"
EXPECTED_STATUS="Running"

while true; do
    # Get the status of pods matching quay-operator in the openshift-operators namespace
    pod_status=$(oc get po -n openshift-operators --no-headers | grep "quay-operator" | awk '{print $2, $3}')

    # Check if all matching pods have reached the expected Ready and Status values
    if echo "$pod_status" | grep -q -v "$EXPECTED_READY $EXPECTED_STATUS"; then
        echo "info: [Quay operator pods have not reached the expected status, waiting...]"
        sleep 20
    else
        echo "ok: [Quay operator pods have reached the expected state]"
        break
    fi
done

# Create a namespace
oc new-project quay-enterprise &> /dev/null
run_command "[Create a quay-enterprise namespac]"

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
oc create secret generic quay-config --from-file=config.yaml -n quay-enterprise &> /dev/null
run_command "[Create a secret containing quay-config]"

rm -rf config.yaml  &> /dev/null

# Create a Quay Registry
cat << EOF | oc apply -f - &> /dev/null
apiVersion: quay.redhat.com/v1
kind: QuayRegistry
metadata:
  name: example-registry
  namespace: quay-enterprise
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

sleep 30

# Check quay pod status
EXPECTED_STATUS="Running"

while true; do
    # Check if all pods meet the expected READY and STATUS
    if oc get po -n quay-enterprise --no-headers &> /dev/null | awk '$3 != "Completed" {
        split($2, ready, "/");
        if (ready[1] != ready[2] || $3 != "'$EXPECTED_STATUS'") print "waiting";
    }' | grep -q "waiting"; then
        echo "info: [Not all pods have reached the expected status, waiting...]"
        sleep 30
    else
        echo "ok: [All pods in namespace quay-enterprise have reached the expected state]"
        break
    fi
done

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Install oc-mirror tool]"

# Check if oc-mirror is already installed and operational
if oc-mirror -h &> /dev/null; then
    run_command "[The oc-mirror tool already installed, skipping installation]"
else
    # Download the oc-mirror tool
    curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz &> /dev/null
    run_command "[Downloaded oc-mirror tool]"

    # Remove the old version (if it exists)
    rm -f /usr/local/bin/oc-mirror &> /dev/null

    tar -xvf oc-mirror.tar.gz &> /dev/null

    # Set execute permissions for the tool
    chmod +x oc-mirror &> /dev/null
    run_command "[Set execute permissions for oc-mirror tool]"

    # Move the new version to /usr/local/bin
    mv oc-mirror /usr/local/bin/ &> /dev/null
    run_command "[Installed oc-mirror tool to /usr/local/bin/]"

    # Verify the installation
    if oc-mirror -h &> /dev/null; then
        run_command "[oc-mirror tool installation complete]"
    else
        run_command "[Failed to install oc-mirror tool, proceeding without it]"
    fi
fi

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Configuring additional trust stores for image registry access]"

# Export the router-ca certificate
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator &> /dev/null 
run_command "[Export the router-ca certificate]"

sleep 30

# Create a configmap containing the CA certificate
export QUAY_HOST=$(oc get route example-registry-quay -n quay-enterprise --template='{{.spec.host}}')

sleep 10

oc create configmap registry-config --from-file=$QUAY_HOST=tls.crt -n openshift-config &> /dev/null
run_command "[Create a configmap containing the Route CA certificate]"

# Additional trusted CA
oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge &> /dev/null
run_command "[Additional trusted CA]"

rm -rf tls.crt &> /dev/null

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Update pull-secret]"

# Export pull-secret
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret
run_command "[Export pull-secret]"

# Update pull-secret file
export AUTHFILE="pull-secret"
export REGISTRY=$(oc get route example-registry-quay -n quay-enterprise --template='{{.spec.host}}')

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
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret &> /dev/null
run_command "[Update pull-secret for the cluster]"

rm -rf tmp-authfile &> /dev/null
rm -rf pull-secret &> /dev/null

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Check status]"

# Check cluser operator status
while true; do
    operator_status=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    if echo "$operator_status" | grep -q -v "True False False"; then
        echo "info: [All cluster operators have not reached the expected status, Waiting...]"
        sleep 30  
    else
        echo "ok: [All cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
while true; do
    mcp_status=$(oc get mcp --no-headers | awk '{print $3, $4, $5}')
    if echo "$mcp_status" | grep -q -v "True False False"; then
        echo "info: [All MCP have not reached the expected status, Waiting...]"
        sleep 30  
    else
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
