#!/bin/bash

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
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

# ====================================================


# Task: Prepare the pull-secret
PRINT_TASK "[TASK: Prepare the pull-secret]"

# Prompt for pull-secret
read -p "Please input the pull secret string from https://cloud.redhat.com/openshift/install/pull-secret:" REDHAT_PULL_SECRET

# Create a temporary file to store the pull secret
PULL_SECRET=$(mktemp -p /tmp)
echo "${REDHAT_PULL_SECRET}" > "${PULL_SECRET}"
run_command "[create a temporary file to store the pull secret]"

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
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem"
    "${REGISTRY_INSTALL_PATH}"
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

# Create installation directory
mkdir -p ${REGISTRY_INSTALL_PATH}
run_command "[create ${REGISTRY_INSTALL_PATH} directory]"

# Download mirror-registry
wget -P ${REGISTRY_INSTALL_PATH} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz &> /dev/null
run_command "[download mirror-registry package]"

# Extract the downloaded mirror-registry package
tar xvf ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_PATH}/ &> /dev/null
run_command "[extract the mirror-registry package]"

# Install mirror-registry
${REGISTRY_INSTALL_PATH}/mirror-registry install \
     --quayHostname ${REGISTRY_HOSTNAME}.${BASE_DOMAIN} \
     --quayRoot ${REGISTRY_INSTALL_PATH} \
     --quayStorage ${REGISTRY_INSTALL_PATH}/quay-storage \
     --pgStorage ${REGISTRY_INSTALL_PATH}/pg-storage \
     --initUser ${REGISTRY_ID} --initPassword ${REGISTRY_PW} 
run_command "[installing mirror-registry...]"

# Get the status and number of containers for quay-pod
podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)' &>/dev/null
run_command "[mirror registry Pod is running]"

# Restart quay-pod.service/quay-app.service
systemctl restart quay-pod.service quay-app.service
run_command "[restart quay-pod.service quay-app.service]"

sleep 120

# Copy the rootCA certificate to the trusted source
cp ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem
run_command "[copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem]"

# Trust the rootCA certificate
update-ca-trust
run_command "[trust the rootCA certificate]"

# Delete the tar package generated during installation
rm -rf pause.tar postgres.tar quay.tar redis.tar &>/dev/null
run_command "[Delete the tar package: pause.tar postgres.tar quay.tar redis.tar]"

# Add an empty line after the task
echo
# ====================================================

# Task: Mirror ocp image to mirror-registry
PRINT_TASK "[TASK: Mirror ocp image to mirror-registry]"

# Login to the registry
rm -rf $XDG_RUNTIME_DIR/containers
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" &>/dev/null
run_command  "[login registry https://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443]"

podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET}" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" &>/dev/null
run_command "[add authentication information to pull-secret]"

# Save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json
cat ${PULL_SECRET} | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
run_command "[save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json]"

# Create ImageSetConfiguration directory
rm -rf ${IMAGE_SET_CONFIGURATION_PATH} &>/dev/null
mkdir ${IMAGE_SET_CONFIGURATION_PATH} &>/dev/null
run_command "[create ${IMAGE_SET_CONFIGURATION_PATH} directory]"

# Create ImageSetConfiguration file
cat << EOF > ${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
 registry:
   imageURL: ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/mirror/metadata
   skipTLS: false
mirror:
  platform:
    channels:
      - name: stable-${OCP_RELEASE_CHANNEL}
        minVersion: ${OCP_RELEASE_VERSION}
        maxVersion: ${OCP_RELEASE_VERSION}
        shortestPath: true
EOF
run_command "[create ${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml file]"

# Mirroring ocp release image
oc mirror --config=${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml docker://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443 --dest-skip-tls
run_command "[mirroring ocp ${OCP_RELEASE_VERSION} release image]"

# Remove the temporary file
rm -f "${PULL_SECRET}"
run_command "[remove temporary pull-secret file]"

# Add an empty line after the task
echo
# ====================================================