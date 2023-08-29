#!/bin/bash

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=45  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

######

# Task: Install infrastructure rpm
PRINT_TASK "[TASK: Mirror ocp image to mirror-registry]"

echo ====== Registry login authentication file ======
# Login to the registry
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET}" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000"

# Check the return code of the podman login command
if [ $? -eq 0 ]; then
    echo "Successfully logged in to the registry."
else
    echo "Failed to log in to the registry."
fi

echo ====== Mirror the ocp image to the registry ======
# Execute oc adm release mirror command
oc adm -a ${{PULL_SECRET}} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY} \
  --to-release-image=${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} 
  
# Check the return code of the oc adm release mirror command
if [ $? -eq 0 ]; then
    echo "Successfully mirrored release."
else
    echo "Failed to mirror release."
fi
sudo sleep 10

curl -u ${REGISTRY_ID}:${REGISTRY_PW} -k https://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/v2/_catalog
