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


# Task: Mirror ocp image to mirror-registry
PRINT_TASK "[TASK: Mirror ocp image to mirror-registry]"

# Prompt for pull-secret
read -p "Please input the pull secret string from https://cloud.redhat.com/openshift/install/pull-secret:" REDHAT_PULL_SECRET

# Create a temporary file to store the pull secret
PULL_SECRET=$(mktemp -p /tmp)
echo "${REDHAT_PULL_SECRET}" > "${PULL_SECRET}"

# Login to the registry
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET}" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" &>/dev/null

# Check the return code of the podman login command
if [ $? -eq 0 ]; then
    echo "ok: [add authentication information to pull-secret]"
else
    echo "failed: [add authentication information to pull-secret]"
fi

#Save the file either as ~/.docker/config.json or $XDG_RUNTIME_DIR/containers/auth.json
cat ${PULL_SECRET} | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json

# Create a ImageSetConfiguration file
cat > imageset-config.yaml << EOF
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
 registry:
   imageURL: ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/mirror/metadata
mirror:
  platform:
    channels:
      - name: stable-4.11
        minVersion: 4.11.20
        maxVersion: 4.11.20
        shortestPath: true
EOF

# Check if ImageSetConfiguration file exists
if [ $? -eq 0 ]; then
    echo "ok: [Create a ImageSetConfiguration file]"
else
    echo "failed: [Create a ImageSetConfiguration file]"
fi

# Start mirroring ocp release image
oc mirror --config=./imageset-config.yaml docker://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443 --dest-skip-tls

# Check whether the ocp release image exists
podman search ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/openshift/release-images --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret
if [ $? -eq 0 ]; then
    echo "ok: [Check whether the ocp release image exists]"
else
    echo "failed: [Check whether the ocp release image exists]"
fi


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
