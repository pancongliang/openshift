#!/bin/bash

# Specify the OpenShift release version
export OCP_VERSION="4.16.29"

# Specify required parameters for install-config.yaml
export PULL_SECRET_FILE="$HOME/ocp-inst/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export CLUSTER_NAME="ocp"
export BASE_DOMAIN="example.com"
export NETWORK_TYPE="OVNKubernetes"                    # OVNKubernetes or OpenShiftSDN(≤ 4.14)

# Specify the OpenShift node’s installation disk and network manager connection name
export COREOS_INSTALL_DEV="/dev/sda"
export NET_IF_NAME="'Wired connection 1'" 

# Specify the OpenShift node infrastructure network configuration
export GATEWAY_IP="10.184.134.1"
export NETMASK="24"
export DNS_FORWARDER_IP="10.184.134.1"                 # Resolve DNS addresses on the Internet

# Specify OpenShift node’s hostname and ip address
export BASTION_HOSTNAME="bastion"
export BOOTSTRAP_HOSTNAME="bootstrap"
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"
export WORKER03_HOSTNAME="worker03"
export BASTION_IP="10.184.134.128"
export BOOTSTRAP_IP="10.184.134.54"
export MASTER01_IP="10.184.134.177"
export MASTER02_IP="10.184.134.156"
export MASTER03_IP="10.184.134.154"
export WORKER01_IP="10.184.134.121"
export WORKER02_IP="10.184.134.216"
export WORKER03_IP="10.184.134.134"


# More options — no changes required!
# Specify required parameters for install-config.yaml
export SSH_KEY_PATH="$HOME/.ssh"
export POD_CIDR="10.128.0.0/14"
export HOST_PREFIX="23"
export SERVICE_CIDR="172.30.0.0/16"

# Specify the NFS directory to use for the image-registry pod PV
export NFS_SERVER_IP="$BASTION_IP"
export NFS_DIR="/nfs"
export IMAGE_REGISTRY_PV="image-registry"

# Specify the HTTPD path to serve the Ignition file for download
export HTTPD_DIR="/var/www/html/materials"
export INSTALL_DIR="${HTTPD_DIR}/pre"

# Specify a publicly resolvable domain name for testing
export NSLOOKUP_TEST_PUBLIC_DOMAIN="redhat.com"

# Do not change the following parameters
export LOCAL_DNS_IP="$BASTION_IP"
export API_VIPS="$BASTION_IP"
export INGRESS_VIPS="$BASTION_IP"
export MCS_VIPS="$API_VIPS"
export API_IP="$API_VIPS"
export API_INT_IP="$API_VIPS"
export APPS_IP="$INGRESS_VIPS"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Step 1:
PRINT_TASK "TASK [Configure Environment Variables]"

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
run_command "[Verify existence of $PULL_SECRET_FILE file]"

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
    check_variable "OCP_VERSION"
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
    check_variable "LOCAL_DNS_IP"
    check_variable "API_IP"
    check_variable "API_INT_IP"
    check_variable "APPS_IP"
    check_variable "API_VIPS"
    check_variable "MCS_VIPS"
    check_variable "INGRESS_VIPS"
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
    IFS=', '
    echo "failed: [Missing variables: ${missing_variables[*]}]"
    unset IFS
else
    echo "ok: [Confirm all required variables are set]"
fi

# Add an empty line after the task
echo
