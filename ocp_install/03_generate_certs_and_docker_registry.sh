#!/bin/bash
# === Function to print a task with uniform length ===
# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}
# ====================================================


# === Task: Prompt for required variables ===
export REGISTRY_DOMAIN="mirror.registry.example.com"
export USER="root"
export PASSWD="password"                      # 8 characters or more
export REGISTRY_INSTALL_PATH="/var/registry"

# === Task: Delete existing duplicate data ===
PRINT_TASK "[TASK: Delete existing duplicate data]"

# Check if there is an active mirror registry pod
if podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)' >/dev/null; then
    # If the mirror registry pod is running, uninstall it
    ${REGISTRY_INSTALL_PATH}/mirror-registry uninstall --autoApprove --quayRoot ${REGISTRY_INSTALL_PATH} &>/dev/null   
    # Check the exit status of the uninstall command
    if [ $? -eq 0 ]; then
        echo "ok: [uninstall the mirror registry]"
    else
        echo "failed: [uninstall the mirror registry]"
    fi
else
    echo "skipping: [no active mirror registry pod found. skipping uninstallation]"
fi

# Delete existing duplicate data
files=(
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN}.ca.pem"
    "${REGISTRY_INSTALL_PATH}"
)
for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        rm -rf "$file" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "ok: [delete existing duplicate data: $file]"
        fi
    else
        echo "skipping: [delete existing duplicate data]"
    fi
done

# === Task: Install mirror registry ===
PRINT_TASK "[TASK: Install mirror registry]"

# Function to check command success and display appropriate message
mirror_registry_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

# Create installation directory
mkdir -p ${REGISTRY_INSTALL_PATH}
mirror_registry_command "[create installation directory]"
sleep 3

# Download mirror-registry
wget -P ${REGISTRY_INSTALL_PATH} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz &> /dev/null
mirror_registry_command "[download mirror-registry package]"

# Extract the downloaded mirror-registry package
tar xvf ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_PATH}/ &> /dev/null
mirror_registry_command "[extract the downloaded mirror-registry package]"

# Install mirror-registry
cd ${REGISTRY_INSTALL_PATH}
${REGISTRY_INSTALL_PATH}/mirror-registry install -v \
     --quayHostname ${REGISTRY_DOMAIN} --quayRoot ${REGISTRY_INSTALL_PATH}/ \
     --initUser ${USER} --initPassword ${PASSWD} &>/dev/null
mirror_registry_command "[installing mirror-registry...]"

# Wait for the installation to complete
cd ~
sleep 6

# Get the status and number of containers for quay-pod
podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)'
mirror_registry_command "[mirror registry Pod is running]"

# Copy the rootCA certificate to the trusted source
cp ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN}.ca.pem
mirror_registry_command "[copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN}.ca.pem]"

# Trust the rootCA certificate
update-ca-trust
mirror_registry_command "[trust the rootCA certificate]"

# loggin registry
podman login -u ${USER} -p ${PASSWD} https://${REGISTRY_DOMAIN}:8443 &>/dev/null
mirror_registry_command  "[test login https://${REGISTRY_DOMAIN}:8443]"
