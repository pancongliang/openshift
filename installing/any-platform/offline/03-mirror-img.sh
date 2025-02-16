#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

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
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 1:
PRINT_TASK "TASK [Applying environment variables]"

source 01-set-params.sh
run_command "[applying environment variables]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Mirror ocp image to mirror-registry]"

# Login to the registry
rm -rf $XDG_RUNTIME_DIR/containers
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" >/dev/null 2>&1
run_command  "[login registry https://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443]"

podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET_FILE}" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" >/dev/null 2>&1
run_command "[add authentication information to pull-secret]"

# Save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json
cat ${PULL_SECRET_FILE} | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
run_command "[save the pull-secret file either as $XDG_RUNTIME_DIR/containers/auth.json]"

# Create ImageSetConfiguration directory
rm -rf ${IMAGE_SET_CONF_PATH} >/dev/null 2>&1
mkdir ${IMAGE_SET_CONF_PATH} >/dev/null 2>&1
run_command "[create ${IMAGE_SET_CONF_PATH} directory]"

# Create ImageSetConfiguration file
cat << EOF > ${IMAGE_SET_CONF_PATH}/imageset-config.yaml
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
run_command "[create ${IMAGE_SET_CONF_PATH}/imageset-config.yaml file]"

# Mirroring ocp release image
oc mirror --config=${IMAGE_SET_CONF_PATH}/imageset-config.yaml docker://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443 --dest-skip-tls
run_command "[mirroring ocp ${OCP_RELEASE_VERSION} release image]"

# Remove the temporary file
# rm -f "${PULL_SECRET_FILE}"
# run_command "[remove temporary pull-secret file]"

# Add an empty line after the task
echo
