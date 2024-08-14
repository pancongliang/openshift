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

# Task: Mirror ocp image to mirror-registry
PRINT_TASK "[TASK: Mirror ocp image to mirror-registry]"

# Prompt for pull-secret
read -p "Please input the pull secret string from https://cloud.redhat.com/openshift/install/pull-secret:" REDHAT_PULL_SECRET

# Create a temporary file to store the pull secret
PULL_SECRET=$(mktemp -p /tmp)
echo "${REDHAT_PULL_SECRET}" > "${PULL_SECRET}"
run_command "[create a temporary file to store the pull secret]"

# Login to the registry
rm -rf $XDG_RUNTIME_DIR/containers
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" &>/dev/null
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
if [ $? -eq 0 ]; then
    echo "ok: [remove temporary pull-secret file]"
else
    echo "failed: [remove temporary pull-secret file]"
fi

# Add an empty line after the task
echo
# ====================================================
