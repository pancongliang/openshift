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
#PRINT_TASK "[TASK: Kubeconfig login]"

# kubeconfig login:
#echo "export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig" >> ~/.bash_profile
#run_command "[add kubeconfig to ~/.bash_profile]"

# completion command:
#oc completion bash >> /etc/bash_completion.d/oc_completion
#run_command "[add oc_completion]"

# Effective immediately
#source /etc/bash_completion.d/oc_completion

# Add an empty line after the task
#echo
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

oc --kubeconfig=${IGNITION_PATH}/auth/kubeconfig apply -f /tmp/${IMAGE_REGISTRY_PV}.yaml &> /dev/null
run_command "[apply ${IMAGE_REGISTRY_PV} pv]"

rm -f /tmp/${IMAGE_REGISTRY_PV}.yaml
run_command "[remove ${IMAGE_REGISTRY_PV}.yaml file]"

# Change the Image registry operator configuration’s managementState from Removed to Managed
oc --kubeconfig=${IGNITION_PATH}/auth/kubeconfig patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}' &> /dev/null
run_command "[change the Image registry operator configuration’s managementState from Removed to Managed]"

# Leave the claim field blank to allow the automatic creation of an image-registry-storage PVC.
oc --kubeconfig=${IGNITION_PATH}/auth/kubeconfig patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}' &> /dev/null
run_command "[leave the claim field blank to allow the automatic creation of an image-registry-storage PVC]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Create htpasswd User ===
PRINT_TASK "[TASK: Create htpasswd User]"

rm -rf $OCP_INSTALL_DIR/users.htpasswd
htpasswd -c -B -b $OCP_INSTALL_DIR/users.htpasswd admin redhat &> /dev/null
run_command "[create a user using the htpasswd tool]"

oc --kubeconfig=${IGNITION_PATH}/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$OCP_INSTALL_DIR/users.htpasswd -n openshift-config &> /dev/null
run_command "[create a secret using the users.htpasswd file]"

rm -rf $OCP_INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
cat  <<EOF | /usr/local/bin/oc --kubeconfig=${IGNITION_PATH}/auth/kubeconfig apply -f - > /dev/null 2>&1
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
oc --kubeconfig=${IGNITION_PATH}/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin &> /dev/null
run_command "[grant cluster-admin permissions to the admin user]"

echo "info: [restarting oauth pod, waiting...]"
sleep 100

while true; do
    operator_status=$(/usr/local/bin/oc --kubeconfig=${IGNITION_PATH}/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    if echo "$operator_status" | grep -q -v "True False False"; then
        echo "info: [all cluster operators have not reached the expected status, Waiting...]"
        sleep 60  
    else
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

echo
# ====================================================

# === Task: Login cluster information ===
PRINT_TASK "[TASK: Login cluster information]"

echo "info: [log in to the cluster using the htpasswd user:  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo "info: [log in to the cluster using kubeconfig:  export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig]"
echo
# ====================================================
