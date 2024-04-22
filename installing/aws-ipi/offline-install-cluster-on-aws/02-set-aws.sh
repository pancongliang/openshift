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


# === Task: Install AWS CLI ===
PRINT_TASK "[TASK: Install AWS CLI]"

# Function to install AWS CLI on Linux
install_awscli_linux() {
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install &>/dev/null || true
    run_command "[Install AWS CLI]"
    sudo rm -rf aws awscliv2.zip
}

# Function to install AWS CLI on macOS
install_awscli_mac() {
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
    sudo installer -pkg AWSCLIV2.pkg -target / || true
    run_command "[Install AWS CLI]"
}

# Function to print a task with uniform length
run_command() {
    echo "$1"
}

# Detecting the operating system
os=$(uname -s)

# Installing AWS CLI based on the operating system
case "$os" in
    Linux*)  install_awscli_linux;;
    Darwin*) install_awscli_mac;;
    *) ;;
esac

# Add an empty line after the task
echo
# ====================================================


# === Task: Set up AWS credentials ===
PRINT_TASK "[TASK: Set up AWS credentials]"

cat << EOF > "$HOME/.aws/credentials"
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[TASK: Set up AWS credentials]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create VPC ===
PRINT_TASK "[TASK: Create VPC]"

# Create VPC and get VPC ID
VPC_ID=$(aws --region $REGION ec2 create-vpc --cidr-block $VPC_CIDR --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" --query 'Vpc.VpcId' --output text)
run_command "[Create VPC and get VPC ID: $VPC_ID]"

# Add name tag to VPC
# aws --region $REGION ec2 create-tags --resources $VPC_ID  --tags Key=Name,Value=$VPC_NAME
# run_command "[Add name tag to VPC: $VPC_NAME]"

# Create public subnet and get public subnet ID
PUBLIC_SUBNET_ID=$(aws --region $REGION ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_CIDR --availability-zone $AVAILABILITY_ZONE --query 'Subnet.SubnetId' --output text)
run_command "[Create public subnet and get public subnet ID: $PUBLIC_SUBNET_ID]"

# Create private subnet and get subnet ID
PRIVATE_SUBNET_ID=$(aws --region $REGION ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_CIDR --availability-zone $AVAILABILITY_ZONE --query 'Subnet.SubnetId' --output text)
run_command "[Create private subnet and get private subnet ID: $PRIVATE_SUBNET_ID]"

# Add VPC name to subnet name
aws --region $REGION ec2 create-tags --resources $PUBLIC_SUBNET_ID --tags Key=Name,Value="${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE}"
run_command "[Add VPC name to subnet name: ${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE}]"

aws --region $REGION ec2 create-tags --resources $PRIVATE_SUBNET_ID --tags Key=Name,Value="${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE}"
run_command "[Add VPC name to subnet name: ${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE}]"

# Enable DNS hostnames for the VPC
aws --region $REGION ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
run_command "[Enable DNS hostnames for the VPC: $VPC_ID VPC]"

# Enable DNS resolution for the VPC
aws --region $REGION ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
run_command "[Enable DNS resolution for the VPC: $VPC_ID]"

# Create S3 Gateway VPC endpoint
S3_ENDPOINT_ID=$(aws --region $REGION ec2 create-vpc-endpoint --vpc-id $VPC_ID --service-name $S3_SERVICE_NAME --query 'VpcEndpoint.VpcEndpointId' --output text)
run_command "[Create S3 Gateway VPC endpoint]"

# Add tag to S3 Gateway VPC endpoint
aws --region $REGION ec2 create-tags --resources $S3_ENDPOINT_ID --tags Key=Name,Value="$S3_ENDPOINT_NAME"
run_command "[Add tag to S3 Gateway VPC endpoint: $S3_ENDPOINT_NAME]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create security group ===
PRINT_TASK "[TASK: Create security group]"

# Create security group and get security group ID
SECURITY_GROUP_DESCRIPTION="External SSH and all internal traffic"
SECURITY_GROUP_ID=$(aws --region $REGION ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "$SECURITY_GROUP_DESCRIPTION" --vpc-id $VPC_ID --output text)
run_command "[Create security group and get security group ID: SECURITY_GROUP_ID]"

# Add inbound rule - SSH
aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
run_command "[Add inbound rule - SSH]"

# Add inbound rule - All traffic
aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol all --port -1 --cidr 10.0.0.0/16
run_command "[Add inbound rule - All traffic]"

# Add outbound rule - All traffic
aws --region $REGION ec2 authorize-security-group-egress --group-id $SECURITY_GROUP_ID --protocol all --port -1 --cidr 0.0.0.0/0
run_command "[Add outbound rule - All traffic]"

# Add tags
aws --region $REGION ec2 create-tags --resources $SECURITY_GROUP_ID --tags Key=Name,Value=$SECURITY_GROUP_NAME
run_command "[Add tags: $SECURITY_GROUP_NAME]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Create EC2 endpoint===
PRINT_TASK "[TASK: Create EC2 endpoint]"

# Create EC2 endpoint
aws --region $REGION ec2 create-vpc-endpoint --vpc-endpoint-type Interface --vpc-id $VPC_ID --service-name com.amazonaws.$REGION.ec2 --subnet-ids $PRIVATE_SUBNET_ID --security-group-ids $SECURITY_GROUP_ID --policy-document "{\"Statement\":[{\"Action\":\"*\",\"Effect\":\"Allow\",\"Resource\":\"*\",\"Principal\":\"*\"}]}" --dns-enable --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$EC2_ENDPOINT_NAME}]"
run_command "[Create EC2 endpoint: $EC2_ENDPOINT_NAME]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Create ELB endpoint===
PRINT_TASK "[TASK: Create ELB endpoint]"

