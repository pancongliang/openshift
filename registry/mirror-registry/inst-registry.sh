#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export REGISTRY_HOST_NAME="mirror.registry.example.com"
export REGISTRY_HOST_IP="10.184.134.128"
export REGISTRY_ID="admin"
export REGISTRY_PW="password"
export REGISTRY_INSTALL_DIR="/opt/quay-install"

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
    if  $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 1: 
PRINT_TASK "TASK Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "podman")

# Convert the array to a space-separated string
package_list="${packages[@]}"

# Install all packages at once
sudo dnf install -y $package_list >/dev/null 2>&1

# Check if each package was installed successfully
for package in "${packages@]}"; do
    rpm -q $package >/dev/null 2>&1
    if  $? -eq 0 ]; then
        echo "ok: Installed $package package]"
    else
        echo "failed: Installed $package package]"
    fi
done

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK Delete existing duplicate data]"

# Check if there is an quay-app.service
 if  -f /etc/systemd/system/quay-pod.service ]; then
    echo "info: Mirror registry detected, starting uninstall]"
    if ${REGISTRY_INSTALL_DIR}/mirror-registry uninstall -v --autoApprove --quayRoot "${REGISTRY_INSTALL_DIR}" > /dev/null 2>&1; then
        echo "ok: Uninstall the mirror registry]"
    else
        echo "failed: Uninstall the mirror registry]"
    fi
else
    echo "skipping: Uninstall the mirror registry]"
fi

# Delete existing duplicate data
rm -rf "/etc/pki/ca-trust/source/anchors/${REGISTRY_HOST_NAME}.ca.pem" >/dev/null 2>&1
rm -rf "${REGISTRY_INSTALL_DIR}" >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK Install mirror registry]"

# Create installation directory
sudo mkdir -p ${REGISTRY_INSTALL_DIR}
sudo mkdir -p ${REGISTRY_INSTALL_DIR}/quay-storage
sudo mkdir -p ${REGISTRY_INSTALL_DIR}/sqlite-storage
sudo chmod -R 777 ${REGISTRY_INSTALL_DIR}
run_command "Create the ${REGISTRY_INSTALL_DIR} directory and modify its permissions]"

# Download mirror-registry
# wget -P ${REGISTRY_INSTALL_DIR} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz >/dev/null 2>&1
sudo wget -O ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz >/dev/null 2>&1
run_command "Download mirror-registry package]"

# Extract the downloaded mirror-registry package
cd ${REGISTRY_INSTALL_DIR}
sudo tar xvf ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_DIR}/ >/dev/null 2>&1
run_command "Extract the mirror-registry package]"


# Add registry entry to /etc/hosts
if ! grep -q "$REGISTRY_HOST_NAME" /etc/hosts; then
  echo "# Add registry entry to /etc/hosts" | sudo tee -a /etc/hosts > /dev/null
  echo "$REGISTRY_HOST_IP $REGISTRY_HOST_NAME" | sudo tee -a /etc/hosts > /dev/null
  echo "ok: Add registry entry to /etc/hosts]"
else
  echo "skipping: Registry entry already exists in /etc/hosts]"
fi

echo "ok: Start installing mirror-registry...]"
# echo "ok: Generate mirror-registry log: ${REGISTRY_INSTALL_DIR}/mirror-registry.log]"

# Install mirror-registry
sudo ${REGISTRY_INSTALL_DIR}/mirror-registry install -v \
     --quayHostname ${REGISTRY_HOST_NAME} \
     --quayRoot ${REGISTRY_INSTALL_DIR} \
     --quayStorage ${REGISTRY_INSTALL_DIR}/quay-storage \
     --sqliteStorage ${REGISTRY_INSTALL_DIR}/sqlite-storage \
     --initUser ${REGISTRY_ID} \
     --initPassword ${REGISTRY_PW}
run_command "Installation of mirror registry completed]"

progress_started=false
while true; do
    # Get the status of all pods
    output=$(sudo podman pod ps | awk 'NR>1' | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b3\b)')
    
    # Check if the pod is not in the "Running" state
    if  -z "$output" ]; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: Waiting for quay pod to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 10
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: Quay pod is in 'running' state]"
        break
    fi
done

# Copy the rootCA certificate to the trusted source
sudo cp ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_HOST_NAME}.ca.pem
run_command "Copy the rootca certificate to the trusted source: /etc/pki/ca-trust/source/anchors/${REGISTRY_HOST_NAME}.ca.pem]"

# Trust the rootCA certificate
sudo update-ca-trust
run_command "Trust the rootCA certificate]"

# Delete the tar package generated during installation
sudo rm -rf pause.tar postgres.tar quay.tar redis.tar >/dev/null 2>&1
run_command "Delete the tar package: pause.tar postgres.tar quay.tar redis.tar]"

# loggin registry
sudo podman login -u ${REGISTRY_ID} -p ${REGISTRY_PW} https://${REGISTRY_HOST_NAME}:8443 >/dev/null 2>&1
run_command  "Login registry https://${REGISTRY_HOST_NAME}:8443]"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK Configuring additional trust stores for image registry access]"

# Check if the registry-cas field exists
REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if  -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-config --from-file=${REGISTRY_HOST_NAME}..8443=/etc/pki/ca-trust/source/anchors/${REGISTRY_HOST_NAME}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command  "Create a configmap containing the registry CA certificate: registry-config]"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null 2>&1
  run_command  "Trust the registry-config configmap]"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-cas --from-file=${REGISTRY_HOST_NAME}..8443=/etc/pki/ca-trust/source/anchors/${REGISTRY_HOST_NAME}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command  "Create a configmap containing the registry CA certificate: registry-cas]"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge >/dev/null 2>&1
  run_command  "Trust the registry-cas configmap]"
fi

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK Update the global pull-secret]"

sudo rm -rf pull-secret >/dev/null 2>&1
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret
run_command  "Export pull-secret file]"

podman login -u $REGISTRY_ID -p $REGISTRY_PW --authfile pull-secret ${REGISTRY_HOST_NAME}:8443 >/dev/null 2>&1
run_command  "Authentication identity information to the pull-secret file]"

oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret >/dev/null 2>&1
run_command  "Update pull-secret for the cluster]"

sudo rm -rf pull-secret >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK Checking the cluster status]"

# Check cluster operator status
progress_started=false
while true; do
    operator_status=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    
    if echo "$operator_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: Waiting for all cluster operators to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: All cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
progress_started=false
while true; do
    mcp_status=$(oc get mcp --no-headers | awk '{print $3, $4, $5}')

    if echo "$mcp_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: Waiting for all mcps to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All mcp have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo
