#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: Command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export CLUSTER_NAME="copan"
export REGION="ap-northeast-1"
export AWS_ACCESS_KEY_ID="xxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxx"

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
run_command "[Set up aws credentials]"

# https://docs.aws.amazon.com/vpc/latest/userguide/delete-vpc.html#delete-vpc-cli

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Delete EC2 Instance]"

# Get subnet name
SUBNET_NAME=$(aws --region $REGION ec2 describe-subnets \
    --query "Subnets[?contains(Tags[?Key=='Name'].Value | [0], '$CLUSTER_NAME')].[Tags[?Key=='Name'].Value | [0]] | [0]" \
    --output text)
run_command "[Get subnet name: $SUBNET_NAME]"

# Get Cluster ID
CLUSTER_ID=$(echo $SUBNET_NAME | cut -d'-' -f1,2)
run_command "[Get Cluster ID: $CLUSTER_ID]"

INSTANCE_NAME="$CLUSTER_ID-bastion"
INSTANCE_ID=$(aws --region $REGION ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" --query "Reservations[].Instances[].InstanceId" --output text)
aws --region $REGION ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null
run_command "[Terminating instance: $INSTANCE_NAME]"

# Wait for deletion to complete
aws --region $REGION ec2 wait instance-terminated --instance-ids $INSTANCE_ID

sleep 5

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Delete Key Pair]"

export KEY_PAIR_NAME="$CLUSTER_ID-bastion-key"
rm -rf $HOME/.ssh/$KEY_PAIR_NAME.pem  > /dev/null
rm -rf ocp-bastion.sh > /dev/null
aws --region $REGION ec2 delete-key-pair --key-name $KEY_PAIR_NAME > /dev/null
run_command "[Delete key pair: $KEY_PAIR_NAME]"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Delete Security Group]"

SECURITY_GROUP_NAME="$CLUSTER_ID-sg"
SECURITY_GROUP_ID=$(aws --region $REGION ec2 describe-security-groups --filters "Name=tag:Name,Values=$SECURITY_GROUP_NAME" --query "SecurityGroups[].GroupId" --output text)
aws --region $REGION ec2 delete-security-group --group-id $SECURITY_GROUP_ID > /dev/null
run_command "[Delete security group: $SECURITY_GROUP_NAME]"

# Add an empty line after the task
echo
