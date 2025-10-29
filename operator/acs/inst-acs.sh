#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export CHANNEL_NAME="stable"
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

# Step 0:
PRINT_TASK "TASK [Uninstall old acs resources...]"

# Uninstall first
echo "info: [Uninstall old logging resources...]"
oc delete securedcluster stackrox-secured-cluster-services -n stackrox >/dev/null 2>&1 || true
oc delete central stackrox-central-services -n stackrox >/dev/null 2>&1 || true
oc delete subscription rhacs-operator -n rhacs-operator >/dev/null 2>&1 || true
oc get csv -n rhacs-operator -o name | grep rhacs-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n rhacs-operator >/dev/null 2>&1 || true
oc delete ns stackrox >/dev/null 2>&1 || true
oc delete ns rhacs-operator >/dev/null 2>&1 || true

sleep 5

# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Install RHACS Operator]"

# Create a namespace
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: rhacs-operator
EOF
run_command "[Create a rhacs-operator namespace]"

# Create a Subscription
cat << EOF | oc create -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  annotations:
    olm.providedAPIs: Central.v1alpha1.platform.stackrox.io,SecuredCluster.v1alpha1.platform.stackrox.io
  generateName: rhacs-operator-
  namespace: rhacs-operator
spec:
  upgradeStrategy: Default
EOF
run_command "[Create a operator group]"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/rhacs-operator.rhacs-operator: ""
  name: rhacs-operator
  namespace: rhacs-operator
spec:
  channel: ${CHANNEL_NAME}
  installPlanApproval: "Manual"
  source: ${CATALOG_SOURCE_NAME}
  name: rhacs-operator
  sourceNamespace: openshift-marketplace
EOF
run_command "[Installing rhacs operator...]"

sleep 30

# Approval IP
export NAMESPACE="rhacs-operator"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[Approve rhacs-operator install plan]"

sleep 10

# Wait for rhacs-operator pods to be in 'Running' state
NAMESPACE="rhacs-operator"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=rhacs-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep rhacs | awk '{print $2, $3}' || true)
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name pods may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name pods are in 'running' state]"
        break
    fi
done

# Create a namespace
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: stackrox
EOF
run_command "[Create a stackrox namespace]"

# Create a Central
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: platform.stackrox.io/v1alpha1
kind: Central
metadata:
  name: stackrox-central-services
  namespace: stackrox
spec:
  central:
    exposure:
      loadBalancer:
        enabled: false
        port: 443
      nodePort:
        enabled: false
      route:
        enabled: true
    persistence:
      persistentVolumeClaim:
        claimName: stackrox-db
    db:
      isEnabled: Default
      persistence:
        persistentVolumeClaim:
          claimName: central-db
  egress:
    connectivityPolicy: Online
  scanner:
    analyzer:
      scaling:
        autoScaling: Enabled
        maxReplicas: 5
        minReplicas: 2
        replicas: 3
    scannerComponent: Enabled
EOF
run_command "[Create a central instance]"

sleep 30

# Wait for stackrox pods to be in 'Running' state
NAMESPACE="stackrox"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=stackrox

while true; do
    # Get the status of all pods
    output=$(oc get po -n $NAMESPACE --no-headers 2>/dev/null |grep -v Completed | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name namespace pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name namespace pods may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name namespace pods are in 'running' state]"
        break
    fi
done

# Check if roxctl is already installed and operational
if roxctl -h >/dev/null 2>&1; then
    run_command "[The roxctl tool already installed, skipping installation]"
else
    # Download the roxctl tool
    arch="$(uname -m | sed "s/x86_64//")"; arch="${arch:+-$arch}"
    curl -f -o roxctl "https://mirror.openshift.com/pub/rhacs/assets/latest/bin/Linux/roxctl${arch}" >/dev/null 2>&1
    run_command "[Downloaded roxctl tool]"

    # Remove the old version (if it exists)
    sudo rm -f /usr/local/bin/roxctl >/dev/null 2>&1
    
    # Set execute permissions for the tool
    chmod +x roxctl >/dev/null 2>&1
    run_command "[Set execute permissions for roxctl tool]"

    # Move the new version to /usr/local/bin
    sudo mv -f roxctl /usr/local/bin/ >/dev/null
    run_command "[Installed roxctl tool to /usr/local/bin/]"

    # Verify the installation
    if roxctl -h >/dev/null 2>&1; then
       echo "ok: [Roxctl tool installation complete]"
    else
       echo "failed: [Roxctl tool installation complete]"
    fi
fi

# Creating resources by using the init bundle
sudo rm -rf cluster_init_bundle.yaml

export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443

sleep 1

export ROX_CENTRAL_ADMIN_PASS=$(oc -n stackrox get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}')

sleep 1

roxctl -e "${ROX_CENTRAL_ADDRESS}" -p "${ROX_CENTRAL_ADMIN_PASS}" central init-bundles generate init_bundle --output-secrets cluster_init_bundle.yaml --insecure-skip-tls-verify >/dev/null 2>&1

sleep 1

oc apply -f cluster_init_bundle.yaml -n stackrox >/dev/null 2>&1
run_command "[Creating resources by using the init bundle]"

sudo rm -rf cluster_init_bundle.yaml

sleep 10

# Create a SecuredCluster
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: platform.stackrox.io/v1alpha1
kind: SecuredCluster
metadata:
  name: stackrox-secured-cluster-services
  namespace: stackrox
spec:
  admissionControl:
    bypass: BreakGlassAnnotation
    contactImageScanners: DoNotScanInline
    listenOnCreates: true
    listenOnEvents: true
    listenOnUpdates: true
    replicas: 3
    timeoutSeconds: 20
  auditLogs:
    collection: Auto
  centralEndpoint: 'central.stackrox.svc:443'
  clusterName: my-cluster
  monitoring:
    openshift:
      enabled: true
  perNode:
    collector:
      collection: EBPF
      imageFlavor: Regular
    taintToleration: TolerateTaints
  scanner:
    analyzer:
      scaling:
        autoScaling: Enabled
        maxReplicas: 5
        minReplicas: 2
        replicas: 3
    scannerComponent: AutoSense
EOF
run_command "[Create a secured cluster]"

sleep 10

# Wait for stackrox pods to be in 'Running' state
NAMESPACE="stackrox"
MAX_RETRIES=60
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=stackrox

while true; do
    # Get the status of all pods
    output=$(oc get po -n $NAMESPACE --no-headers 2>/dev/null |grep -v Completed | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name namespace pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name namespace pods may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name namespace pods are in 'running' state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Login cluster information]"

ACS_CONSOLE=$(oc get route central -n stackrox -o jsonpath='{"https://"}{.spec.host}{"\n"}')
ACS_PW=$(oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d)

echo "info: [ACS console: $ACS_CONSOLE]"
echo "info: [ACS user id: admin  pw: $ACS_PW]"

# Add an empty line after the task
echo
