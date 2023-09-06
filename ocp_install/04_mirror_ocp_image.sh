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



# Task: Mirror ocp image to mirror-registry
PRINT_TASK "[TASK: Mirror ocp image to mirror-registry]"

# Login to the registry
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET}" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" &>/dev/null

# Check the return code of the podman login command
if [ $? -eq 0 ]; then
    echo "ok: [add authentication information to pull-secret]"
else
    echo "failed: [add authentication information to pull-secret]"
fi

# Execute oc adm release mirror command
oc adm -a ${PULL_SECRET} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/${LOCAL_REPOSITORY} \
  --to-release-image=${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}
  
# Check the return code of the oc adm release mirror command
if [ $? -eq 0 ]; then
    echo "ok: [mirror openshift image to registry]"
else
    echo "failed: [mirror openshift image to registry]"
fi

