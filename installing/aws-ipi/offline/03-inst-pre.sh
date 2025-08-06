#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Step 1:
PRINT_TASK "TASK [Enter pull-secret information]"

# Prompt for pull-secret
read -p "Please input the pull secret string from https://cloud.redhat.com/openshift/install/pull-secret:" REDHAT_PULL_SECRET

# Add an empty line after the task
echo

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

# Step 2:
# Applying environment variables
source 01-set-params.sh

# Step 3:
PRINT_TASK "TASK [Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "vim-enhanced" "podman" "git" "bash-completion" "jq" "skopeo")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
sudo dnf install -y $package_list >/dev/null

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    sudo rpm -q $package &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [installed $package package]"
    else
        echo "failed: [installed $package package]"
    fi
done

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Install openshift tool]"

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

# Function to download and install .tar.gz tools
install_tar_gz() {
    local tool_name="$1"
    local tool_url="$2"  
    # Download the tool
    sudo wget -P "/usr/local/bin" "$tool_url" &> /dev/null    
    if [ $? -eq 0 ]; then
        echo "ok: [Download $tool_name tool]"        
        # Extract the downloaded tool
        sudo tar xvf "/usr/local/bin/$(basename $tool_url)" -C "/usr/local/bin/" &> /dev/null
        # Remove the downloaded .tar.gz file
        sudo rm -rf "/usr/local/bin/openshift-install.tar.gz" > /dev/null 
        sudo rm -rf "/usr/local/bin/openshift-client.tar.gz" > /dev/null
        sudo rm -rf "/usr/local/bin/oc-mirror.tar.gz" > /dev/null
    else
        echo "failed: [Download $tool_name tool]"
    fi
}

# Install .tar.gz tools
install_tar_gz "openshift-install" "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE_VERSION}/openshift-install-linux.tar.gz"
install_tar_gz "openshift-client" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz"
install_tar_gz "oc-mirror" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"

sudo chmod a+x /usr/local/bin/oc-mirror > /dev/null 
run_command "[Modify /usr/local/bin/oc-mirror tool permissions]"

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Install AWS CLI]"

# Function to install AWS CLI on Linux
install_awscli_linux() {
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" > /dev/null 
    unzip awscliv2.zip > /dev/null 
    sudo ./aws/install &>/dev/null || true
    run_command "[Install AWS CLI]"
    sudo rm -rf aws awscliv2.zip
}

# Function to install AWS CLI on macOS
install_awscli_mac() {
    curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" > /dev/null 
    sudo installer -pkg AWSCLIV2.pkg -target / &>/dev/null || true
    run_command "[Install AWS CLI]"
    sudo rm -rf AWSCLIV2.pkg
}

# Detecting the operating system
os=$(uname -s)

# Installing AWS CLI based on the operating system
case "$os" in
    Linux*)  install_awscli_linux;;
    Darwin*) install_awscli_mac;;
    *) ;;
esac

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Set up AWS credentials]"
sudo rm -rf $HOME/.aws
sudo mkdir -p $HOME/.aws
sudo cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[Set up AWS credentials]"

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Delete existing Mirror-Registry duplicate data]"

# Check if there is an active mirror registry pod
if podmanpod ps | grep -E 'quay-pod.*Running' >/dev/null; then
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
    "/etc/pki/ca-trust/source/anchors/quay.ca.pem"
    "${REGISTRY_INSTALL_PATH}"
)
for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        sudo rm -rf "$file" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "ok: [Delete existing duplicate data: $file]"
        fi
    fi
done

# Add an empty line after the task
echo

# Step 8:
PRINT_TASK "TASK [Install Mirror-Registry]"

sudo mkdir -p ${REGISTRY_INSTALL_PATH}
sudo mkdir -p ${REGISTRY_INSTALL_PATH}/quay-storage
sudo mkdir -p ${REGISTRY_INSTALL_PATH}/sqlite-storage
sudo chmod -R 777 ${REGISTRY_INSTALL_PATH}
run_command "[Create ${REGISTRY_INSTALL_PATH} directory]"

# Download mirror-registry
# wget -P ${REGISTRY_INSTALL_PATH} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz &> /dev/null
sudo wget -O ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz &> /dev/null
run_command "[Download mirror-registry package]"

# Extract the downloaded mirror-registry package
sudo tar xvf ${REGISTRY_INSTALL_PATH}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_PATH}/ &> /dev/null
run_command "[Extract the mirror-registry package]"

echo "ok: [Start installing mirror-registry...]"
echo "ok: [Generate mirror-registry log: ${REGISTRY_INSTALL_PATH}/mirror-registry.log]"

sudo ${REGISTRY_INSTALL_PATH}/mirror-registry install -v \
     --quayHostname ${REGISTRY_DOMAIN_NAME} \
     --quayRoot ${REGISTRY_INSTALL_PATH} \
     --quayStorage ${REGISTRY_INSTALL_PATH}/quay-storage \
     --sqliteStorage ${REGISTRY_INSTALL_PATH}/sqlite-storage \
     --initUser ${REGISTRY_ID} \
     --initPassword ${REGISTRY_PW} > ${REGISTRY_INSTALL_PATH}/mirror-registry.log
run_command "[Installation of mirror registry completed]"

