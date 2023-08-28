#!/bin/bash
echo ====== Generate a defined install-config file ======
# Define variables
REGISTRY_CA_FILE="${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt"

# Backup and format the registry CA certificate
cp "${REGISTRY_CA_FILE}" "${REGISTRY_CA_FILE.bak}"
sed -i 's/^/  /' "${REGISTRY_CA_FILE.bak}"

# Define variables
export REGISTRY_CA="$(cat ${REGISTRY_CA_FILE.bak})"
export REGISTRY_ID_PW=$(echo -n "${REGISTRY_ID}:${REGISTRY_PW}" | base64)
export ID_RSA_PUB=$(cat "${ID_RSA_PUB_FILE}")

# Generate a defined install-config file
rm -rf ${HTTPD_PATH}/install-config.yaml
cat << EOF > $HTTPD_PATH/install-config.yaml 
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 0 
controlPlane: 
  hyperthreading: Enabled 
  name: master
  replicas: 3 
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: ${POD_CIDR}
    hostPrefix: ${HOST_PREFIX}
  networkType: ${NETWORK_TYPE}
  serviceNetwork: 
  - ${SERVICE_CIDR}
platform:
  none: {} 
fips: false
pullSecret: '{"auths":{"${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000": {"auth": "${REGISTRY_ID_PW}","email": "xxx@xxx.com"}}}' 
sshKey: '${ID_RSA_PUB}'
additionalTrustBundle: | 
${REGISTRY_CA}
imageContentSources:
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

# Delete certificate
rm -rf "$REGISTRY_CA_FILE.bak"

echo "Generated install-config files."

echo ====== Generate a manifests ======
# Create installation directory
rm -rf "${IGNITION_PATH}"
mkdir -p "${IGNITION_PATH}"

# Copy install-config.yaml to installation directory
cp "$HTTPD_PATH/install-config.yaml" "${IGNITION_PATH}"

# Generate manifests
openshift-install create manifests --dir "${IGNITION_PATH}"


echo ====== Disable master node scheduling ======
# Verify the initial value
initial_value=$(grep "mastersSchedulable: true" "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml")
if [ -n "$initial_value" ]; then
    echo "Initial value found: $initial_value"    
    # Modify the file using sed
    sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml"

    # Verify the modification
    modified_value=$(grep "mastersSchedulable: false" "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml")
    if [ -n "$modified_value" ]; then
        echo "Master node scheduling disabled successful: $modified_value"
    else
        echo "Master node scheduling disabled failed."
    fi
fi

echo ====== Generate a ignition file ======
# Generate and modify ignition configuration files
openshift-install create ignition-configs --dir "${IGNITION_PATH}"


echo ====== Generate an ignition file containing the node hostname ======
# Array of hostnames to process
hosts=("$BOOTSTRAP_HOSTNAME" "$MASTER01_HOSTNAME" "$MASTER02_HOSTNAME" "$MASTER03_HOSTNAME" "$WORKER01_HOSTNAME" "$WORKER02_HOSTNAME")

# Copy ignition files with modified names
for host in "${hosts[@]}"; do
    cp "${IGNITION_PATH}/bootstrap.ign" "${IGNITION_PATH}/${host}bk.ign"
    cp "${IGNITION_PATH}/master.ign" "${IGNITION_PATH}/${host}.ign"
    cp "${IGNITION_PATH}/worker.ign" "${IGNITION_PATH}/${host}.ign"
done

# Modify ignition files
for host in "${hosts[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:'"${host}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},"mode": 420}]}}/' "${IGNITION_PATH}/${host}.ign"
done

# Verify if the ignition files were generated successfully
for host in "${hosts[@]}"; do
    if [ ! -f "${IGNITION_PATH}/${host}.ign" ]; then
        echo "Failed to generate ignition file for ${host}"
        exit 1
    fi
done
echo "Successfully generated ignition files containing node hostnames"

echo ====== Set permissions for ignition files ======
# Set permissions for ignition files
chmod a+r "${IGNITION_PATH}"/*.ign

echo "====== Change permissions of ignition files ======"
# Change permissions of ignition files
chmod a+r "${IGNITION_PATH}"/*.ign

# Verify if permissions were changed successfully
ignition_files=("${IGNITION_PATH}"/*.ign)
success=true
for file in "${ignition_files[@]}"; do
    if [ ! -r "$file" ]; then
        echo "Failed to change permissions for $file"
        success=false
        break
    fi
done

if [ "$success" = true ]; then
    echo "Successfully changed permissions of ignition files"
else
    echo "Failed to change permissions of ignition files"
fi

echo "====== Generated Ignition files ======"
# Display generated files
ls -l "${IGNITION_PATH}"/*.ign
