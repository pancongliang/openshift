#!/bin/bash

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Task: Set environment variables
PRINT_TASK "[TASK: Set environment variables]"

#### Set the necessary variables ####
# OpenShift version
export OCP_RELEASE="4.10.20"

# OpenShift install-config
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export SSH_KEY_PATH="/root/.ssh"                      # No need to manually create dir
export NETWORK_TYPE="OVNKubernetes"

# OpenShift infrastructure network
export GATEWAY_IP="10.74.255.254"
export NETMASK="21"
export DNS_FORWARDER_IP="10.75.5.25"

# OpenShift Node Hostname/IP variable
export BASTION_HOSTNAME="bastion"
export BOOTSTRAP_HOSTNAME="bootstrap"
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"
export BASTION_IP="10.74.251.171"
export MASTER01_IP="10.74.251.61"
export MASTER02_IP="10.74.254.155"
export MASTER03_IP="10.74.253.133"
export WORKER01_IP="10.74.251.58"
export WORKER02_IP="10.74.253.49"
export BOOTSTRAP_IP="10.74.255.118"

# OpenShift Coreos install dev/Net ifname
export COREOS_INSTALL_DEV="/dev/sda"
export NET_IF_NAME="'Wired connection 1'" 

# Registry and mirror variable
export REGISTRY_HOSTNAME="docker.registry"
export REGISTRY_ID="admin"
export REGISTRY_PW="redhat"
export PULL_SECRET="/root/pull-secret"                # Download pull-secret https://console.redhat.com/openshift/install/metal/installer-provisioned
export REGISTRY_CERT_PATH="/etc/certs"                # No need to manually create dir
export REGISTRY_INSTALL_PATH="/opt/registry"          # No need to manually create dir

### more parameters ###
# NFS directory is used to create image-registry pod pv
export NFS_PATH="/nfs"                                # No need to manually create dir
export IMAGE_REGISTRY_PV="image-registry"             # No need to manually create dir

# Httpd and ocp ignition dir
export HTTPD_PATH="/var/www/html/materials"           # No need to manually create dir
export IGNITION_PATH="${HTTPD_PATH}/pre"              # No need to manually create dir

# OpenShift install-config
export POD_CIDR="10.128.0.0/14"                       # Generally use the default value
export HOST_PREFIX="23"                               # Generally use the default value
export SERVICE_CIDR="172.30.0.0/16"                   # Generally use the default value

# Download ocp image
export LOCAL_REPOSITORY="ocp4/openshift4"
export PRODUCT_REPO="openshift-release-dev" 
export RELEASE_NAME="ocp-release"
export ARCHITECTURE="x86_64"

### Do not change the following parameters ###
# Function to generate duplicate parameters
export ID_RSA_PUB_FILE="${SSH_KEY_PATH}/id_rsa.pub"
export NFS_SERVER_IP="$BASTION_IP"
export DNS_SERVER_IP="$BASTION_IP"
export REGISTRY_IP="$BASTION_IP"
export API_IP="$BASTION_IP"
export API_INT_IP="$BASTION_IP"
export APPS_IP="$BASTION_IP"

# Create directories
run_command() {
    $1
    if [ $? -eq 0 ]; then
        echo "ok: [$2]"
        return 0
    else
        echo "failed: [$2]"
        return 1
    fi
}
# Create directories
run_command "mkdir -p ${SSH_KEY_PATH}" "creating SSH key directory"
run_command "mkdir -p ${REGISTRY_CERT_PATH}" "creating registry certificate directory"
run_command "mkdir -p ${REGISTRY_INSTALL_PATH}" "creating registry install directory"
run_command "mkdir -p ${NFS_PATH}" "creating NFS directory"
run_command "mkdir -p ${HTTPD_PATH}" "creating HTTPD directory"
run_command "mkdir -p ${IGNITION_PATH}" "creating Ignition directory"

# Function to generate reversed_ip_par/zone name
export IP_PART=$(echo "$BASTION_IP" | cut -d. -f1-2)
export REVERSED_IP_PART=$(echo "$IP_PART" | awk -F'.' '{print $2"."$1}')
export REVERSE_ZONE_NAME="$REVERSED_IP_PART.in-addr.arpa"
export REVERSE_ZONE_FILE="$REVERSED_IP_PART.zone"
export FORWARD_ZONE_NAME="$BASE_DOMAIN"
export FORWARD_ZONE_FILE="$BASE_DOMAIN.zone"


# Nslookup public network
export NSLOOKUP_PUBLIC="redhat.com"

### Check all variables ####
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
    check_variable "OCP_RELEASE"
    check_variable "CLUSTER_NAME"
    check_variable "BASE_DOMAIN"
    check_variable "SSH_KEY_PATH"
    check_variable "ID_RSA_PUB_FILE"
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
    check_variable "BASTION_IP"
    check_variable "MASTER01_IP"
    check_variable "MASTER02_IP"
    check_variable "MASTER03_IP"
    check_variable "WORKER01_IP"
    check_variable "WORKER02_IP"
    check_variable "BOOTSTRAP_IP"
    check_variable "COREOS_INSTALL_DEV"
    check_variable "NET_IF_NAME"
    check_variable "REGISTRY_HOSTNAME"
    check_variable "REGISTRY_ID"
    check_variable "REGISTRY_PW"
    check_variable "PULL_SECRET"
    check_variable "REGISTRY_CERT_PATH"  
    check_variable "REGISTRY_INSTALL_PATH"
    check_variable "NFS_PATH"
    check_variable "IMAGE_REGISTRY_PV"
    check_variable "DNS_SERVER_IP"
    check_variable "REGISTRY_IP"
    check_variable "API_IP"
    check_variable "API_INT_IP"
    check_variable "APPS_IP"
    check_variable "NFS_SERVER_IP"
    check_variable "IP_PART"
    check_variable "REVERSED_IP_PART"
    check_variable "REVERSE_ZONE_NAME"
    check_variable "REVERSE_ZONE_FILE"
    check_variable "FORWARD_ZONE_NAME"
    check_variable "FORWARD_ZONE_FILE"
    check_variable "NSLOOKUP_PUBLIC"
    check_variable "LOCAL_REPOSITORY"
    check_variable "PRODUCT_REPO"
    check_variable "RELEASE_NAME"
    check_variable "ARCHITECTURE"
    check_variable "HTTPD_PATH"
    check_variable "IGNITION_PATH"
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
