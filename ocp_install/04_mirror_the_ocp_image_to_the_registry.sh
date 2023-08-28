#!/bin/bash
#######################################################

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
