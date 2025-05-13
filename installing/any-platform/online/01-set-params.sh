#!/bin/bash

# OpenShift release version
export OCP_RELEASE_VERSION="4.16.26"

# OpenShift install-config
export PULL_SECRET_FILE="$HOME/ocp-inst/pull-secret"   #  Download https://cloud.redhat.com/openshift/install/metal/installer-provisioned and copy it to the specified path
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export NETWORK_TYPE="OVNKubernetes"

# OpenShift Coreos install Dev/Net ifname
export COREOS_INSTALL_DEV="/dev/sda"
export NET_IF_NAME="'Wired connection 1'" 

# OpenShift infrastructure network
export GATEWAY_IP="10.184.134.1"
export NETMASK="24"
export DNS_FORWARDER_IP="10.184.134.1"                # Resolve DNS addresses on the Internet

# OpenShift node hostname and IP address information
export BASTION_HOSTNAME="bastion"
export BOOTSTRAP_HOSTNAME="bootstrap"
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"
export WORKER03_HOSTNAME="worker03"
export BASTION_IP="10.184.134.128"
export BOOTSTRAP_IP="10.184.134.223"
export MASTER01_IP="10.184.134.243"
export MASTER02_IP="10.184.134.241"
export MASTER03_IP="10.184.134.207"
export WORKER01_IP="10.184.134.238"
export WORKER02_IP="10.184.134.246"
export WORKER03_IP="10.184.134.202"


# More options, no changes required
# OpenShift install-config
export SSH_KEY_PATH="$HOME/.ssh"
export POD_CIDR="10.128.0.0/14"
export HOST_PREFIX="23"
export SERVICE_CIDR="172.30.0.0/16"

# NFS directory is used to create image-registry pod pv
export NFS_DIR="/nfs"
export IMAGE_REGISTRY_PV="image-registry"

# Httpd and ocp ignition dir
export HTTPD_DIR="/var/www/html/materials"
export INSTALL_DIR="${HTTPD_DIR}/pre"

# Do not change the following parameters
export NFS_SERVER_IP="$BASTION_IP"
export DNS_SERVER_IP="$BASTION_IP"
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
    check_variable "NFS_DIR"
    check_variable "IMAGE_REGISTRY_PV"
    check_variable "DNS_SERVER_IP"
    check_variable "LB_IP"
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