# Create ELB endpoint
aws --region $REGION ec2 create-vpc-endpoint --vpc-endpoint-type Interface --vpc-id $VPC_ID --service-name com.amazonaws.$REGION.elasticloadbalancing --subnet-ids $PRIVATE_SUBNET_ID --security-group-ids $SECURITY_GROUP_ID --policy-document "{\"Statement\":[{\"Action\":\"*\",\"Effect\":\"Allow\",\"Resource\":\"*\",\"Principal\":\"*\"}]}" --dns-enable --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$ELB_ENDPOINT_NAME}]"
run_command "[Create ELB endpoint: $ELB_ENDPOINT_NAME]"

aws --region $REGION elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].DNSName"

# Add an empty line after the task
echo
# ====================================================


# === Task: Create private hosted zone===
PRINT_TASK "[TASK: Create private hosted zone]"

# Create private hosted zone
HOSTED_ZONE_ID=$(aws --region $REGION route53 create-private-hosted-zone --name $DOMAIN_NAME --vpc "VPCRegion=$REGION,VPCId=$VPC_ID" --query 'HostedZone.Id' --output text)
run_command "[Create private hosted zone: $HOSTED_ZONE_ID]"

# Create record
RECORD_NAME="*.apps.$CLUSTER_NAME"
RECORD_TYPE="A"
ELB_DNS_NAME=$(aws --region $REGION elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].DNSName" --output text)
LOAD_BALANCER_HOSTED_ZONE_ID=$(aws --region $REGION ec2 describe-vpc-endpoints --filters "Name=service-name,Values=com.amazonaws.$REGION.elasticloadbalancing" --query "VpcEndpoints[0].ServiceDetails.AvailabilityZones[0].LoadBalancers[0].CanonicalHostedZoneId" --output text)
aws route53 create-record --hosted-zone-id $HOSTED_ZONE_ID --name "$RECORD_NAME.$DOMAIN_NAME" --type $RECORD_TYPE --alias-target "HostedZoneId=$LOAD_BALANCER_HOSTED_ZONE_ID,DNSName=$ELB_DNS_NAME" --region $REGION

# Add an empty line after the task
echo
# ====================================================


# === Task: Create bastion instance ===
PRINT_TASK "[TASK: Create bastion instance]"

# Launch instance
INSTANCE_ID=$(aws --region $REGION ec2 run-instances --image-id $AMI_ID --instance-type t3.large --subnet-id $PUBLIC_SUBNET_CIDR --security-group-ids $SECURITY_GROUP_ID --key-name $KEY_PAIR_NAME --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$STORAGE_SIZE,\"VolumeType\":\"gp2\"}}]" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" --query "Instances[0].InstanceId" --output text)
run_command "[Create instance: $INSTANCE_NAME]"

# Wait for instance to be in running state
aws --region $REGION ec2 wait instance-running --instance-ids $INSTANCE_ID
run_command "[Wait for instance to be in running state]"

# Download the key pair file
aws --region $REGION ec2 create-key-pair --key-name $KEY_PAIR_NAME --query 'KeyMaterial' --output text > $KEY_PAIR_NAME.pem
run_command "[Download the key pair file: $KEY_PAIR_NAME.pem]"

# Modify permissions for the key pair file
chmod 400 $KEY_PAIR_NAME.pem
run_command "[Modify permissions for the key pair file: $KEY_PAIR_NAME.pem]"

# Get the public IP address of the instance
while true; do
    INSTANCE_IP=$(aws --region $REGION ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    if [ -n "$INSTANCE_IP" ]; then
        break
    fi
    sleep 10 
done
run_command "[Get the public IP address of the instance: $INSTANCE_IP]"

# Add an empty line after the task
echo
# ====================================================


# SSH into the instance
ssh -i $KEY_PAIR_NAME.pem ec2-user@$INSTANCE_IP

