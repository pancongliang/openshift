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



# === Task: Install infrastructure rpm ===
PRINT_TASK "[TASK: Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "zip" "vim" "podman" "bash-completion" "jq")

# Install the RPM package and return the execution result
for package in "${packages[@]}"; do
    sudo yum install -y "$package" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [install $package package]"
    else
        echo "failed: [install $package package]"
    fi
done

# Add an empty line after the task
echo
# ====================================================


# === Task: Install openshift tool ===
PRINT_TASK "[TASK: Install openshift tool]"

# Step 1: Delete openshift tool
# ----------------------------------------------------
# Delete openshift tool
files=(
    "/usr/local/bin/kubectl"
    "/usr/local/bin/oc"
    "/usr/local/bin/oc-mirror"
    "/usr/local/bin/openshift-install"
    "/usr/local/bin/openshift-install-linux.tar.gz"
    "/usr/local/bin/openshift-client-linux.tar.gz"
    "/usr/local/bin/oc-mirror.tar.gz"
)
for file in "${files[@]}"; do
    sudo rm -rf $file 2>/dev/null
done

# Step 2: Function to download and install tool
# ----------------------------------------------------
# Function to download and install .tar.gz tools
install_tar_gz() {
    local tool_name="$1"
    local tool_url="$2"  
    # Download the tool
    sudo wget -P "/usr/local/bin" "$tool_url" &> /dev/null    
    if [ $? -eq 0 ]; then
        echo "ok: [download $tool_name tool]"        
        # Extract the downloaded tool
        sudo tar xvf "/usr/local/bin/$(basename $tool_url)" -C "/usr/local/bin/" &> /dev/null
        # Remove the downloaded .tar.gz file
        sudo rm -f "/usr/local/bin/$(basename $tool_url)"
    else
        echo "failed: [download $tool_name tool]"
    fi
}

# Install .tar.gz tools
install_tar_gz "openshift-install" "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE_VERSION}/openshift-install-linux.tar.gz"
install_tar_gz "openshift-client" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz"
install_tar_gz "oc-mirror" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"


# === Task: Delete existing duplicate data ===
PRINT_TASK "[TASK: Delete existing duplicate data]"

# Check if there is an active mirror registry pod
if podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)' >/dev/null; then
    # If the mirror registry pod is running, uninstall it
    sudo ${REGISTRY_INSTALL_PATH}/mirror-registry uninstall --autoApprove --quayRoot ${REGISTRY_INSTALL_PATH} &>/dev/null
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
        sudo rm -rf "$file" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "ok: [delete existing duplicate data: $file]"
        fi
    fi
done

# Add an empty line after the task
echo
# ====================================================

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

# === Task: Install mirror registry ===
PRINT_TASK "[TASK: Install mirror registry]"

sudo mkdir -p ${REGISTRY_INSTALL_PATH}
run_command "[create ${REGISTRY_INSTALL_PATH} directory]"

# Download mirror-registry
sudo wget -P ${REGISTRY_INSTALL_PATH} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz &> /dev/null
run_command "[download mirror-registry package]"

# Extract the downloaded mirror-registry package
sudo tar xvf ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_PATH}/ &> /dev/null
run_command "[extract the mirror-registry package]"

sudo ${REGISTRY_INSTALL_PATH}/mirror-registry install \
     --quayHostname $HOSTNAME \
     --quayRoot ${REGISTRY_INSTALL_PATH} \
     --quayStorage ${REGISTRY_INSTALL_PATH}/quay-storage \
     --pgStorage ${REGISTRY_INSTALL_PATH}/pg-storage \
     --initUser ${REGISTRY_ID} --initPassword ${REGISTRY_PW} 
run_command "[installing mirror-registry...]"

sleep 60

# Get the status and number of containers for quay-pod
podman pod ps | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b4\b)' &>/dev/null
run_command "[mirror registry Pod is running]"

# Copy the rootCA certificate to the trusted source
sudo cp ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/quay.ca.pem
run_command "[copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/quay.ca.pem]"

# Trust the rootCA certificate
sudo update-ca-trust
run_command "[trust the rootCA certificate]"

# loggin registry
podman login -u ${REGISTRY_ID} -p ${REGISTRY_PW} https://${HOSTNAME}:8443 &>/dev/null
run_command  "[login registry https://${HOSTNAME}:8443]"

# Add an empty line after the task
echo
# ====================================================



# Task: Mirror ocp image to mirror-registry
PRINT_TASK "[TASK: Mirror ocp image to mirror-registry]"

