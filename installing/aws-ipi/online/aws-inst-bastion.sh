#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export CLUSTER_NAME="copan"
export CLUSTER_API="api.$CLUSTER_NAME.xxx"
export REGION="ap-northeast-1"
export AWS_ACCESS_KEY_ID="xxxxx"
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

# Function to check command success and display appropriate message
run_command() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 1:
PRINT_TASK "TASK [Set up AWS credentials]"

# Create AWS credentials
rm -rf $HOME/.aws
mkdir -p $HOME/.aws

cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[set up aws credentials]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Get subnet information]"

# Get subnet name
SUBNET_NAME=$(aws --region $REGION ec2 describe-subnets \
    --query "Subnets[?contains(Tags[?Key=='Name'].Value | [0], '$CLUSTER_NAME')].[Tags[?Key=='Name'].Value | [0]] | [0]" \
    --output text)
run_command "[get subnet name: $SUBNET_NAME]"

# Get Cluster ID
CLUSTER_ID=$(echo $SUBNET_NAME | cut -d'-' -f1,2)
run_command "[get cluster id: $CLUSTER_ID]"

# Get availability zone
AVAILABILITY_ZONE=$(echo $SUBNET_NAME | awk -F'-' '{print $(NF-2)"-"$(NF-1)"-"$NF}')
run_command "[get availability zone: $AVAILABILITY_ZONE]"

# Get Public Subnet ID
PUBLIC_SUBNET_ID=$(aws --region $REGION ec2 describe-subnets --filters Name=tag:Name,Values=$CLUSTER_ID-subnet-public-$AVAILABILITY_ZONE | jq -r '.Subnets[].SubnetId')
run_command "[get public subnet id: $PUBLIC_SUBNET_ID]"

# Add an empty line after the task
echo


# Step 3:
PRINT_TASK "TASK [Create Security Group]"

# Get vpn name and vpc id
VPC_NAME=$(aws --region "$REGION" ec2 describe-vpcs --filters "Name=tag:Name,Values=$CLUSTER_ID*" --query "Vpcs[].Tags[?Key=='Name'].Value | [0]" --output text)
run_command "[get vpc name: $VPC_NAME]"

VPC_ID=$(aws --region "$REGION" ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[].VpcId" --output text)
run_command "[get vpc id: $VPC_ID]"

# Create security group and get security group ID
SECURITY_GROUP_NAME="$CLUSTER_ID-sg"
SECURITY_GROUP_DESCRIPTION="External SSH and all internal traffic"
SECURITY_GROUP_ID=$(aws --region $REGION ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "$SECURITY_GROUP_DESCRIPTION" --vpc-id $VPC_ID --output text)
run_command "[create security group and get security group ID: $SECURITY_GROUP_ID]"

# Add tag to security group
aws --region $REGION ec2 create-tags --resources $SECURITY_GROUP_ID --tags Key=Name,Value=$SECURITY_GROUP_NAME > /dev/null
run_command "[add tag to security group: $SECURITY_GROUP_NAME]"

# Add inbound rule - SSH
aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
run_command "[add inbound rule - ssh]"

# Add inbound rule - All traffic
aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol all --port -1 --cidr 0.0.0.0/0 > /dev/null
run_command "[add inbound rule - all traffic]"

# Add outbound rule - All traffic
aws --region $REGION ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID | grep -A 5 "IpPermissionsEgress" > /dev/null
run_command "[default existing outbound rule - all traffic]"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Create Bastion Instance]"

# Create and download the key pair file
export KEY_PAIR_NAME="$CLUSTER_ID-bastion-key"
rm -rf $HOME/.ssh/$KEY_PAIR_NAME.pem > /dev/null
aws --region $REGION ec2 delete-key-pair --key-name $KEY_PAIR_NAME > /dev/null
aws --region $REGION ec2 create-key-pair --key-name $KEY_PAIR_NAME --query 'KeyMaterial' --output text > $HOME/.ssh/$KEY_PAIR_NAME.pem
run_command "[create and download the key pair file: $HOME/.ssh/$KEY_PAIR_NAME.pem]"

# Retrieves the latest RHEL AMI ID that matches the specified name pattern
AMI_ID=$(aws --region $REGION ec2 describe-images \
    --filters "Name=name,Values=RHEL-9.3.0_HVM-*-x86_64-49-Hourly2-GP3" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)
run_command "[retrieves the latest rhel9 ami id that matches the specified name pattern: $AMI_ID]"

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
run_command "[create bastion ec2 instance: $INSTANCE_NAME]"

# Wait for instance to be in running state
aws --region $REGION ec2 wait instance-status-ok --instance-ids $INSTANCE_ID > /dev/null
run_command "[wait for $INSTANCE_ID instance to pass the status check]"

aws --region $REGION ec2 wait instance-running --instance-ids $INSTANCE_ID > /dev/null
run_command "[wait for $INSTANCE_ID instance to be in running state]"

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Get access to Bastion Instance information]"

