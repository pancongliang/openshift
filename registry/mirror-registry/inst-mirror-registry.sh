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


# === Task: Install infrastructure rpm ===
PRINT_TASK "[TASK: Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "vim" "podman" "bash-completion" "jq")

# Install the RPM package and return the execution result
for package in "${packages[@]}"; do
    sudo yum install -y "$package" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [Install $package package]"
    else
        echo "failed: [Install $package package]"
    fi
done

# Add an empty line after the task
echo
# ====================================================


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
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem"
    "${REGISTRY_INSTALL_PATH}"
)

for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        rm -rf "$file" &>/dev/null
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
mkdir -p ${REGISTRY_INSTALL_PATH}
mkdir -p ${REGISTRY_INSTALL_PATH}/quay-storage
mkdir -p ${REGISTRY_INSTALL_PATH}/sqlite-storage
chmod -R 777 ${REGISTRY_INSTALL_PATH}
run_command "[create ${REGISTRY_INSTALL_PATH} directory]"

# Download mirror-registry
# wget -P ${REGISTRY_INSTALL_PATH} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz &> /dev/null
wget -O ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz &> /dev/null
run_command "[download mirror-registry package]"

# Extract the downloaded mirror-registry package
tar xvf ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_PATH}/ &> /dev/null
run_command "[extract the mirror-registry package]"

# Install mirror-registry
${REGISTRY_INSTALL_PATH}/mirror-registry install \
     --quayHostname ${REGISTRY_DOMAIN_NAME} \
     --quayRoot ${REGISTRY_INSTALL_PATH} \
     --quayStorage ${REGISTRY_INSTALL_PATH}/quay-storage \
     --sqliteStorage ${REGISTRY_INSTALL_PATH}/sqlite-storage \
     --initUser ${REGISTRY_ID} \
     --initPassword ${REGISTRY_PW}
run_command "[Installation of mirror registry completed]"

# Get the status and number of containers for quay-pod
podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)' &>/dev/null
run_command "[mirror registry Pod is running]"

# Copy the rootCA certificate to the trusted source
cp ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem
run_command "[copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.pem]"

# Trust the rootCA certificate
update-ca-trust
run_command "[trust the rootCA certificate]"

# Delete the tar package generated during installation
rm -rf pause.tar postgres.tar quay.tar redis.tar &>/dev/null
run_command "[Delete the tar package: pause.tar postgres.tar quay.tar redis.tar]"

# loggin registry
podman login -u ${REGISTRY_ID} -p ${REGISTRY_PW} https://${REGISTRY_DOMAIN_NAME}:8443 &>/dev/null
run_command  "[login registry https://${REGISTRY_DOMAIN_NAME}:8443]"

# Add an empty line after the task
echo
# ====================================================