# Prompt for pull-secret
read -p "Please input the pull secret string from https://cloud.redhat.com/openshift/install/pull-secret:" REDHAT_PULL_SECRET

# Create a temporary file to store the pull secret
PULL_SECRET=$(sudo mktemp -p /tmp)
echo "${REDHAT_PULL_SECRET}" > "${PULL_SECRET}"
run_command "[create a temporary file to store the pull secret]"

# Login to the registry
sudo rm -rf $XDG_RUNTIME_DIR/containers
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" "https://${HOSTNAME}:8443" &>/dev/null
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET}" "https://${HOSTNAME}:8443" &>/dev/null
run_command "[add authentication information to pull-secret]"

# Save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json
sudo cat ${PULL_SECRET} | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
run_command "[save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json]"

# Create ImageSetConfiguration directory
sudo rm -rf ${IMAGE_SET_CONFIGURATION_PATH} &>/dev/null
sudo mkdir ${IMAGE_SET_CONFIGURATION_PATH} &>/dev/null
run_command "[create ${IMAGE_SET_CONFIGURATION_PATH} directory]"

# Create ImageSetConfiguration file
sudo cat << EOF > ${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
 registry:
   imageURL: ${HOSTNAME}:8443/mirror/metadata
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
sudo oc mirror --config=${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml docker://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443 --dest-skip-tls
run_command "[mirroring ocp ${OCP_RELEASE_VERSION} release image]"

# Remove the temporary file
sudo rm -f "${PULL_SECRET}"
if [ $? -eq 0 ]; then
    echo "ok: [remove temporary pull-secret file]"
else
    echo "failed: [remove temporary pull-secret file]"
fi

# Add an empty line after the task
echo
# ====================================================



# Task: Generate a defined install-config file
PRINT_TASK "[TASK: Generate a defined install-config file]"

# Backup and format the registry CA certificate
sudo rm -rf "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak"
sudo cp "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem" "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak"
run_command "[backup registry CA certificate]"

sudo sed -i 's/^/  /' "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak"
run_command "[format registry ca certificate]"

# Create ssh-key for accessing CoreOS
sudo rm -rf ${SSH_KEY_PATH}
ssh-keygen -N '' -f ${HOME}/.ssh/id_rsa &> /dev/null
run_command "[create ssh-key for accessing coreos]"

# Define variables
export REGISTRY_CA_CERT_FORMAT="$(cat ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak)"
export REGISTRY_AUTH=$(echo -n "${REGISTRY_ID}:${REGISTRY_PW}" | base64)
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Generate a defined install-config file
sudo rm -rf $INSTALL/install-config.yaml
sudo mkdir $INSTALL

cat << EOF > $INSTALL/install-config.yaml
apiVersion: v1
baseDomain: $BASE_DOMAIN
credentialsMode: $CREDENTIALS_MODE
controlPlane:   
  hyperthreading: Enabled 
  name: master
  platform:
    aws:
      zones:
      - $AVAILABILITY_ZONE
      rootVolume:
        iops: 4000
        size: 500
        type: io1 
      metadataService:
        authentication: Optional 
      type: m6i.xlarge
  replicas: 3
compute: 
- hyperthreading: Enabled 
  name: worker
  platform:
    aws:
      rootVolume:
        iops: 2000
        size: 500
        type: io1 
      metadataService:
        authentication: Optional 
      type: c5.4xlarge
      zones:
      - $AVAILABILITY_ZONE
  replicas: 3
metadata:
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes 
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $REGION
    subnets: 
    - $PRIVATE_SUBNET_ID
    hostedZone: $HOSTED_ZONE_ID
fips: false
publish: Internal
pullSecret: '{"auths":{"$HOSTNAME:8443": {"auth": "$REGISTRY_AUTH","email": "test@redhat.com"}}}'
sshKey: '${SSH_PUB_STR}'
additionalTrustBundle: | 
${REGISTRY_CA_CERT_FORMAT}
imageContentSources: 
- mirrors:
  - $HOSTNAME:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- mirrors:
  - $HOSTNAME:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
EOF
run_command "[Generate a defined install-config file]"

# Delete certificate
rm -rf ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak
run_command "[delete ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak file]"

# Add an empty line after the task
echo
# ====================================================

# Task: Install OpenShift
PRINT_TASK "[TASK: Install OpenShift]"

sudo openshift-install create cluster --dir $INSTALL --log-level=info
