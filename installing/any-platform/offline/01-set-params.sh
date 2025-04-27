#!/bin/bash
# No need to create any resources, just specify parameters.
# OpenShift release version
export OCP_RELEASE_VERSION="4.12.30"

# OpenShift install-config
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export PULL_SECRET_FILE="$HOME/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export SSH_KEY_PATH="$HOME/.ssh"
export NETWORK_TYPE="OVNKubernetes"
export POD_CIDR="10.128.0.0/14"
export HOST_PREFIX="23"
export SERVICE_CIDR="172.30.0.0/16"

# OpenShift infrastructure network
export GATEWAY_IP="10.184.134.1"
export NETMASK="24"
export DNS_FORWARDER_IP="10.184.134.1"

# OpenShift Node Hostname/IP variable
export BASTION_HOSTNAME="bastion"
export BOOTSTRAP_HOSTNAME="bootstrap"
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"
export WORKER03_HOSTNAME="worker03"
export BASTION_IP="10.184.134.128"
export BOOTSTRAP_IP="10.184.134.101"
export MASTER01_IP="10.184.134.129"
export MASTER02_IP="10.184.134.130"
export MASTER03_IP="10.184.134.131"
export WORKER01_IP="10.184.134.132"
export WORKER02_IP="10.184.134.133"
export WORKER03_IP="10.184.134.134"

# OpenShift Coreos install Dev/Net ifname
export COREOS_INSTALL_DEV="/dev/sda"
export NET_IF_NAME="'Wired connection 1'" 

# Mirror-Registry is used to mirror ocp image
export REGISTRY_HOSTNAME="mirror.registry"
export REGISTRY_ID="admin"
export REGISTRY_PW="password"                         # 8 characters or more
export REGISTRY_INSTALL_DIR="/opt/quay-install"

# oc-mirror plug-in for mirror image
export IMAGE_SET_CONF_PATH="/$HOME/oc-mirror"
export OCP_RELEASE_CHANNEL="$(echo $OCP_RELEASE_VERSION | cut -d. -f1,2)"

# NFS directory is used to create image-registry pod pv
export NFS_DIR="/nfs"
export IMAGE_REGISTRY_PV="image-registry"

# Httpd and ocp ignition dir
export HTTPD_DIR="/var/www/html/materials"
export INSTALL_DIR="${HTTPD_DIR}/pre"
 
# Do not change the following parameters
export NFS_SERVER_IP="$BASTION_IP"
export DNS_SERVER_IP="$BASTION_IP"
export REGISTRY_IP="$BASTION_IP"
export API_IP="$BASTION_IP"
export API_INT_IP="$BASTION_IP"
export APPS_IP="$BASTION_IP"
export LB_IP="$BASTION_IP"

# Nslookup public network
export NSLOOKUP_TEST_PUBLIC_DOMAIN="redhat.com"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Step 1:
PRINT_TASK "TASK [Set environment variables]"

# Function to check command success and display appropriate message
run_command() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

cat $PULL_SECRET_FILE >/dev/null 2>&1
run_command "[check if the $PULL_SECRET_FILE file exists]"

# Define variables
missing_variables=()

# Define a function to check if a variable is set
check_variable() {
    if [ -z "${!1}" ]; then
        missing_variables+=("$1")
    fi
}

# Check all variables that need validation
check_all_variables() {
    check_variable "OCP_RELEASE_VERSION"
    check_variable "CLUSTER_NAME"
    check_variable "BASE_DOMAIN"
    check_variable "SSH_KEY_PATH"
    check_variable "PULL_SECRET_FILE"
    check_variable "NETWORK_TYPE"
    check_variable "POD_CIDR"
    check_variable "HOST_PREFIX"
    check_variable "SERVICE_CIDR"
    check_variable "GATEWAY_IP"
    check_variable "NETMASK"
    check_variable "DNS_FORWARDER_IP"
    check_variable "BASTION_HOSTNAME"
    check_variable "BOOTSTRAP_HOSTNAME"
    check_variable "MASTER01_HOSTNAME"
    check_variable "MASTER02_HOSTNAME"
    check_variable "MASTER03_HOSTNAME"
    check_variable "WORKER01_HOSTNAME"
    check_variable "WORKER02_HOSTNAME"
    check_variable "WORKER03_HOSTNAME"
    check_variable "BASTION_IP"
    check_variable "MASTER01_IP"
    check_variable "MASTER02_IP"
    check_variable "MASTER03_IP"
    check_variable "WORKER01_IP"
    check_variable "WORKER02_IP"
    check_variable "WORKER03_IP"    
    check_variable "BOOTSTRAP_IP"
    check_variable "COREOS_INSTALL_DEV"
    check_variable "NET_IF_NAME"
    check_variable "REGISTRY_HOSTNAME"
    check_variable "REGISTRY_ID"
    check_variable "REGISTRY_PW"
    check_variable "REGISTRY_INSTALL_DIR"
    check_variable "IMAGE_SET_CONF_PATH"
    check_variable "OCP_RELEASE_CHANNEL"
    check_variable "NFS_DIR"
    check_variable "IMAGE_REGISTRY_PV"
    check_variable "DNS_SERVER_IP"
    check_variable "LB_IP"
    check_variable "REGISTRY_IP"
    check_variable "API_IP"
    check_variable "API_INT_IP"
    check_variable "APPS_IP"
    check_variable "NFS_SERVER_IP"
    check_variable "NSLOOKUP_TEST_PUBLIC_DOMAIN"
    check_variable "HTTPD_DIR"
    check_variable "INSTALL_DIR"
    # If all variables are set, display a success message  
}

# Call the function to check all variables
check_all_variables

# Display missing variables, if any
if [ ${#missing_variables[@]} -gt 0 ]; then
    echo "Missing or unset variables:"
    for var in "failed: [${missing_variables[@]}]"; do
        echo "- $var"
    done
else
    echo "ok: [all variables are set]"
fi

# Add an empty line after the task
echo

# Step 2:
# PRINT_TASK "TASK [Prepare the pull-secret]"

# Prompt for pull-secret
# read -p "Please input the pull secret string from https://cloud.redhat.com/openshift/install/pull-secret:" REDHAT_PULL_SECRET

# Create a temporary file to store the pull secret
# PULL_SECRET_FILE=$(mktemp -p /tmp)
# echo "${REDHAT_PULL_SECRET}" > "${PULL_SECRET_FILE}"
# run_command "[create a temporary file to store the pull secret]"

# Add an empty line after the task
# echo
