#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Define environment variables for Single Node OpenShift (SNO) deployment
export OCP_VERSION=4.16.20
export ARCH=x86_64
export CLUSTER_NAME="sno"
export BASE_DOMAIN="example.com"
export SNO_IP="10.72.94.209"
export SNO_GW="10.72.94.254"
export SNO_NETMASK="255.255.255.0"
export SNO_DNS="10.74.251.171"
export SNO_DISK="/dev/sda"
export SNO_INTERFACE="ens192"

# Define client-specific variables
export SSH_KEY_PATH="$HOME/.ssh"
export PULL_SECRET_PATH="$HOME/pull-secret"
export CLIENT_OS_ARCH=mac-arm64              #mac/mac-arm64/linux


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

PRINT_TASK "TASK [Delete old SNO resources...]"

# Delete old data
echo "info: [delete old sno resources...]"
rm -rf oc >/dev/null 2>&1 || true
rm -rf kubectl >/dev/null 2>&1 || true
rm -rf oc.tar.gz >/dev/null 2>&1 || true
rm -rf openshift-install >/dev/null 2>&1 || true
rm -rf openshift-install-$CLIENT_OS_ARCH.tar.gz >/dev/null 2>&1 || true
rm -rf ocp >/dev/null 2>&1 || true
rm -rf rhcos-live.iso >/dev/null 2>&1 || true
rm -rf README.md >/dev/null 2>&1 || true
echo 

# Step 1:
PRINT_TASK "TASK [Generating the installation ISO with coreos-installer]"

# Download OpenShift client tool
curl -s -k https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_VERSION/openshift-client-$CLIENT_OS_ARCH.tar.gz -o oc.tar.gz
run_command "[download openshift client tool]"

# Extract and install OpenShift client tool
tar zxf oc.tar.gz >/dev/null 2>&1
run_command "[install openshift client tool]"

# Modify permissions for the OpenShift client
chmod +x oc >/dev/null 2>&1
run_command "[modify oc client permissions]"

# Download OpenShift install tool
curl -s -k https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_VERSION/openshift-install-$CLIENT_OS_ARCH.tar.gz -o openshift-install-$CLIENT_OS_ARCH.tar.gz
run_command "[download openshift install tool]"

# Extract and install OpenShift installer
tar -xzf openshift-install-$CLIENT_OS_ARCH.tar.gz >/dev/null 2>&1
run_command "[install openshift install tool]"

# Modify permissions for the OpenShift installer
chmod +x openshift-install >/dev/null 2>&1
run_command "[modify openshift install permissions]"

# Fetch the CoreOS live ISO download link from OpenShift installer
ISO_URL=$(./openshift-install coreos print-stream-json | grep location | grep $ARCH | grep iso | cut -d\" -f4)

# Download the CoreOS live ISO
curl -s -L $ISO_URL -o rhcos-live.iso >/dev/null 2>&1
run_command "[download rhcos-live.iso]"

# Create ssh-key for accessing CoreOS
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo "ok: [create ssh-key for accessing coreos]"
else
    echo "info: [ssh key already exists, skip generation]"
fi

# Define variables
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Create the installation directory
mkdir ocp
run_command "[create installation directory: ocp]"

# Generate the OpenShift installation configuration file
cat << EOF > ocp/install-config.yaml 2>/dev/null
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- name: worker
  replicas: 0 
controlPlane:
  name: master
  replicas: 1 
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
  none: {}
bootstrapInPlace:
  installationDisk: $SNO_DISK
pullSecret: '$(cat $PULL_SECRET_PATH)' 
sshKey: '${SSH_PUB_STR}'
EOF
run_command "[create ocp/install-config.yaml file]"

# Generate ignition configuration for single-node OpenShift
./openshift-install --dir=ocp create single-node-ignition-config >/dev/null 2>&1
run_command "[create single-node-ignition-config]"

# Define an alias for the CoreOS installer
#alias coreos-installer='podman run --privileged --pull always --rm -v /dev:/dev -v /run/udev:/run/udev -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release'
#run_command "[define an alias for the coreos installer]"

# Embed ignition configuration into the CoreOS live ISO
podman run --privileged --pull always --rm -v /dev:/dev -v /run/udev:/run/udev -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release iso ignition embed -fi ocp/bootstrap-in-place-for-live-iso.ign rhcos-live.iso >/dev/null 2>&1
run_command "[embed ignition configuration into the coreos live iso]"

# Modify kernel arguments for network configuration
podman run --privileged --pull always --rm -v /dev:/dev -v /run/udev:/run/udev -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release iso kargs modify -a "ip=$SNO_IP::$SNO_GW:$SNO_NETMASK:$CLUSTER_NAME.$BASE_DOMAIN:$SNO_INTERFACE:off:$SNO_DNS" rhcos-live.iso >/dev/null 2>&1
run_command "[modify kernel arguments for network configuration]"

# Clean up downloaded archives
rm -rf oc.tar.gz >/dev/null 2>&1 || true
rm -rf kubectl >/dev/null 2>&1 || true
rm -rf openshift-install-$CLIENT_OS_ARCH.tar.gz >/dev/null 2>&1 || true
rm -rf README.md >/dev/null 2>&1 || true
