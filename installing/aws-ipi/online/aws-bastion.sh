#!/bin/bash

export CLUSTER_NAME="copan"
export REGION="ap-northeast-1"
export AWS_ACCESS_KEY_ID="xxxx"
export AWS_SECRET_ACCESS_KEY="xxxxx"
export STORAGE_SIZE="100" 

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

# === Task: Set up AWS credentials ===
PRINT_TASK "[TASK: Set up AWS credentials]"
rm -rf $HOME/.aws
mkdir -p $HOME/.aws
cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[Set up AWS credentials]"

# Add an empty line after the task
echo
# ====================================================

# === Task: Get subnet information ===
PRINT_TASK "[TASK: Get subnet information]"

# Get subnet name
SUBNET_NAME=$(aws --region $REGION ec2 describe-subnets \
    --query "Subnets[?contains(Tags[?Key=='Name'].Value | [0], '$CLUSTER_NAME')].[Tags[?Key=='Name'].Value | [0]] | [0]" \
    --output text)
run_command "[Get subnet name: $SUBNET_NAME]"

# Get Cluster ID
CLUSTER_ID=$(echo $SUBNET_NAME | cut -d'-' -f1,2)
run_command "[Get Cluster ID: $CLUSTER_ID]"

# Get availability zone
AVAILABILITY_ZONE=$(echo $SUBNET_NAME | awk -F'-' '{print $(NF-2)"-"$(NF-1)"-"$NF}')
run_command "[Get Availability Zone: $AVAILABILITY_ZONE]"

# Get Public Subnet ID
PUBLIC_SUBNET_ID=$(aws --region $REGION ec2 describe-subnets --filters Name=tag:Name,Values=$CLUSTER_ID-subnet-public-$AVAILABILITY_ZONE | jq -r '.Subnets[].SubnetId')
run_command "[Get Public Subnet ID: $PUBLIC_SUBNET_ID]"

# Add an empty line after the task
echo
# ====================================================

# === Task: Create Security Group ===
PRINT_TASK "[TASK: Create Security Group]"

# Get vpn name and vpc id
VPC_NAME=$(aws --region "$REGION" ec2 describe-vpcs --filters "Name=tag:Name,Values=$CLUSTER_ID*" --query "Vpcs[].Tags[?Key=='Name'].Value | [0]" --output text)
run_command "[Get vpc name: $VPC_NAME]"

VPC_ID=$(aws --region "$REGION" ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[].VpcId" --output text)
run_command "[Get vpc id: $VPC_ID]"

# Create security group and get security group ID
SECURITY_GROUP_NAME="$CLUSTER_ID-sg"
SECURITY_GROUP_DESCRIPTION="External SSH and all internal traffic"
SECURITY_GROUP_ID=$(aws --region $REGION ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "$SECURITY_GROUP_DESCRIPTION" --vpc-id $VPC_ID --output text)
run_command "[Create security group and get security group ID: $SECURITY_GROUP_ID]"

# Add tag to security group
aws --region $REGION ec2 create-tags --resources $SECURITY_GROUP_ID --tags Key=Name,Value=$SECURITY_GROUP_NAME > /dev/null
run_command "[Add tag to security group: $SECURITY_GROUP_NAME]"

# Add inbound rule - SSH
aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
run_command "[Add inbound rule - SSH]"

# Add inbound rule - All traffic
aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol all --port -1 --cidr 0.0.0.0/0 > /dev/null
run_command "[Add inbound rule - All traffic]"

# Add outbound rule - All traffic
aws --region $REGION ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID | grep -A 5 "IpPermissionsEgress" > /dev/null
run_command "[Default existing outbound rule - All traffic]"

# Add an empty line after the task
echo
# ====================================================

# === Task: Create Bastion Instance ===
PRINT_TASK "[TASK: Create Bastion Instance]"

# Create and download the key pair file
export KEY_PAIR_NAME="bastion-ec2-key"
rm -rf ./$KEY_PAIR_NAME.pem > /dev/null
aws --region $REGION ec2 delete-key-pair --key-name $KEY_PAIR_NAME > /dev/null
aws --region $REGION ec2 create-key-pair --key-name $KEY_PAIR_NAME --query 'KeyMaterial' --output text > ./$KEY_PAIR_NAME.pem
run_command "[Create and download the key pair file: $KEY_PAIR_NAME.pem]"

# Retrieves the latest RHEL AMI ID that matches the specified name pattern
AMI_ID=$(aws --region $REGION ec2 describe-images \
    --filters "Name=name,Values=RHEL-9.3.0_HVM-*-x86_64-49-Hourly2-GP3" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)
run_command "[Retrieves the latest RHEL9 AMI ID that matches the specified name pattern: $AMI_ID]"

# Create bastion ec2 instance
INSTANCE_NAME="$CLUSTER_ID-bastion"
INSTANCE_ID=$(aws --region $REGION ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.large \
    --subnet-id $PUBLIC_SUBNET_ID \
    --security-group-ids $SECURITY_GROUP_ID \
    --key-name $KEY_PAIR_NAME \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$STORAGE_SIZE,\"VolumeType\":\"gp2\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --associate-public-ip-address \
    --query "Instances[0].InstanceId" \
    --output text
)
run_command "[Create bastion ec2 instance: $INSTANCE_NAME]"

# Wait for instance to be in running state
aws --region $REGION ec2 wait instance-status-ok --instance-ids $INSTANCE_ID > /dev/null
run_command "[Wait for $INSTANCE_ID instance to pass the status check]"

aws --region $REGION ec2 wait instance-running --instance-ids $INSTANCE_ID > /dev/null
run_command "[Wait for $INSTANCE_ID instance to be in running state]"

# Add an empty line after the task
echo
# ====================================================

# === Task: Get access to Bastion Instance information ===
PRINT_TASK "[TASK: Get access to Bastion Instance information]"

# Modify permissions for the key pair file
chmod 400 $KEY_PAIR_NAME.pem > /dev/null
run_command "[Modify permissions for the key pair file: $KEY_PAIR_NAME.pem]"

# Get the public IP address of the bastion ec2 instance
INSTANCE_IP=$(aws --region $REGION ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
run_command "[Get the public IP address of the instance: $INSTANCE_IP]"

# Create access bastion machine file in current directory
rm -rf ./ocp-bastion.sh > /dev/null
cat << EOF > "./ocp-bastion.sh"
ssh -o StrictHostKeyChecking=no -i "$KEY_PAIR_NAME.pem" ec2-user@"$INSTANCE_IP"
EOF
run_command "[Create access $INSTANCE_NAME file in current directory]"

# Modify permissions for the key pair file
chmod 777 ./ocp-bastion.sh > /dev/null
run_command "[Modify permissions for the $INSTANCE_NAME file]"

# Add an empty line after the task
echo
# ====================================================
