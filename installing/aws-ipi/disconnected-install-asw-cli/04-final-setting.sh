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


# Task: Kubeconfig login and oc completion
PRINT_TASK "[TASK: Kubeconfig login]"

# kubeconfig login:
echo "export KUBECONFIG=${INSTALL}/auth/kubeconfig" >> $HOME/bash_profile
run_command "[add kubeconfig to $HOME/bash_profile]"

# completion command:
sudo oc completion bash >> /etc/bash_completion.d/oc_completion
run_command "[add oc_completion]"

# Effective immediately
sudo source /etc/bash_completion.d/oc_completion

# Add an empty line after the task
echo
# ====================================================


# Task: Create record
PRINT_TASK "[TASK: Create *.apps.$CLUSTER_NAME record]"

# Create record
RECORD_NAME="*.apps"
RECORD_TYPE="A"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --query "HostedZones[?Name=='$DOMAIN_NAME.'].Id" --output text)
ELB_DNS_NAME=$(aws elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].DNSName" --output text)
LOAD_BALANCER_HOSTED_ZONE_ID=$(aws ec2 describe-vpc-endpoints --filters "Name=service-name,Values=com.amazonaws.$REGION.elasticloadbalancing" --query "VpcEndpoints[0].ServiceDetails.AvailabilityZones[0].LoadBalancers[0].CanonicalHostedZoneId" --output text)
aws route53 create-record --hosted-zone-id $HOSTED_ZONE_ID --name "$RECORD_NAME.$CLUSTER_NAME" --type $RECORD_TYPE --alias-target "HostedZoneId=$LOAD_BALANCER_HOSTED_ZONE_ID,DNSName=$ELB_DNS_NAME" --region $REGION
run_command "[ Create *.apps.$CLUSTER_NAME record]"

# Add an empty line after the task
echo
# ====================================================


# Task: Configure cluster DNS
PRINT_TASK "[TASK: Configure cluster DNS]"

oc patch dnses.config.openshift.io/cluster --type=merge --patch='{"spec": {"privateZone": null}}'
run_command "[ Delete dnses.config.openshift.io/cluster.spec.privateZone]"

# Add an empty line after the task
echo
# ====================================================


# Task: Disable the default OperatorHub sources
PRINT_TASK "[TASK: Disable the default OperatorHub sources]"

oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
run_command "[ Disable the default OperatorHub sources]"


