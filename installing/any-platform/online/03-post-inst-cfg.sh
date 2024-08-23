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

export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig

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


# === Task: Create htpasswd User ===
PRINT_TASK "[TASK: Create htpasswd User]"

export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig

rm -rf $OCP_INSTALL_DIR/users.htpasswd
htpasswd -c -B -b $OCP_INSTALL_DIR/users.htpasswd admin redhat &> /dev/null
run_command "[Create a user using the htpasswd tool]"

/usr/local/bin/oc create secret generic htpasswd-secret --from-file=htpasswd=$OCP_INSTALL_DIR/users.htpasswd -n openshift-config &> /dev/null
run_command "[Create a secret using the users.htpasswd file]"

rm -rf $OCP_INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
cat  <<EOF | /usr/local/bin/oc apply -f - > /dev/null 2>&1
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
run_command "[Setting up htpasswd authentication]"

# Grant the 'cluster-admin' cluster role to the user 'admin'
/usr/local/bin/oc adm policy add-cluster-role-to-user cluster-admin admin &> /dev/null
run_command "[Grant cluster-admin permissions to the admin user]"

echo "info: [Restarting oauth pod, waiting...]"
sleep 100
echo "info: [Restarting oauth pod, waiting...]"
sleep 100
echo "info: [Restarting oauth pod, waiting...]"
sleep 100

echo
# ====================================================

# === Task: Login cluster information ===
PRINT_TASK "[TASK: Login cluster information]"

echo "info: [Log in to the cluster using the htpasswd user:  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo "info: [Log in to the cluster using kubeconfig:  export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig]"
echo
# ====================================================
