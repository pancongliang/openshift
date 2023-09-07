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


# Task: Set environment variables
PRINT_TASK "[TASK: Set environment variables]"

# No need to create any resources, just specify parameters.
# === Set the necessary variables === 
# OpenShift version
export OCP_RELEASE="4.10.20"

# OpenShift install-config
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export SSH_KEY_PATH="/root/.ssh"
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

# === more parameters === 
# Mirror-Registry and mirror variable
export REGISTRY_HOSTNAME="mirror.registry"
export REGISTRY_ID="root"
export REGISTRY_PW="password"                         # 8 characters or more
export REGISTRY_INSTALL_PATH="/opt/registry"

# NFS directory is used to create image-registry pod pv
export NFS_PATH="/nfs"
export IMAGE_REGISTRY_PV="image-registry"

# Httpd and ocp ignition dir
export HTTPD_PATH="/var/www/html/materials"
export IGNITION_PATH="${HTTPD_PATH}/pre"

# OpenShift install-config
export POD_CIDR="10.128.0.0/14"
export HOST_PREFIX="23"
export SERVICE_CIDR="172.30.0.0/16"

# Download ocp image
export LOCAL_REPOSITORY="ocp4/openshift4"
export PRODUCT_REPO="openshift-release-dev" 
export RELEASE_NAME="ocp-release"
export ARCHITECTURE="x86_64"

# === Do not change the following parameters === 
# Function to generate duplicate parameters
export NFS_SERVER_IP="$BASTION_IP"
export DNS_SERVER_IP="$BASTION_IP"
export REGISTRY_IP="$BASTION_IP"
export API_IP="$BASTION_IP"
export API_INT_IP="$BASTION_IP"
export APPS_IP="$BASTION_IP"
export LB_IP="$BASTION_IP"

# Nslookup public network
export NSLOOKUP_PUBLIC="redhat.com"

# === Check all variables === 
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
    check_variable "REGISTRY_INSTALL_PATH"
    check_variable "NFS_PATH"
    check_variable "IMAGE_REGISTRY_PV"
    check_variable "DNS_SERVER_IP"
    check_variable "LB_IP"
    check_variable "REGISTRY_IP"
    check_variable "API_IP"
    check_variable "API_INT_IP"
    check_variable "APPS_IP"
    check_variable "NFS_SERVER_IP"
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

# Add an empty line after the task
echo
# ====================================================
