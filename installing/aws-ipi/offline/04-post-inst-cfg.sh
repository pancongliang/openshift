#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

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
PRINT_TASK "TASK [Applying environment variables]"

source 01-set-params.sh
run_command "[applying environment variables]"

# Add an empty line after the task
echo

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Kubeconfig login]"

# kubeconfig login:
echo "export KUBECONFIG=${INSTALL}/auth/kubeconfig" >> $HOME/bash_profile
run_command "[add kubeconfig to $HOME/bash_profile]"

source $HOME/bash_profile

# completion command:
sudo bash -c '/usr/local/bin/oc completion bash >> /etc/bash_completion.d/oc_completion' || true
run_command "[add oc_completion]"

# Effective immediately
source /etc/bash_completion.d/oc_completion || true

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Create *.apps.$CLUSTER_NAME.$BASE_DOMAIN record]"

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

# Step 4:
PRINT_TASK "TASK [Disable the default OperatorHub sources]"

/usr/local/bin/oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]' > /dev/null
run_command "[ Disable the default OperatorHub sources]"

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Configuring additional trust stores for image registry access]"

# Create a configmap containing the CA certificate
oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig create configmap registry-config \
     --from-file=${REGISTRY_HOSTNAME}.${BASE_DOMAIN}..8443=/etc/pki/ca-trust/source/anchors/quay.ca.pem \
     -n openshift-config &> /dev/null
run_command "[create a configmap containing the CA certificate]"

# Additional trusted CA
oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge &> /dev/null
run_command "[additional trusted CA]"

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Create htpasswd User]"

sudo rm -rf $INSTALL_DIR/users.htpasswd
sudo htpasswd -c -B -b $INSTALL_DIR/users.htpasswd admin redhat &> /dev/null
run_command "[create a user using the htpasswd tool]"

oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$INSTALL_DIR/users.htpasswd -n openshift-config &> /dev/null
run_command "[create a secret using the users.htpasswd file]"

sudo rm -rf $INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
sudo cat  <<EOF | /usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig apply -f - > /dev/null 2>&1
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - htpasswd:
      fileData:
        name: htpasswd-secret
    mappingMethod: claim
    name: htpasswd-user
    type: HTPasswd
EOF
run_command "[setting up htpasswd authentication]"

# Grant the 'cluster-admin' cluster role to the user 'admin'
oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin &> /dev/null || true
run_command "[grant cluster-admin permissions to the admin user]"

sleep 15

# Wait for OpenShift authentication pods to be in 'Running' state
export AUTH_NAMESPACE="openshift-authentication"
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get po -n "$AUTH_NAMESPACE" --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [all oauth pods are in 'running' state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Checking the cluster status]"

# Print task title
PRINT_TASK "TASK [Check status]"

# Check cluster operator status
progress_started=false
while true; do
    operator_status=$(oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    
    if echo "$operator_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
progress_started=false

while true; do
    mcp_status=$(oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get mcp --no-headers | awk '{print $3, $4, $5}')

    if echo "$mcp_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all mcps to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 15
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all mcp have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 8:
PRINT_TASK "TASK [Login cluster information]"

echo "info: [log in to the cluster using the htpasswd user:  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo "info: [log in to the cluster using kubeconfig:  export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig]"
echo
