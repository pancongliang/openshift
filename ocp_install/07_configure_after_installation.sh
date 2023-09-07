#!/bin/bash
# === Function to print a task with uniform length ===
# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}


# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

# Task: Kubeconfig login
PRINT_TASK "[TASK: Kubeconfig login]"

# kubeconfig login:
echo 'export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig' >> ~/.bash_profile
run_command "[add kubeconfig to ~/.bash_profile]"
source ~/.bash_profile


# Task: Configure data persistence for the image-registry operator
PRINT_TASK "[TASK: Configure data persistence for the image-registry operator]"


cat << EOF | oc apply -f -
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
EOF &> /dev/null
run_command "[create ${IMAGE_REGISTRY_PV} pv]"


# Change the Image registry operator configuration’s managementState from Removed to Managed
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}' &> /dev/null
run_command "[change the Image registry operator configuration’s managementState from Removed to Managed]"

# Leave the claim field blank to allow the automatic creation of an image-registry-storage PVC.
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}' &> /dev/null
run_command "[leave the claim field blank to allow the automatic creation of an image-registry-storage PVC]"




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
