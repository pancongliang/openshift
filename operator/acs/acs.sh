#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export SUB_CHANNEL="stable"
export CATALOG_SOURCE=redhat-operators
export DEFAULT_STORAGE_CLASS=managed-nfs-storage
export NAMESPACE="stackrox"

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
PRINT_TASK "TASK [Delete old acs resources]"

# Delete custom resources
if oc get securedcluster stackrox-secured-cluster-services -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting securedcluster stackrox-secured-cluster-services..."
    oc delete securedcluster stackrox-secured-cluster-services -n $NAMESPACE >/dev/null 2>&1 || true
else
    echo -e "\e[96mINFO\e[0m Securedcluster does not exist"
fi

if oc get central stackrox-central-services -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting central stackrox-central-services..."
    oc delete central stackrox-central-services -n $NAMESPACE >/dev/null 2>&1 || true
else
    echo -e "\e[96mINFO\e[0m Central does not exist"
fi

oc delete subscription rhacs-operator -n rhacs-operator >/dev/null 2>&1 || true
oc get csv -n rhacs-operator -o name | grep rhacs-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n rhacs-operator >/dev/null 2>&1 || true
oc get ip -n rhacs-operator --no-headers 2>/dev/null|grep rhacs-operator|awk '{print $1}'|xargs -r oc delete ip -n rhacs-operator >/dev/null 2>&1 || true

if oc get ns $NAMESPACE >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting rhacs operator..."
   echo -e "\e[96mINFO\e[0m Deleting $NAMESPACE project..."
   oc delete ns $NAMESPACE >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The $NAMESPACE project does not exist"
fi

if oc get ns rhacs-operator >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting rhacs-operator project..."
   oc delete ns rhacs-operator >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The rhacs-operator project does not exist"
fi

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
run_command "Create a rhacs-operator namespace"

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
run_command "Create a operator group"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/rhacs-operator.rhacs-operator: ""
  name: rhacs-operator
  namespace: rhacs-operator
spec:
  channel: ${SUB_CHANNEL}
  installPlanApproval: "Manual"
  source: ${CATALOG_SOURCE}
  name: rhacs-operator
  sourceNamespace: openshift-marketplace
EOF
run_command "Installing rhacs operator..."

sleep 30

# Approval IP
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
export OPERATOR_NS="rhacs-operator"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the rhacs-operator install plan"

sleep 10

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=60    # Maximum number of retries
SLEEP_INTERVAL=2  # Sleep interval in seconds
LINE_WIDTH=120    # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
project=$OPERATOR_NS
pod_name=rhacs-operator

while true; do
    # Get the status of all pods in the pod_name project
    PODS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2, $3}' || true)
    
    # Check if all pods are in "1/1 Running" state
    ALL_READY=true
    while read -r READY STATUS; do
        if [[ "$READY $STATUS" != "1/1 Running" ]]; then
            ALL_READY=false
            break
        fi
    done <<< "$PODS"

    if $ALL_READY; then
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

# Create a namespace
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOF
run_command "Create a $NAMESPACE namespace"

# Create a Central
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: platform.stackrox.io/v1alpha1
kind: Central
metadata:
  name: stackrox-central-services
  namespace: $NAMESPACE
spec:
  monitoring:
    openshift:
      enabled: true
  network:
    policies: Enabled
  central:
    notifierSecretsEncryption:
      enabled: false
    exposure:
      loadBalancer:
        enabled: false
        port: 443
      nodePort:
        enabled: false
      route:
        enabled: true
    telemetry:
      enabled: true
    db:
      isEnabled: Default
      persistence:
        persistentVolumeClaim:
          claimName: central-db
    persistence:
      persistentVolumeClaim:
        claimName: stackrox-db
  egress:
    connectivityPolicy: Online
  scannerV4:
    db:
      persistence:
        persistentVolumeClaim:
          claimName: scanner-v4-db
    indexer:
      scaling:
        autoScaling: Enabled
        maxReplicas: 5
        minReplicas: 2
        replicas: 3
    matcher:
      scaling:
        autoScaling: Enabled
        maxReplicas: 5
        minReplicas: 2
        replicas: 3
    scannerComponent: Default
  scanner:
    analyzer:
      scaling:
        autoScaling: Enabled
        maxReplicas: 5
        minReplicas: 2
        replicas: 3
EOF
run_command "Create a central instance"

sleep 30

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=450    # Maximum number of retries
SLEEP_INTERVAL=2   # Sleep interval in seconds
LINE_WIDTH=120     # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
namespace=$NAMESPACE

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

# Check if roxctl is already installed and operational
if roxctl -h >/dev/null 2>&1; then
    run_command "The roxctl tool already installed, skipping installation"
else
    # Download the roxctl tool
    echo -e "\e[96mINFO\e[0m Downloading the roxctl tool"
    arch="$(uname -m | sed "s/x86_64//")"; arch="${arch:+-$arch}"
    curl -f -o roxctl "https://mirror.openshift.com/pub/rhacs/assets/latest/bin/Linux/roxctl${arch}" >/dev/null 2>&1
    run_command "Downloaded roxctl tool"

    # Remove the old version (if it exists)
    sudo rm -f /usr/local/bin/roxctl >/dev/null 2>&1
    
    # Set execute permissions for the tool
    chmod +x roxctl >/dev/null 2>&1
    run_command "Set execute permissions for roxctl tool"

    # Move the new version to /usr/local/bin
    sudo mv -f roxctl /usr/local/bin/ >/dev/null
    run_command "Installed roxctl tool to /usr/local/bin/roxctl"

    # Verify the installation
    if roxctl -h >/dev/null 2>&1; then
       echo -e "\e[96mINFO\e[0m Roxctl tool installation complete"
    else
       echo -e "\e[31mFAILED\e[0m Roxctl tool installation complete"
    fi
fi

sleep 20

# Creating resources by using the init bundle
sudo rm -rf cluster_init_bundle.yaml

export ROX_CENTRAL_ADDRESS=$(oc get route central -n $NAMESPACE -o jsonpath='{.spec.host}'):443

sleep 1

export ROX_CENTRAL_ADMIN_PASS=$(oc -n $NAMESPACE get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}')

sleep 1

roxctl -e "${ROX_CENTRAL_ADDRESS}" -p "${ROX_CENTRAL_ADMIN_PASS}" central init-bundles generate init_bundle --output-secrets cluster_init_bundle.yaml --insecure-skip-tls-verify >/dev/null 2>&1

sleep 1

oc apply -f cluster_init_bundle.yaml -n $NAMESPACE >/dev/null 2>&1
run_command "Creating resources by using the init bundle"

sudo rm -rf cluster_init_bundle.yaml

sleep 10

# Create a SecuredCluster
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: platform.stackrox.io/v1alpha1
kind: SecuredCluster
metadata:
  name: stackrox-secured-cluster-services
  namespace: $NAMESPACE
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
run_command "Create a secured cluster..."

sleep 30

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=300    # Maximum number of retries
SLEEP_INTERVAL=2   # Sleep interval in seconds
LINE_WIDTH=120     # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
namespace=$NAMESPACE

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

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Login cluster information]"

ACS_CONSOLE=$(oc get route central -n $NAMESPACE -o jsonpath='{"https://"}{.spec.host}{"\n"}')
ACS_PW=$(oc get secret central-htpasswd -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)

echo -e "\e[96mINFO\e[0m ACS console: $ACS_CONSOLE"
echo -e "\e[96mINFO\e[0m ACS user id: admin  pw: $ACS_PW"

# Add an empty line after the task
echo
