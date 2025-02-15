#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export REGISTRY_DOMAIN_NAME="mirror.registry.example.com"
export REGISTRY_ID="admin"
export REGISTRY_PW="password"
export REGISTRY_INSTALL_PATH="/opt/quay-install"

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
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}
# ====================================================

# === Task: Install infrastructure rpm ===
PRINT_TASK "[TASK: Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "podman")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
sudo dnf install -y $package_list &>/dev/null

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [installed $package package]"
    else
        echo "failed: [installed $package package]"
    fi
done


# Add an empty line after the task
echo
# ====================================================


# === Task: Delete existing duplicate data ===
PRINT_TASK "[TASK: Delete existing duplicate data]"

# Check if there is an active mirror registry pod
if sudo podman pod ps | grep -E 'quay-pod.*Running' >/dev/null; then
    # If the mirror registry pod is running, uninstall it
    ${REGISTRY_INSTALL_PATH}/mirror-registry uninstall --autoApprove --quayRoot ${REGISTRY_INSTALL_PATH} &>/dev/null
    # Check the exit status of the uninstall command
    if [ $? -eq 0 ]; then
        echo "ok: [uninstall the mirror registry]"
    else
        echo "failed: [uninstall the mirror registry]"
    fi
else
    echo "skipping: [no active mirror registry pod found]"
fi

# Delete existing duplicate data
files=(
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem"
    "${REGISTRY_INSTALL_PATH}"
)

for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        sudo rm -rf "$file" &>/dev/null
        if [ $? -eq 0 ]; then
            echo "ok: [delete existing duplicate data: $file]"
        else
            echo "failed: [delete existing duplicate data: $file]"
        fi
    else
        echo "skipping: [no duplicate data: $file]"
    fi
done

# Add an empty line after the task
echo
# ====================================================



# === Task: Install mirror registry ===
PRINT_TASK "[TASK: Install mirror registry]"

# Create installation directory
sudo mkdir -p ${REGISTRY_INSTALL_PATH}
sudo mkdir -p ${REGISTRY_INSTALL_PATH}/quay-storage
sudo mkdir -p ${REGISTRY_INSTALL_PATH}/sqlite-storage
sudo chmod -R 777 ${REGISTRY_INSTALL_PATH}
run_command "[create ${REGISTRY_INSTALL_PATH} directory]"

# Download mirror-registry
# wget -P ${REGISTRY_INSTALL_PATH} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz &> /dev/null
sudo wget -O ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz &> /dev/null
run_command "[download mirror-registry package]"

# Extract the downloaded mirror-registry package
sudo tar xvf ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_PATH}/ &> /dev/null
run_command "[extract the mirror-registry package]"

echo "ok: [Start installing mirror-registry...]"
# echo "ok: [Generate mirror-registry log: ${REGISTRY_INSTALL_PATH}/mirror-registry.log]"

# Install mirror-registry
sudo ${REGISTRY_INSTALL_PATH}/mirror-registry install -v \
     --quayHostname ${REGISTRY_DOMAIN_NAME} \
     --quayRoot ${REGISTRY_INSTALL_PATH} \
     --quayStorage ${REGISTRY_INSTALL_PATH}/quay-storage \
     --sqliteStorage ${REGISTRY_INSTALL_PATH}/sqlite-storage \
     --initUser ${REGISTRY_ID} \
     --initPassword ${REGISTRY_PW}
run_command "[Installation of mirror registry completed]"

sleep 60

# Get the status and number of containers for quay-pod
# podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b3\b)' &>/dev/null
# run_command "[Mirror Registry Pod is running]"

# Copy the rootCA certificate to the trusted source
sudo cp ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem
run_command "[Copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem]"

# Trust the rootCA certificate
sudo update-ca-trust
run_command "[Trust the rootCA certificate]"

# Delete the tar package generated during installation
sudo rm -rf pause.tar postgres.tar quay.tar redis.tar &>/dev/null
run_command "[Delete the tar package: pause.tar postgres.tar quay.tar redis.tar]"

# loggin registry
sudo podman login -u ${REGISTRY_ID} -p ${REGISTRY_PW} https://${REGISTRY_DOMAIN_NAME}:8443 &>/dev/null
run_command  "[Login registry https://${REGISTRY_DOMAIN_NAME}:8443]"

# Add an empty line after the task
echo
# ====================================================


# Task: Update the global pull-secret
PRINT_TASK "[TASK: Update the global pull-secret]"

rm -rf pull-secret &>/dev/null
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret &>/dev/null
run_command  "[Export pull-secret file]"

podman login --authfile pull-secret ${REGISTRY_DOMAIN_NAME}:8443 &>/dev/null
run_command  "[Authentication identity information to the pull-secret file]"

oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret &>/dev/null
run_command  "[Update global pull-secret]"


# Add an empty line after the task
echo
# ====================================================

# Task: Configuring additional trust stores for image registry access
PRINT_TASK "[TASK: Configuring additional trust stores for image registry access]"

# Check if the registry-cas field exists
REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if [[ -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  sudo oc create configmap registry-config --from-file=${REGISTRY_DOMAIN_NAME}..8443=/etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem -n openshift-config &> /dev/null
  run_command  "[Create a configmap containing the registry CA certificate: registry-config]"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge &> /dev/null
  run_command  "[Trust the registry-config configmap]"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  sudo oc create configmap registry-cas --from-file=${REGISTRY_DOMAIN_NAME}..8443=/etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem -n openshift-config &> /dev/null
  run_command  "[Create a configmap containing the registry CA certificate: registry-cas]"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge &> /dev/null
  run_command  "[Trust the registry-cas configmap]"
fi

# Add an empty line after the task
echo
# ====================================================


# === Task: Checking the cluster status ===
PRINT_TASK "[TASK: Checking the cluster status]"

# Print task title
PRINT_TASK "[TASK: Check status]"

# Check cluster operator status
progress_started=false
while true; do
    operator_status=$(sudo /usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    
    if echo "$operator_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
progress_started=false

while true; do
    mcp_status=$(sudo /usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get mcp --no-headers | awk '{print $3, $4, $5}')

    if echo "$mcp_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all mcps to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all mcp have reached the expected state]"
        break
    fi
done

echo
# ====================================================
