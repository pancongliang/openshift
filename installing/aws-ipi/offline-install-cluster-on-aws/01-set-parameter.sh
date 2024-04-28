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
export NETWORK_TYPE="OVNKubernetes"

# AWS credentials
export AWS_ACCESS_KEY_ID="AKIAQ2Fxxxx"
export AWS_SECRET_ACCESS_KEY="KiGyRt5EyHJo+zxxx"
export REGION="ap-northeast-1"
export AVAILABILITY_ZONE="ap-northeast-1a"
export TAG_NAME="$CLUSTER_NAME"     # Created AWS resource tag name

# === Default parameters ===
export INSTANCE_NAME="$TAG_NAME-bastion"
export KEY_PAIR_NAME="$TAG_NAME-ec2-key"
export STORAGE_SIZE="100" 
export INSTALL="$HOME/ocp-install"
export REGISTRY_ID="admin"
export REGISTRY_PW="password"
export REGISTRY_INSTALL_PATH="$HOME/quay-install"
export IMAGE_SET_CONFIGURATION_PATH="$HOME/mirror"
export OCP_RELEASE_CHANNEL="$(echo $OCP_RELEASE_VERSION | cut -d. -f1,2)"
export HOSTED_ZONE_NAME="$BASE_DOMAIN"
export VPC_NAME="$TAG_NAME-vpc"
export IGW_NAME="$TAG_NAME-igw"
export PUBLIC_RTB_NAME="$TAG_NAME-public-rtb"
export PRIVATE_RTB_NAME="$TAG_NAME-private-rtb"
export SECURITY_GROUP_NAME="$TAG_NAME-sg"
export S3_ENDPOINT_NAME="$TAG_NAME-vpce-s3"
export EC2_ENDPOINT_NAME="$TAG_NAME-vpce-ec2"
export ELB_ENDPOINT_NAME="$TAG_NAME-vpce-elb"
export VPC_CIDR="10.0.0.0/16"
export PUBLIC_SUBNET_CIDR="10.0.0.0/24"
export PRIVATE_SUBNET_CIDR="10.0.1.0/24"
export S3_SERVICE_NAME="com.amazonaws.$REGION.s3"

# === Check all variables === 
# Define variables
missing_variables=()

# Define a function to check if a variable is set
check_variable() {
    local var_name="$1"
    local var_value="$(eval echo \$$var_name)"
    if [ -z "$var_value" ]; then
        missing_variables+=("$var_name")
    fi
}

# Check all variables that need validation
check_all_variables() {
    check_variable "OCP_RELEASE_VERSION"
    check_variable "CLUSTER_NAME"
    check_variable "BASE_DOMAIN"
    check_variable "CREDENTIALS_MODE"
    check_variable "NETWORK_TYPE"
    check_variable "AWS_ACCESS_KEY_ID"
    check_variable "AWS_SECRET_ACCESS_KEY"
    check_variable "INSTANCE_NAME"
    check_variable "KEY_PAIR_NAME"
    check_variable "STORAGE_SIZE"
    check_variable "REGION"
    check_variable "AVAILABILITY_ZONE"
    check_variable "REGISTRY_ID"
    check_variable "REGISTRY_PW"
    check_variable "REGISTRY_INSTALL_PATH"
    check_variable "IMAGE_SET_CONFIGURATION_PATH"
    check_variable "OCP_RELEASE_CHANNEL"
    check_variable "HOSTED_ZONE_NAME"
    check_variable "TAG_NAME"
    check_variable "VPC_NAME"
    check_variable "IGW_NAME"
    check_variable "PUBLIC_RTB_NAME"
    check_variable "PRIVATE_RTB_NAME"
    check_variable "S3_ENDPOINT_NAME"
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
    for var in "${missing_variables[@]}"; do
        echo "failed: [$var]"
    done
else
    echo "ok: [all variables are set]"
fi

# Add an empty line after the task
echo
# ====================================================
