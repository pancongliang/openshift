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


# === Task: Delete existing duplicate data ===
PRINT_TASK "[TASK: Delete existing duplicate data]"

# Check if there is an active mirror registry pod
if podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)' >/dev/null; then
    # If the mirror registry pod is running, uninstall it
    ${REGISTRY_INSTALL_DIR}/mirror-registry uninstall --autoApprove --quayRoot ${REGISTRY_INSTALL_DIR} &>/dev/null
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
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem"
    "${REGISTRY_INSTALL_DIR}"
)
for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        rm -rf "$file" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "ok: [delete existing duplicate data: $file]"
        fi
    fi
done

# Add an empty line after the task
echo
# ====================================================



# === Task: Install mirror registry ===
PRINT_TASK "[TASK: Install mirror registry]"

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

# Create installation directory
mkdir -p ${REGISTRY_INSTALL_DIR}
run_command "[create ${REGISTRY_INSTALL_DIR} directory]"

# Download mirror-registry
wget -P ${REGISTRY_INSTALL_DIR} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz &> /dev/null
run_command "[download mirror-registry package]"

# Extract the downloaded mirror-registry package
tar xvf ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_DIR}/ &> /dev/null
run_command "[extract the mirror-registry package]"

# Install mirror-registry
${REGISTRY_INSTALL_DIR}/mirror-registry install -v \
     --quayHostname ${REGISTRY_HOSTNAME}.${BASE_DOMAIN} \
     --quayRoot ${REGISTRY_INSTALL_DIR} \
     --quayStorage ${REGISTRY_INSTALL_DIR}/quay-storage \
     --pgStorage ${REGISTRY_INSTALL_DIR}/pg-storage \
     --initUser ${REGISTRY_ID} --initPassword ${REGISTRY_PW} 
run_command "[installing mirror-registry...]"

# Get the status and number of containers for quay-pod
podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)' &>/dev/null
run_command "[mirror registry Pod is running]"

# Copy the rootCA certificate to the trusted source
cp ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem
run_command "[copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem]"

# Trust the rootCA certificate
update-ca-trust
run_command "[trust the rootCA certificate]"

# Delete the tar package generated during installation
rm -rf pause.tar postgres.tar quay.tar redis.tar &>/dev/null
run_command "[Delete the tar package: pause.tar postgres.tar quay.tar redis.tar]"

# loggin registry
podman login -u ${REGISTRY_ID} -p ${REGISTRY_PW} https://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443 &>/dev/null
run_command  "[login registry https://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443]"

# Add an empty line after the task
echo
# ====================================================