sleep 60

# Copy the rootCA certificate to the trusted source
sudo cp ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/quay.ca.pem &>/dev/null
run_command "[Copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/quay.ca.pem]"

# Trust the rootCA certificate
sudo update-ca-trust &>/dev/null
run_command "[Trust the rootCA certificate]"

# loggin registry
podmanlogin -u ${REGISTRY_ID} -p ${REGISTRY_PW} https://${HOSTNAME}:8443 &>/dev/null
run_command  "[Login registry https://${HOSTNAME}:8443]"

sudo rm -rf ./*.tar

# Add an empty line after the task
echo

# Step 1:9
PRINT_TASK "TASK [Mirror ocp image to Mirror-Registry]"

# Prompt for pull-secret
# read -p "Please input the pull secret string from https://cloud.redhat.com/openshift/install/pull-secret:" REDHAT_PULL_SECRET

# Create a temporary file to store the pull secret
PULL_SECRET=$(mktemp -p $HOME)
echo "${REDHAT_PULL_SECRET}" > "${PULL_SECRET}"
run_command "[Create a temporary file to store the pull secret]"

# Login to the registry
sudo rm -rf $XDG_RUNTIME_DIR/containers &>/dev/null
podmanlogin -u "$REGISTRY_ID" -p "$REGISTRY_PW" "https://${HOSTNAME}:8443" &>/dev/null
podmanlogin -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET}" "https://${HOSTNAME}:8443" &>/dev/null
run_command "[Add authentication information to pull-secret]"

# Save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json
sudo cat ${PULL_SECRET} | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
run_command "[Save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json]"

# Create ImageSetConfiguration directory
sudo sudo rm -rf ${IMAGE_SET_CONFIGURATION_PATH} &>/dev/null
sudo mkdir ${IMAGE_SET_CONFIGURATION_PATH} &>/dev/null
run_command "[Create ${IMAGE_SET_CONFIGURATION_PATH} directory]"

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
run_command "[Create ${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml file]"

# Mirroring ocp release image
echo "ok: [Generate oc-mirror mirror log: ${IMAGE_SET_CONFIGURATION_PATH}/mirror.log]"
/usr/local/bin/oc-mirror --config=${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml docker://${HOSTNAME}:8443 --dest-skip-tls > ${IMAGE_SET_CONFIGURATION_PATH}/mirror.log
run_command "[Mirroring OCP ${OCP_RELEASE_VERSION} release image]"

# Remove the temporary file
sudo rm -rf oc-mirror-workspac* &>/dev/null
sudo rm -rf "${PULL_SECRET}" &>/dev/null
run_command "[Remove temporary pull-secret file]"

# Add an empty line after the task
echo

# Step 10:
PRINT_TASK "TASK [Generate a defined install-config file]"

# Backup and format the registry CA certificate
sudo rm -rf "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak"
sudo cp "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem" "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak"
run_command "[Backup registry CA certificate]"

sudo sed -i 's/^/  /' "${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak"
run_command "[Format registry ca certificate]"

# Create ssh-key for accessing CoreOS
sudo rm -rf ${HOME}/.ssh/id_rsa ${HOME}/.ssh/id_rsa.pub
sudo ssh-keygen -N '' -f ${HOME}/.ssh/id_rsa &> /dev/null
run_command "[Create ssh-key for accessing coreos]"

# Define variables
export REGISTRY_CA_CERT_FORMAT="$(cat ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak)"
export REGISTRY_AUTH=$(echo -n "${REGISTRY_ID}:${REGISTRY_PW}" | base64)
export SSH_PUB_STR="$(cat ${HOME}/.ssh/id_rsa.pub)"
export HOSTED_ZONE_ID=$(aws --region $REGION route53 list-hosted-zones --query "HostedZones[?Name=='$HOSTED_ZONE_NAME.'].Id" --output text | awk -F'/' '{print $3}')
export PRIVATE_SUBNET_ID=$(aws --region $REGION ec2 describe-subnets --filters "Name=tag:Name,Values=${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE}" --query "Subnets[].SubnetId" --output text)

# Generate a defined install-config file
sudo rm -rf $INSTALL
sudo mkdir $INSTALL

sudo cat << EOF > $INSTALL/install-config.yaml
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
  networkType: ${NETWORK_TYPE}
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
sudo rm -rf ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak
run_command "[Delete ${REGISTRY_INSTALL_PATH}/quay-rootCA/rootCA.pem.bak file]"

sudo /usr/local/bin/openshift-install create manifests --dir $INSTALL &>/dev/null
run_command "[Manifests created in: $INSTALL/manifests $INSTALL/openshift ]"

# Delete the private zone in the cluster-dns-02-config.yml file
sudo cat << EOF > $INSTALL/manifests/cluster-dns-02-config.yml
apiVersion: config.openshift.io/v1
kind: DNS
metadata:
  creationTimestamp: null
  name: cluster
spec:
  baseDomain: $CLUSTER_NAME.$BASE_DOMAIN
  platform:
    aws: null
    type: ""
status: {}
EOF
run_command "[Delete the private zone in the $INSTALL/manifests/cluster-dns-02-config.yml file]"

# Add an empty line after the task
echo
