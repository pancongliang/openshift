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

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}


# === Delete EC2 Instance ===
PRINT_TASK "[TASK: Delete EC2 Instance]"
aws --region $REGION ec2 terminate-instances --instance-ids $(aws --region $REGION ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" --query "Reservations[].Instances[].InstanceId" --output text) >/dev/null
run_command "[Terminating instance: $INSTANCE_NAME]"

# Add an empty line after the task
echo
# ====================================================
sleep 30

# === Delete Key Pair ===
PRINT_TASK "[TASK: Delete Key Pair]"
aws --region $REGION ec2 delete-key-pair --key-name $KEY_PAIR_NAME >/dev/null
run_command "[Deleting key pair: $KEY_PAIR_NAME]"

# Add an empty line after the task
echo
# ====================================================

# === Delete ELB Endpoint ===
PRINT_TASK "[TASK: Delete ELB Endpoint]"
aws --region $REGION ec2 delete-vpc-endpoints --vpc-endpoint-ids $(aws --region $REGION ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=$ELB_ENDPOINT_NAME" --query "VpcEndpoints[].VpcEndpointId" --output text) >/dev/null
run_command "[Deleting ELB endpoint: $ELB_ENDPOINT_NAME]"

# Add an empty line after the task
echo
# ====================================================
sleep 10

# === Delete EC2 Endpoint ===
PRINT_TASK "[TASK: Delete EC2 Endpoint]"
aws --region $REGION ec2 delete-vpc-endpoints --vpc-endpoint-ids $(aws --region $REGION ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=$EC2_ENDPOINT_NAME" --query "VpcEndpoints[].VpcEndpointId" --output text) >/dev/null
run_command "[Deleting EC2 endpoint: $EC2_ENDPOINT_NAME]"

# Add an empty line after the task
echo
# ====================================================
sleep 10

# === Delete S3 Gateway VPC Endpoint ===
PRINT_TASK "[TASK: Delete S3 Gateway VPC Endpoint]"
aws --region $REGION ec2 delete-vpc-endpoints --vpc-endpoint-ids $(aws --region $REGION ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=$S3_ENDPOINT_NAME" --query "VpcEndpoints[].VpcEndpointId" --output text) >/dev/null
run_command "[Deleting S3 Gateway VPC endpoint: $S3_ENDPOINT_NAME]"

# Add an empty line after the task
echo
# ====================================================
sleep 10

# === Delete Private Hosted Zone ===
PRINT_TASK "[TASK: Delete Private Hosted Zone]"
aws --region $REGION route53 delete-hosted-zone --id $(aws --region $REGION route53 list-hosted-zones --query "HostedZones[?Name=='$DOMAIN_NAME.'].Id" --output text) >/dev/null
run_command "[Deleting private hosted zone: $DOMAIN_NAME]"

# Add an empty line after the task
echo
# ====================================================
sleep 100

# === Delete Security Group ===
PRINT_TASK "[TASK: Delete Security Group]"
aws --region $REGION ec2 delete-security-group --group-id $(aws --region $REGION ec2 describe-security-groups --filters "Name=tag:Name,Values=$SECURITY_GROUP_NAME" --query "SecurityGroups[].GroupId" --output text) >/dev/null
run_command "[Deleting security group: $SECURITY_GROUP_NAME]"

# Add an empty line after the task
echo
# ====================================================
sleep 10

# === Delete Private Subnet ===
PRINT_TASK "[TASK: Delete Private Subnet]"
aws --region $REGION ec2 delete-subnet --subnet-id $(aws --region $REGION ec2 describe-subnets --filters "Name=tag:Name,Values=${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE}" --query "Subnets[].SubnetId" --output text) >/dev/null
run_command "[Deleting private subnet: ${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE}]"

# Add an empty line after the task
echo
# ====================================================
sleep 10

# === Delete Public Subnet ===
PRINT_TASK "[TASK: Delete Public Subnet]"
aws --region $REGION ec2 delete-subnet --subnet-id $(aws --region $REGION ec2 describe-subnets --filters "Name=tag:Name,Values=${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE}" --query "Subnets[].SubnetId" --output text) >/dev/null
run_command "[Deleting public subnet: ${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE}]"

# Add an empty line after the task
echo
# ====================================================

sleep 100
# === Delete VPC ===
PRINT_TASK "[TASK: Delete VPC]"
aws --region $REGION ec2 delete-vpc --vpc-id $(aws --region $REGION ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[].VpcId" --output text) >/dev/null
run_command "[Deleting VPC: $VPC_NAME]"

# Add an empty line after the task
echo
# ====================================================

# === Delete Key Pair File ===
PRINT_TASK "[TASK: Delete Local Key Pair File]"
rm -rf $KEY_PAIR_NAME.pem >/dev/null
run_command "[Deleting local key pair file: $KEY_PAIR_NAME.pem]"
