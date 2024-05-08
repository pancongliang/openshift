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
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" > /dev/null 
    unzip awscliv2.zip > /dev/null 
    sudo ./aws/install &>/dev/null || true
    run_command "[Install AWS CLI]"
    sudo rm -rf aws awscliv2.zip
}

# Function to install AWS CLI on macOS
install_awscli_mac() {
    curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" > /dev/null 
    sudo installer -pkg AWSCLIV2.pkg -target / &>/dev/null || true
    run_command "[Install AWS CLI]"
    sudo rm -rf AWSCLIV2.pkg
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



# === Task: Create VPC ===
PRINT_TASK "[TASK: Create VPC]"

# Create VPC and get VPC ID
VPC_ID=$(aws --region $REGION ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text)
run_command "[Create VPC and get VPC ID: $VPC_ID]"

# Add tag to VPC
aws --region $REGION ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
run_command "[Add tag to VPC: $VPC_NAME]"

# Enable DNS hostnames for the VPC
aws --region $REGION ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
run_command "[Enable DNS hostnames for the VPC: $VPC_ID]"

# Enable DNS resolve for the VPC
aws --region $REGION ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
run_command "[Enable DNS resolve for the VPC: $VPC_ID]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create Subnets ===
PRINT_TASK "[TASK: Create Subnet]"

# Create public subnet and get public subnet ID
PUBLIC_SUBNET_ID=$(aws --region $REGION ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_CIDR --availability-zone $AVAILABILITY_ZONE --query 'Subnet.SubnetId' --output text)
run_command "[Create public subnet and get public subnet ID: $PUBLIC_SUBNET_ID]"

# Add tag name to public subnet 
aws --region $REGION ec2 create-tags --resources $PUBLIC_SUBNET_ID --tags Key=Name,Value="${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE}"
run_command "[Add tag name to subnet name: ${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE}]"

# Create priavate subnet and get priavate subnet ID
PRIVATE_SUBNET_ID=$(aws --region $REGION ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_CIDR --availability-zone $AVAILABILITY_ZONE --query 'Subnet.SubnetId' --output text)
run_command "[Create private subnet and get subnet ID: $PRIVATE_SUBNET_ID]"

# Add tag name to priavate subnet
aws --region $REGION ec2 create-tags --resources $PRIVATE_SUBNET_ID --tags Key=Name,Value="${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE}"
run_command "[Add tag name to subnet name: ${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE}]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create Internet Gateway ===
PRINT_TASK "[TASK: Create Internet Gateway]"

# Create Internet Gateway
IGW_ID=$(aws --region $REGION ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
run_command "[Create Internet Gateway: $IGW_ID]"

# Add tag to Internet Gateway
aws --region $REGION ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="$IGW_NAME"
run_command "[Add tag to Internet Gateway: $IGW_NAME]"

# Attach Internet Gateway to VPC
aws --region $REGION ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
run_command "[Attach Internet Gateway $IGW_ID to VPC: $VPC_ID]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create Routing Table ===
PRINT_TASK "[TASK: Create Routing Table]"

# Create public Route Table
PUBLIC_ROUTE_TABLE_ID=$(aws --region $REGION ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
run_command "[Create public Route Table: $PUBLIC_ROUTE_TABLE_ID]"

# Add tag to public Route Table
aws --region $REGION ec2 create-tags --resources $PUBLIC_ROUTE_TABLE_ID --tags Key=Name,Value="$PUBLIC_RTB_NAME"  > /dev/null
run_command "[Add tag to public Route Table: $PUBLIC_RTB_NAME]"

# Create private Route Table
PRIVATE_ROUTE_TABLE_ID=$(aws --region $REGION ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
run_command "[Create private Route Table: $PRIVATE_ROUTE_TABLE_ID]"

# Add tag to private Route Table
aws --region $REGION ec2 create-tags --resources $PRIVATE_ROUTE_TABLE_ID --tags Key=Name,Value="$PRIVATE_RTB_NAME"  > /dev/null
run_command "[Add tag to private Route Table: $PRIVATE_RTB_NAME]"

# Link public Route Table to Internet Gateway
aws --region $REGION ec2 create-route --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --route-table-id $PUBLIC_ROUTE_TABLE_ID > /dev/null
run_command "[Link public Route Table to Internet Gateway]"

# Associate public Route Table with public subnet
aws --region $REGION ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $PUBLIC_ROUTE_TABLE_ID > /dev/null       
run_command "[Associate public Route Table with public subnet]"

# Associate private Route Table with private subnet
aws --region $REGION ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID > /dev/null
run_command "[Associate private Route Table with private subnet]"



# Add an empty line after the task
echo
# ====================================================

# === Task: Create Security Group ===
PRINT_TASK "[TASK: Create Security Group]"

# Create security group and get security group ID
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
aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol all --port -1 --cidr 10.0.0.0/16 > /dev/null
run_command "[Add inbound rule - All traffic]"

# Add outbound rule - All traffic
# aws --region $REGION ec2 authorize-security-group-egress --group-id $SECURITY_GROUP_ID --protocol all --port all --cidr 0.0.0.0/0 > /dev/null
# run_command "[Add outbound rule - All traffic]"
aws --region $REGION ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID | grep -A 5 "IpPermissionsEgress" > /dev/null
run_command "[Default existing outbound rule - All traffic]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create the VPC Endpoint for the S3 Service===
PRINT_TASK "[TASK: Create the VPC Endpoint for the S3 Service]"

# Create the VPC endpoint for the S3 Service and get endpoint ID
S3_ENDPOINT_ID=$(aws --region $REGION ec2 create-vpc-endpoint --vpc-endpoint-type Gateway --vpc-id $VPC_ID --service-name com.amazonaws.$REGION.s3 --route --route-table-ids $PRIVATE_ROUTE_TABLE_ID --no-private-dns-enabled --query 'VpcEndpoint.VpcEndpointId' --output text)
run_command "[Create the VPC endpoint for the s3 Service: S3_ENDPOINT_ID]"

# Add tag to S3 Service endpoint
aws --region $REGION ec2 create-tags --resources $S3_ENDPOINT_ID --tags Key=Name,Value="$S3_ENDPOINT_NAME" > /dev/null
run_command "[Add tag to S3 Service endpoint: $S3_ENDPOINT_NAME]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create the VPC Endpoint for the ELB Service ===
PRINT_TASK "[TASK: Create the VPC Endpoint for the ELB Service]"

# Create the VPC endpoint for the ELB Service and get endpoint ID
ELB_ENDPOINT_ID=$(aws --region $REGION ec2 create-vpc-endpoint --vpc-endpoint-type Interface --vpc-id ${VPC_ID} --service-name com.amazonaws.$REGION.elasticloadbalancing --subnet-ids ${PRIVATE_SUBNET_ID} --private-dns-enabled --query 'VpcEndpoint.VpcEndpointId' --output text)
run_command "[Create the VPC endpoint for the ELB Service: $ELB_ENDPOINT_ID]"

# Add tag to ELB Service endpoint
aws --region $REGION ec2 create-tags --resources $ELB_ENDPOINT_ID --tags Key=Name,Value="$ELB_ENDPOINT_NAME" > /dev/null
run_command "[Add tags to EC2 Service endpoint: $ELB_ENDPOINT_NAME]"

# Obtain default security group IDs associated with the ELB endpoint
ELB_ENDPOINT_SG_DEFAULT=$(aws --region $REGION ec2 describe-vpc-endpoints --vpc-endpoint-ids $ELB_ENDPOINT_ID | jq -r '.VpcEndpoints[].Groups[].GroupId' | uniq > /dev/null)
run_command "[Obtain default security group IDs associated with the ELB endpoint]"

# Add the default security group IDs and the $SECURITY_GROUP_NAME security group ID to the ELB endpoint
aws --region $REGION ec2 modify-vpc-endpoint --vpc-endpoint-id ${ELB_ENDPOINT_ID} --add-security-group-ids ${ELB_ENDPOINT_SG_DEFAULT} --add-security-group-ids ${SECURITY_GROUP_ID} > /dev/null 
run_command "[Add default security groups and provided security group to ELB endpoint]"

# Remove default security group IDs from the ELB endpoint
aws --region $REGION ec2 modify-vpc-endpoint --vpc-endpoint-id ${ELB_ENDPOINT_ID} --remove-security-group-ids ${ELB_ENDPOINT_SG_DEFAULT} > /dev/null
run_command "[Remove default security group IDs from ELB endpoint]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create the VPC Endpoint for the EC2 Service ===
PRINT_TASK "[TASK: Create the VPC Endpoint for the EC2 Service]"

# Create the VPC endpoint for the EC2 Service and get endpoint ID
EC2_ENDPOINT_ID=$(aws --region $REGION ec2 create-vpc-endpoint --vpc-endpoint-type Interface --vpc-id ${VPC_ID} --service-name com.amazonaws.$REGION.ec2 --subnet-ids $PRIVATE_SUBNET_ID --private-dns-enabled --query 'VpcEndpoint.VpcEndpointId' --output text)
run_command "[Create the VPC endpoint for the EC2 Service: $EC2_ENDPOINT_ID]"

# Add tag to EC2 Service endpoint
aws --region $REGION ec2 create-tags --resources $EC2_ENDPOINT_ID --tags Key=Name,Value="$EC2_ENDPOINT_NAME" > /dev/null
run_command "[Add tags to EC2 Service endpoint: $EC2_ENDPOINT_NAME]"

# Obtain default security group IDs associated with the EC2 endpoint
EC2_ENDPOINT_SG_DEFAULT=$(aws --region $REGION ec2 describe-vpc-endpoints --vpc-endpoint-ids $EC2_ENDPOINT_ID | jq -r '.VpcEndpoints[].Groups[].GroupId' | uniq > /dev/null)
run_command "[Obtain default security group IDs associated with the EC2 endpoint]"

# Add the default security group IDs and the $SECURITY_GROUP_NAME security group ID to the EC2 endpoint
aws --region $REGION ec2 modify-vpc-endpoint --vpc-endpoint-id ${EC2_ENDPOINT_ID} --add-security-group-ids ${EC2_ENDPOINT_SG_DEFAULT} --add-security-group-ids ${SECURITY_GROUP_ID} > /dev/null
run_command "[Add default security groups and provided security group to EC2 endpoint]"

# Remove default security group IDs from the EC2 endpoint
aws --region $REGION ec2 modify-vpc-endpoint --vpc-endpoint-id ${EC2_ENDPOINT_ID} --remove-security-group-ids ${EC2_ENDPOINT_SG_DEFAULT} > /dev/null
run_command "[Remove default security group IDs from EC2 endpoint]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create Private Hosted Zone ===
PRINT_TASK "[TASK: Create Private Hosted Zone]"

# Create private hosted zone
HOSTED_ZONE_ID=$(aws --region $REGION route53 create-hosted-zone \
    --name $HOSTED_ZONE_NAME \
    --caller-reference "$(date +%Y%m%d%H%M%S)" \
    --hosted-zone-config Comment="$TAG_NAME-test" \
    --vpc "VPCRegion=$REGION,VPCId=$VPC_ID" \
    --query 'HostedZone.Id' \
    --output text | sed 's/\/hostedzone\///')    
run_command "[Create private hosted zone and get PHZ ID: $HOSTED_ZONE_ID]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Create Bastion Instance ===
PRINT_TASK "[TASK: Create Bastion Instance]"

# Create and download the key pair file
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
aws --region $REGION  ec2 wait instance-status-ok --instance-ids $INSTANCE_ID > /dev/null
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

# Copy the installation script to the bastion ec2 instance
scp -o StrictHostKeyChecking=no -o LogLevel=ERROR -i ./$KEY_PAIR_NAME.pem ./00-del-aws-res.sh ./01-set-parameter.sh ./03-install-pre.sh ./04-final-setting.sh ec2-user@$INSTANCE_IP:~/ > /dev/null 2> /dev/null
run_command "[Copy the installation script to the $INSTANCE_NAME]"

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
