# Set environment variables
export CHANNEL_NAME="stable-6.1"
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
for BUCKET_NAME in "loki-bucket"; do
    mc --no-color mb my-minio/$BUCKET_NAME &> /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done

echo 
# ====================================================

# Print task title
PRINT_TASK "[TASK: Install OpenShift Logging]"

# Create a namespace
cat << EOF | oc apply -f - &> /dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators-redhat 
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true" 
EOF
run_command "[Create a openshift-operators-redhat namespace]"

cat << EOF | oc apply -f - &> /dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-logging
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
EOF
run_command "[Create a openshift-logging namespace]"

# Create a OperatorGroup
cat << EOF | oc apply -f - &> /dev/null
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
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
run_command "[Create a loki operator]"

cat << EOF | oc apply -f - &> /dev/null
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
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
run_command "[Create a cluster-logging operator]"

cat << EOF | oc apply -f - &> /dev/null
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-operators
spec:
  channel: development
  installPlanApproval: "Manual"
  name: cluster-observability-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
run_command "[Create a cluster observability operator]"

# Approval IP
export NAMESPACE="openshift-logging"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash &> /dev/null
run_command "[Approve cluster-logging install plan]"

export NAMESPACE="openshift-operators-redhat"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash &> /dev/null
run_command "[Approve loki-operator install plan]"

export NAMESPACE="openshift-operators"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash &> /dev/null
run_command "[Approve cluster-observability-operator install plan]"

sleep 30

# Create Object Storage secret credentials
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
export ACCESS_KEY_ID="minioadmin"
export ACCESS_KEY_SECRET="minioadmin"
export BUCKET_NAME="loki-bucket"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/02-config.yaml | envsubst | oc create -f - &> /dev/null
run_command "[Create Object Storage secret credentials]"

# Create loki stack
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-loki-stack-v6.yaml | envsubst | oc create -f - &> /dev/null
run_command "[Create loki stack]"

sleep 30

# Check openshift-logging pod status
EXPECTED_STATUS="Running"

while true; do
    # Check if all pods meet the expected READY and STATUS
    if oc get po -n openshift-logging --no-headers | awk '$3 != "Completed" {
        split($2, ready, "/");
        if (ready[1] != ready[2] || $3 != "'$EXPECTED_STATUS'") print "waiting";
    }' | grep -q "waiting"; then
        echo "info: [Not all pods have reached the expected status, waiting...]"
        sleep 30
    else
        echo "ok: [All pods in namespace openshift-logging have reached the expected state]"
        break
    fi
done

oc project openshift-logging &> /dev/null

oc create sa collector -n openshift-logging &> /dev/null
run_command "[Create a service account for the collector]"

oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z collector &> /dev/null
run_command "[Allow the collector’s service account to write data to the LokiStack CR]"

oc adm policy add-cluster-role-to-user collect-application-logs -z collector &> /dev/null
run_command "[Allow the collector’s service account to collect app logs]"

oc adm policy add-cluster-role-to-user collect-audit-logs -z collector &> /dev/null
run_command "[Allow the collector’s service account to collect audit logs]"

oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z collector &> /dev/null
run_command "[Allow the collector’s service account to collect infra logs]"

# Creating CLF CR and UIPlugin
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/04-clf-ui.yaml | envsubst | oc create -f - &> /dev/null
run_command "[Creating CLF CR and UIPlugin]"

# Check openshift-logging pod status
EXPECTED_STATUS="Running"

while true; do
    # Check if all pods meet the expected READY and STATUS
    if oc get po -n openshift-logging --no-headers | awk '$3 != "Completed" {
        split($2, ready, "/");
        if (ready[1] != ready[2] || $3 != "'$EXPECTED_STATUS'") print "waiting";
    }' | grep -q "waiting"; then
        echo "info: [Not all pods have reached the expected status, waiting...]"
        sleep 30
    else
        echo "ok: [All pods in namespace openshift-logging have reached the expected state]"
        break
    fi
done
