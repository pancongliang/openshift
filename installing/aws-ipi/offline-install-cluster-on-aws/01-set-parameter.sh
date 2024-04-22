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
export OCP_RELEASE_VERSION="4.14.20"

# OpenShift install-config
export CLUSTER_NAME="copan"
export BASE_DOMAIN="test.copan.com"
export CREDENTIALS_MODE="Passthrough"

# AWS credentials
export AWS_ACCESS_KEY_ID="AKIAQ2FLxxxxx"
export AWS_SECRET_ACCESS_KEY="KiGyRt5EyHJo+z9NWVawgxxxx"
export VPC_NAME="copan"
export REGION="ap-northeast-1"
export AVAILABILITY_ZONE="ap-northeast-1a"

# Bastion instance
export INSTANCE_NAME="$VPC_NAME-bastion"
export KEY_PAIR_NAME="$VPC_NAME-KEY"
export AMI_ID="ami-0014871499315f25a"
export STORAGE_SIZE="100" 

# === more parameters ===
export INSTALL="$HOME/ocp-install"
export REGISTRY_ID="admin"
export REGISTRY_PW="password"
export REGISTRY_INSTALL_PATH="/opt/quay-install"
export IMAGE_SET_CONFIGURATION_PATH="$HOME/OLM"
export OCP_RELEASE_CHANNEL="$(echo $OCP_RELEASE_VERSION | cut -d. -f1,2)"
export DOMAIN_NAME="$BASE_DOMAIN"
export SECURITY_GROUP_NAME="$VPC_NAME-sg"
export EC2_ENDPOINT_NAME="$VPC_NAME-vpce-ec2"
export ELB_ENDPOINT_NAME="$VPC_NAME-vpce-elb"
export VPC_CIDR="10.0.0.0/16"
export PUBLIC_SUBNET_CIDR="10.0.0.0/24"
export PRIVATE_SUBNET_CIDR="10.0.1.0/24"
export S3_SERVICE_NAME="com.amazonaws.$REGION.s3"

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
    check_variable "OCP_RELEASE_VERSION"
    check_variable "CLUSTER_NAME"
    check_variable "BASE_DOMAIN"
    check_variable "CREDENTIALS_MODE"
    check_variable "AWS_ACCESS_KEY_ID"
    check_variable "AWS_SECRET_ACCESS_KEY"
    check_variable "INSTANCE_NAME"
    check_variable "KEY_PAIR_NAME"
    check_variable "AMI_ID"
    check_variable "STORAGE_SIZE"
    check_variable "VPC_NAME"
    check_variable "REGION"
    check_variable "AVAILABILITY_ZONE"
    check_variable "REGISTRY_ID"
    check_variable "REGISTRY_PW"
    check_variable "REGISTRY_INSTALL_PATH"
    check_variable "IMAGE_SET_CONFIGURATION_PATH"
    check_variable "OCP_RELEASE_CHANNEL"
    check_variable "DOMAIN_NAME"
    check_variable "SECURITY_GROUP_NAME"
    check_variable "EC2_ENDPOINT_NAME"
    check_variable "ELB_ENDPOINT_NAME"
    check_variable "VPC_CIDR"
    check_variable "PUBLIC_SUBNET_CIDR"
    check_variable "PRIVATE_SUBNET_CIDR"
    check_variable "S3_SERVICE_NAME"
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
