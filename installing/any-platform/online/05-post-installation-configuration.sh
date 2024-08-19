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
echo "export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig" >> ~/.bash_profile
run_command "[add kubeconfig to ~/.bash_profile]"

# completion command:
oc completion bash >> /etc/bash_completion.d/oc_completion
run_command "[add oc_completion]"

# Effective immediately
source /etc/bash_completion.d/oc_completion

# Add an empty line after the task
echo
# ====================================================


# Task: Configure data persistence for the image-registry operator
PRINT_TASK "[TASK: Configure data persistence for the image-registry operator]"

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
    path: ${NFS_PATH}/${IMAGE_REGISTRY_PV}
    server: ${NFS_SERVER_IP}
  persistentVolumeReclaimPolicy: Retain
EOF
run_command "[create ${IMAGE_REGISTRY_PV}.yaml file]"

oc apply -f /tmp/${IMAGE_REGISTRY_PV}.yaml &> /dev/null
run_command "[apply ${IMAGE_REGISTRY_PV} pv]"

rm -f /tmp/${IMAGE_REGISTRY_PV}.yaml
run_command "[remove ${IMAGE_REGISTRY_PV}.yaml file]"

# Change the Image registry operator configuration’s managementState from Removed to Managed
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}' &> /dev/null
run_command "[change the Image registry operator configuration’s managementState from Removed to Managed]"

# Leave the claim field blank to allow the automatic creation of an image-registry-storage PVC.
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}' &> /dev/null
run_command "[leave the claim field blank to allow the automatic creation of an image-registry-storage PVC]"

# Add an empty line after the task
echo
# ====================================================


# Task: Configuring additional trust stores for image registry access
PRINT_TASK "[TASK: Configuring additional trust stores for image registry access]"

# Create a configmap containing the CA certificate
oc create configmap registry-config \
     --from-file=${REGISTRY_HOSTNAME}.${BASE_DOMAIN}..8443=/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem \
     -n openshift-config &> /dev/null
run_command "[create a configmap containing the CA certificate]"

# Additional trusted CA
oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge &> /dev/null
run_command "[additional trusted CA]"

# Add an empty line after the task
echo
# ====================================================

# Task: Disabling the default OperatorHub sources
PRINT_TASK "[TASK: Disabling the default OperatorHub sources]"

# Disabling the default OperatorHub sources
oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
run_command "[disabling the default OperatorHub sources]"
