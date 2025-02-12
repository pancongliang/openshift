#!/bin/bash
set -u

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

# Applying environment variables
source 01-set-params.sh


# Task: Kubeconfig login and oc completion
PRINT_TASK "[TASK: Kubeconfig login]"

# kubeconfig login:
cp ${INSTALL_DIR}/auth/kubeconfig ${INSTALL_DIR}/auth/kubeconfigbk &> /dev/null
echo "export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" >> ~/.bash_profile
run_command "[add kubeconfig to ~/.bash_profile]"

# completion command:
oc completion bash >> /etc/bash_completion.d/oc_completion &> /dev/null
run_command "[add oc_completion]"

# Effective immediately
source /etc/bash_completion.d/oc_completion &> /dev/null

# Add an empty line after the task
echo
# ====================================================


# Task: Configure data persistence for the image-registry operator
PRINT_TASK "[TASK: Configure data persistence for the image-registry operator]"

rm -rf ${NFS_DIR}/${IMAGE_REGISTRY_PV} &> /dev/null
mkdir -p ${NFS_DIR}/${IMAGE_REGISTRY_PV} &> /dev/null
run_command "[create ${NFS_DIR}/${IMAGE_REGISTRY_PV} director]"

cat << EOF > /tmp/${IMAGE_REGISTRY_PV}.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${IMAGE_REGISTRY_PV}
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: ${NFS_DIR}/${IMAGE_REGISTRY_PV}
    server: ${NFS_SERVER_IP}
  persistentVolumeReclaimPolicy: Retain
EOF
run_command "[create ${IMAGE_REGISTRY_PV}.yaml file]"

oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig apply -f /tmp/${IMAGE_REGISTRY_PV}.yaml &> /dev/null
run_command "[apply ${IMAGE_REGISTRY_PV} pv]"

rm -f /tmp/${IMAGE_REGISTRY_PV}.yaml
run_command "[remove ${IMAGE_REGISTRY_PV}.yaml file]"


# Change the Image registry operator configuration’s managementState from Removed to Managed
oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}' &> /dev/null
run_command "[change the Image registry operator configuration’s managementState from Removed to Managed]"

# Leave the claim field blank to allow the automatic creation of an image-registry-storage PVC.
oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}' &> /dev/null
run_command "[leave the claim field blank to allow the automatic creation of an image-registry-storage PVC]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Create htpasswd User ===
PRINT_TASK "[TASK: Create htpasswd User]"

rm -rf $INSTALL_DIR/users.htpasswd
htpasswd -c -B -b $INSTALL_DIR/users.htpasswd admin redhat &> /dev/null
run_command "[create a user using the htpasswd tool]"

oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$INSTALL_DIR/users.htpasswd -n openshift-config &> /dev/null
run_command "[create a secret using the users.htpasswd file]"

rm -rf $INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
cat  <<EOF | /usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig apply -f - > /dev/null 2>&1
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
oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin &> /dev/null
run_command "[grant cluster-admin permissions to the admin user]"

sleep 15

# Wait for OpenShift authentication pods to be in 'Running' state
export AUTH_NAMESPACE="openshift-authentication"
# Initialize progress_started as false
progress_started=false

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$AUTH_NAMESPACE" --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 15
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [all oauth pods are in 'running' state]"
        break
    fi
done

echo
# ====================================================


# === Task: Checking the cluster status ===
PRINT_TASK "[TASK: Checking the cluster status]"

# Initialize progress tracking
progress_started=false
while true; do
    # Get the status of all cluster operators
    operator_status=$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')

    # Check if any operator has not reached the expected state
    if echo "$operator_status" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to not reach the expected state"
            progress_started=true  # Mark progress as started
        fi
        
        # Print progress indicator
        echo -n '.'
        sleep 10
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
# Initialize progress tracking
progress_started=false

while true; do
    # Get the status of all MachineConfigPools (MCP)
    mcp_status=$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get mcp --no-headers | awk '{print $3, $4, $5}')

    # Check if any MCP has not reached the expected state
    if echo "$mcp_status" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for all mcps to not reach expected state"
            progress_started=true  # Mark progress as started
        fi
        
        # Print progress indicator
        echo -n '.'
        sleep 10
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [all mcp have reached the expected state]"
        break
    fi
done

echo
# ====================================================

# === Task: Login cluster information ===
PRINT_TASK "[TASK: Login cluster information]"

echo "info: [default setting is to use kubeconfig to login]"
echo "info: [log in to the cluster using the htpasswd user: uset KUBECONFIG && oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo
# ====================================================
