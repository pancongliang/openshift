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


# Task: Generate a defined install-config file
PRINT_TASK "[TASK: Generate a defined install-config file]"

# Create ssh-key for accessing CoreOS
rm -rf ${SSH_KEY_PATH}
ssh-keygen -N '' -f ${SSH_KEY_PATH}/id_rsa &> /dev/null
run_command "[create ssh-key for accessing coreos]"

# Define variables
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Generate a defined install-config file
rm -rf ${HTTPD_PATH}/install-config.yaml

cat << EOF > ${HTTPD_PATH}/install-config.yaml 
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 0 
controlPlane: 
  hyperthreading: Enabled 
  name: master
  replicas: 3 
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: ${POD_CIDR}
    hostPrefix: ${HOST_PREFIX}
  networkType: ${NETWORK_TYPE}
  serviceNetwork: 
  - ${SERVICE_CIDR}
platform:
  none: {} 
fips: false
pullSecret: '$(cat $PULL_SECRET_PATH)'
sshKey: '${SSH_PUB_STR}'
EOF
run_command "[create ${HTTPD_PATH}/install-config.yaml file]"

# Add an empty line after the task
echo
# ====================================================


# Task:  Generate a manifests
PRINT_TASK "[TASK: Generate a manifests]"

# Create installation directory
rm -rf "${IGNITION_PATH}"
mkdir -p "${IGNITION_PATH}"
run_command "[create installation directory: ${IGNITION_PATH}]"

# Copy install-config.yaml to installation directory
cp "${HTTPD_PATH}/install-config.yaml" "${IGNITION_PATH}"
run_command "[copy the install-config.yaml file to the installation directory]"

# Generate manifests
openshift-install create manifests --dir "${IGNITION_PATH}" &> /dev/null
run_command "[generate manifests]"

# Check if the file contains "mastersSchedulable: true"
if grep -q "mastersSchedulable: true" "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml"; then
  # Replace "mastersSchedulable: true" with "mastersSchedulable: false"
  sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml"
  echo "ok: [disable the master node from scheduling custom pods]"
else
  echo "skipping: [scheduling of custom pods on master nodes is already disabled]"
fi

# Add an empty line after the task
echo
# ====================================================


# Task: Generate default ignition file
PRINT_TASK "[TASK: Generate default ignition file]"

# Generate and modify ignition configuration files
openshift-install create ignition-configs --dir "${IGNITION_PATH}" &> /dev/null
run_command "[generate default ignition file]"

# Add an empty line after the task
echo
# ====================================================


# Task: Generate an ignition file containing the node hostname
PRINT_TASK "[TASK: Generate an ignition file containing the node hostname]"

# Copy ignition files with appropriate hostnames
BOOTSTRAP_HOSTNAME="${BOOTSTRAP_HOSTNAME}"
MASTER_HOSTNAMES=("${MASTER01_HOSTNAME}" "${MASTER02_HOSTNAME}" "${MASTER03_HOSTNAME}")
WORKER_HOSTNAMES=("${WORKER01_HOSTNAME}" "${WORKER02_HOSTNAME}" "${WORKER03_HOSTNAME}")

cp "${IGNITION_PATH}/bootstrap.ign" "${IGNITION_PATH}/append-${BOOTSTRAP_HOSTNAME}.ign"
run_command "[copy and customize the bootstrap.ign file name: append-${BOOTSTRAP_HOSTNAME}.ign]"

for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/master.ign" "${IGNITION_PATH}/append-${MASTER_HOSTNAME}.ign"
    run_command "[copy and customize the master.ign file name: append-${MASTER_HOSTNAME}.ign]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/worker.ign" "${IGNITION_PATH}/append-${WORKER_HOSTNAME}.ign"
    run_command "[copy and customize the worker.ign file name: append-${WORKER_HOSTNAME}.ign]"
done

# Update hostname in ignition files
for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${MASTER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},"mode":420}]}}/' "${IGNITION_PATH}/append-${MASTER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the append-${MASTER_HOSTNAME}.ign file]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${WORKER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},"mode":420}]}}/' "${IGNITION_PATH}/append-${WORKER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the append-${WORKER_HOSTNAME}.ign file]"
done

# Set correct permissions
chmod a+r "${IGNITION_PATH}"/*.ign
run_command "[change ignition file permissions]"

# Add an empty line after the task
echo
# ====================================================
