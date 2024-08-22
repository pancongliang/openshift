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


# Task: Kubeconfig login and oc completion
PRINT_TASK "[TASK: Kubeconfig login]"

# kubeconfig login:
echo "export KUBECONFIG=${INSTALL}/auth/kubeconfig" >> $HOME/bash_profile
run_command "[add kubeconfig to $HOME/bash_profile]"

source $HOME/bash_profile

# completion command:
sudo bash -c '/usr/local/bin/oc completion bash >> /etc/bash_completion.d/oc_completion'
run_command "[add oc_completion]"

# Effective immediately
source /etc/bash_completion.d/oc_completion

# Add an empty line after the task
echo
# ====================================================


# Task: Create record
PRINT_TASK "[TASK: Create *.apps.$CLUSTER_NAME.$BASE_DOMAIN record]"

# Create *.apps.$CLUSTER_NAME.$BASE_DOMAIN record
RECORD_NAME="*.apps"
RECORD_TYPE="A"
HOSTED_ZONE_ID=$(aws --region $REGION route53 list-hosted-zones --query "HostedZones[?Name=='$HOSTED_ZONE_NAME.'].Id" --output text | awk -F'/' '{print $3}')
VPC_ID=$(aws --region $REGION ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[].VpcId" --output text)
ELB_DNS_NAME=$(aws --region $REGION elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].DNSName" --output text)
ELB_HOSTED_ZONE_ID=$(aws --region $REGION elb describe-load-balancers --query "LoadBalancerDescriptions[?DNSName=='$ELB_DNS_NAME'].CanonicalHostedZoneNameID" --output text)

change_batch='{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "*.apps.'$CLUSTER_NAME'.'$BASE_DOMAIN'",
                "Type": "A",
                "AliasTarget": {
                    "HostedZoneId": "'$ELB_HOSTED_ZONE_ID'",
                    "DNSName": "'dualstack.$ELB_DNS_NAME'",
                    "EvaluateTargetHealth": true
                }
            }
        }
    ]
}'

aws --region $REGION route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch "$change_batch" > /dev/null
run_command "[ Create *.apps.$CLUSTER_NAME.$BASE_DOMAIN record]"

# Add an empty line after the task
echo
# ====================================================


# Task: Disable the default OperatorHub sources
PRINT_TASK "[TASK: Disable the default OperatorHub sources]"

oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]' > /dev/null
run_command "[ Disable the default OperatorHub sources]"


