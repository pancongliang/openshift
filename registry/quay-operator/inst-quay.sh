# Set environment variables
export CHANNEL_NAME="stable-3.13"
export NAMESPACE="minio"
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

curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc &> /dev/null
run_command "[Downloaded MC tool]"

rm -f /usr/local/bin/mc &> /dev/null

mv mc /usr/local/bin/ &> /dev/null
run_command "[Installed MC tool to /usr/local/bin/]"

chmod +x /usr/local/bin/mc &> /dev/null
run_command "[Set execute permissions for MC tool]"

mc --version &> /dev/null
run_command "[MC tool installation complete]"

echo 

# Print task title
PRINT_TASK "[TASK: Deploying Minio object]"

# Deploy Minio with the specified YAML template
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f - &> /dev/null
run_command "[Applied Minio object]"

# Wait for Minio pods to be in 'Running' state
while true; do
    # Check the status of pods
    if oc get pods -n "$NAMESPACE" --no-headers | awk '{print $3}' | grep -v "Running" &> /dev/null; then
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
for BUCKET_NAME in "loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket"; do
    mc --no-color mb my-minio/$BUCKET_NAME &> /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done

echo 

# Print task title
PRINT_TASK "[TASK: Deploying Quay Operator]"

cat << EOF | oc apply -f - &> /dev/null
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: quay-operator
  namespace: openshift-operators
spec:
  channel: ${CHANNEL_NAME}
  installPlanApproval: Automatic
  name: quay-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
run_command "[Installing Quay Operator...]"

sleep 60

oc new-project quay-enterprise &> /dev/null
run_command "[Create a quay-enterprise namespac]"

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
EOF

oc create secret generic quay-config --from-file=config.yaml -n quay-enterprise &> /dev/null
run_command "[Create a secret containing quay-config]"

rm -rf config.yaml  &> /dev/null

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

curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz &> /dev/null
run_command "[Download oc-mirror tool]"

tar -xvf oc-mirror.tar.gz &> /dev/null
chmod +x oc-mirror &> /dev/null
rm -rf /usr/local/bin/oc-mirror &> /dev/null

mv oc-mirror /usr/local/bin/ &> /dev/null
run_command "[Install oc-mirror tool]"

rm -rf oc-mirror.tar.gz &> /dev/null

echo "info: [Red Hat Quay Operator has been deployed!]"
echo "info: [Wait for the pod in the quay-enterprise namespace to be in the running state]"
