#!/bin/bash
echo ====== Generate a defined install-config file ======
# Define variables
REGISTRY_CA_FILE="/etc/crts/$REGISTRY_HOSTNAME.$BASE_DOMAIN.ca.crt"

# Backup and format the registry CA certificate
cp "$REGISTRY_CA_FILE" "$REGISTRY_CA_FILE.bak"
sed -i 's/^/  /' "$REGISTRY_CA_FILE.bak"

# Define variables
export REGISTRY_CA="$(cat $REGISTRY_CA_FILE.bak)"
export REGISTRY_ID_PW=$(echo -n "$REGISTRY_ID:$REGISTRY_PW" | base64)
export ID_RSA_PUB=$(cat "$ID_RSA_PUB_FILE")

# Generate a defined install-config file
cat << EOF > $HTTPD_PATH/install-config.yaml 
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 0 
controlPlane: 
  hyperthreading: Enabled 
  name: master
  replicas: 3 
metadata:
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: $POD_CIDR
    hostPrefix: $HOST_PREFIX
  networkType: $NETWORK_TYPE
  serviceNetwork: 
  - $SERVICE_CIDR
platform:
  none: {} 
fips: false
pullSecret: '{"auths":{"${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000": {"auth": "$REGISTRY_ID_PW","email": "xxx@xxx.com"}}}' 
sshKey: '$ID_RSA_PUB'
additionalTrustBundle: | 
$REGISTRY_CA
imageContentSources:
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

echo "Generated install-config files."

echo ====== Generate a ignition file ======
# Create installation directory
mkdir -p "$OCP_INSTALL_DIR"

# Copy install-config.yaml to installation directory
cp "$HTTPD_PATH/install-config.yaml" "$OCP_INSTALL_DIR"

# Generate manifests
openshift-install create manifests --dir "$OCP_INSTALL_DIR"
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "$OCP_INSTALL_DIR/manifests/cluster-scheduler-02-config.yml"

# Generate and modify ignition configuration files
openshift-install create ignition-configs --dir "$OCP_INSTALL_DIR"
echo "Generated Ignition files:"


echo ====== Generate an ignition file containing the hostname ======
# Function to modify ignition file
modify_ignition() {
    local hostname="$1"
    local source="$2"
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:'"$hostname.$CLUSTER_NAME.$BASE_DOMAIN"'"},"mode":420}]}}/' "$OCP_INSTALL_DIR/$source.ign"
}

# Modify ignition files for different nodes
modify_ignition "$BOOTSTRAP_HOSTNAME" "bootstrap"
modify_ignition "$MASTER01_HOSTNAME" "master"
modify_ignition "$MASTER02_HOSTNAME" "master"
modify_ignition "$MASTER03_HOSTNAME" "master"
modify_ignition "$WORKER01_HOSTNAME" "worker"
modify_ignition "$WORKER02_HOSTNAME" "worker"

# Set permissions for ignition files
chmod a+r "$OCP_INSTALL_DIR"/*.ign

# Display generated files
echo "Generated Ignition files:"
ls -l "$OCP_INSTALL_DIR"/*.ign
