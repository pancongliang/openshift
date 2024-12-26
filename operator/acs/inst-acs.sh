# Set environment variables
export CHANNEL_NAME="stable"

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
PRINT_TASK "[TASK: Install RHACS Operator]"

# Create a namespace
cat << EOF | oc apply -f - &> /dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: rhacs-operator
EOF
run_command "[Create a rhacs-operator namespace]"

# Create a Subscription
cat << EOF | oc apply -f - &> /dev/null
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

cat << EOF | oc apply -f - &> /dev/null
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/rhacs-operator.rhacs-operator: ""
  name: rhacs-operator
  namespace: rhacs-operator
spec:
  channel: ${CHANNEL_NAME}
  installPlanApproval: Automatic
  source: redhat-operators
  name: rhacs-operator
  sourceNamespace: openshift-marketplace
EOF
run_command "[Installing RHACS Operator...]"

sleep 30

# Chek Quay operator pod
EXPECTED_READY="1/1"
EXPECTED_STATUS="Running"

while true; do
    # Get the status of pods matching quay-operator in the openshift-operators namespace
    pod_status=$(oc get po -n rhacs-operator --no-headers &> /dev/null | grep "rhacs" | awk '{print $2, $3}')

    # Check if all matching pods have reached the expected Ready and Status values
    if echo "$pod_status" | grep -q -v "$EXPECTED_READY $EXPECTED_STATUS"; then
        echo "info: [ACS operator pods have not reached the expected status, waiting...]"
        sleep 20
    else
        echo "ok: [ACS operator pods have reached the expected state]"
        break
    fi
done

# Create a namespace
cat << EOF | oc apply -f - &> /dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: stackrox
EOF
run_command "[Create a stackrox namespace]"

# Create a Central
cat << EOF | oc apply -f - &> /dev/null
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

# Check pod status
EXPECTED_READY="1/1" 
EXPECTED_STATUS="Running"

while true; do
    # Get the status of all pods excluding those in Completed state
    pod_status=$(oc get po -n stackrox --no-headers &> /dev/null | awk '$3 != "Completed" {print $2, $3}')

    # Check if any pod does not meet the expected conditions
    if echo "$pod_status" | grep -q -v "$EXPECTED_READY $EXPECTED_STATUS"; then
        echo "info: [Not all pods have reached the expected status, waiting...]"
        sleep 30
    else
        echo "ok: [All pods in namespace stackrox have reached the expected state]"
        break
    fi
done

# Check if roxctl is already installed and operational
if roxctl -h &> /dev/null; then
    run_command "[The roxctl tool already installed, skipping installation]"
else
    # Download the roxctl tool
    arch="$(uname -m | sed "s/x86_64//")"; arch="${arch:+-$arch}"
    curl -f -o roxctl "https://mirror.openshift.com/pub/rhacs/assets/latest/bin/Linux/roxctl${arch}" &> /dev/null
    run_command "[Downloaded roxctl tool]"

    # Remove the old version (if it exists)
    rm -f /usr/local/bin/roxctl &> /dev/null
    
    # Set execute permissions for the tool
    chmod +x roxctl &> /dev/null
    run_command "[Set execute permissions for roxctl tool]"

    # Move the new version to /usr/local/bin
    mv -f roxctl /usr/local/bin/ &> /dev/null
    run_command "[Installed roxctl tool to /usr/local/bin/]"

    # Verify the installation
    if roxctl -h &> /dev/null; then
        run_command "[roxctl tool installation complete]"
    else
        run_command "[Failed to install roxctl tool, proceeding without it]"
    fi
fi

# Creating resources by using the init bundle
export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
roxctl -e "$ROX_CENTRAL_ADDRESS" central init-bundles generate cluster_init_bundle.yaml --output-secrets cluster_init_bundle.yaml
sleep 10
oc apply -f cluster_init_bundle.yaml -n stackrox
run_command "[Creating resources by using the init bundle]"

sleep 10

# Create a SecuredCluster
cat << EOF | oc apply -f - &> /dev/null
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

sleep 20

# Check pod status
EXPECTED_READY="1/1" 
EXPECTED_STATUS="Running"

while true; do
    # Get the status of all pods excluding those in Completed state
    pod_status=$(oc get po -n stackrox --no-headers &> /dev/null | awk '$3 != "Completed" {print $2, $3}')

    # Check if any pod does not meet the expected conditions
    if echo "$pod_status" | grep -q -v "$EXPECTED_READY $EXPECTED_STATUS"; then
        echo "info: [Not all pods have reached the expected status, waiting...]"
        sleep 30
    else
        echo "ok: [All pods in namespace stackrox have reached the expected state]"
        break
    fi
done
