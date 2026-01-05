#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export SUB_CHANNEL="stable"
export CATALOG_SOURCE=redhat-operators
export NAMESPACE="stackrox"
export DEFAULT_STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

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

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=rhacs-operator

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

sleep 10

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=60                # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=$OPERATOR_NS
pod_name=rhacs-operator

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
MAX_RETRIES=450              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=$NAMESPACE

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
MAX_RETRIES=300              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=$NAMESPACE

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

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Login cluster information]"

ACS_CONSOLE=$(oc get route central -n $NAMESPACE -o jsonpath='{"https://"}{.spec.host}{"\n"}')
ACS_PW=$(oc get secret central-htpasswd -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)

echo -e "\e[96mINFO\e[0m ACS console: $ACS_CONSOLE"
echo -e "\e[96mINFO\e[0m ACS user ID: admin  PW: $ACS_PW"

# Add an empty line after the task
echo