# Modify permissions for the key pair file
chmod 400 $HOME/.ssh/$KEY_PAIR_NAME.pem > /dev/null
run_command "[modify permissions for the key pair file: $HOME/.ssh/$KEY_PAIR_NAME.pem]"

# Get the public IP address of the bastion ec2 instance
INSTANCE_IP=$(aws --region $REGION ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
run_command "[get the public ip address of the instance: $INSTANCE_IP]"

# Create access bastion machine file in current directory
rm -rf ./ocp-bastion.sh > /dev/null

cat << EOF > "./ocp-bastion.sh"
ssh -o StrictHostKeyChecking=no -i "$HOME/.ssh/$KEY_PAIR_NAME.pem" ec2-user@"$INSTANCE_IP"
EOF
run_command "[create access $INSTANCE_NAME file in current directory]"

# Modify permissions for the key pair file
chmod 777 ./ocp-bastion.sh > /dev/null
run_command "[modify permissions for the $INSTANCE_NAME file]"

# Dowload ocp login script
cat << EOF > "./ocp-login.sh"
/usr/local/bin/oc login -u admin -p redhat https://$CLUSTER_API:6443 --insecure-skip-tls-verify=true
EOF
run_command "[create access $INSTANCE_NAME file in current directory]"

# Dowload mirror-registry script
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/registry/mirror-registry/inst-mirror-registry.sh
cat <<EOF | cat - inst-mirror-registry.sh > temp && mv temp inst-registry.sh
export CLUSTER_NAME="copan"
export REGISTRY_DOMAIN_NAME="\$HOSTNAME"
export REGISTRY_ID="root"
export REGISTRY_PW="password"                         # 8 characters or more
export REGISTRY_INSTALL_PATH="\$HOME/quay-install"
EOF
run_command "[dowload mirror-registry script]"

# Dowload ocp tool script
cat << 'EOF' > inst-ocp-tool.sh
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
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 6:
PRINT_TASK "TASK [Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "vim" "bash-completion" "jq")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
sudo dnf install -y $package_list >/dev/null

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    sudo rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "ok: [installed $package package]"
    else
        echo "failed: [installed $package package]"
    fi
done

# Add an empty line after the task
echo

PRINT_TASK "TASK [Install openshift tool]"

# Delete openshift tool
files=(
    "/usr/local/bin/kubectl"
    "/usr/local/bin/oc"
    "/usr/local/bin/oc-mirror"
    "/usr/local/bin/oc-mirror.tar.gz"
)
for file in "${files[@]}"; do
    sudo rm -rf $file 2>/dev/null
done

# Function to download and install .tar.gz tools
install_tar_gz() {
    local tool_name="$1"
    local tool_url="$2"  
    # Download the tool
    curl -L -o "/usr/local/bin/$(basename "$tool_url")" "$tool_url" >/dev/null 2>&1    
    if [ $? -eq 0 ]; then
        echo "ok: [download $tool_name tool]"        
        # Extract the downloaded tool
        sudo tar xvf "/usr/local/bin/$(basename "$tool_url")" -C "/usr/local/bin/" >/dev/null 2>&1
        run_command "[unzip to /usr/local/bin/$tool_name]"
        # Remove the downloaded .tar.gz file
        sudo rm -rf "/usr/local/bin/openshift-client-linux.tar.gz" > /dev/null 
        sudo rm -rf "/usr/local/bin/oc-mirror.tar.gz" > /dev/null 
    else
        echo "failed: [download $tool_name tool]"
    fi
}

# Install .tar.gz tools
install_tar_gz "openshift-client" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz"
install_tar_gz "oc-mirror" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"

sudo chmod a+x /usr/local/bin/oc-mirror > /dev/null 
run_command "[modify /usr/local/bin/oc-mirror tool permissions]"
 
sudo echo -e "\nClientAliveInterval 120\nClientAliveCountMax 720" | sudo tee -a /etc/ssh/sshd_config >/dev/null 2>&1
sudo systemctl restart sshd >/dev/null 2>&1

# completion command:
/usr/local/bin/oc login -u admin -p redhat https://$CLUSTER_API:6443 --insecure-skip-tls-verify=true >/dev/null 2>&1
sudo bash -c '/usr/local/bin/oc completion bash >> /etc/bash_completion.d/oc_completion' >/dev/null 2>&1
source /etc/bash_completion.d/oc_completio >/dev/null 2>&1

# Add an empty line after the task
echo
EOF
run_command "[dowload ocp tool script]"

# Copy the installation script to the bastion ec2 instance
scp -o StrictHostKeyChecking=no -o LogLevel=ERROR -i $HOME/.ssh/$KEY_PAIR_NAME.pem ./inst-registry.sh ./inst-ocp-tool.sh ./ocp-login.sh ec2-user@$INSTANCE_IP:~/ > /dev/null 2> /dev/null
run_command "[copy the inst-registry.sh and inst-ocp-tool.sh script to the $INSTANCE_NAME]"

rm -rf ./inst-*.sh
rm -rf ./ocp-login.sh

# Add an empty line after the task
echo
# ====================================================
