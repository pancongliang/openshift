#!/bin/bash

#######################################################

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=45  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

#######################################################

# Task: Generate a defined install-config file
PRINT_TASK "[TASK: Generate a defined install-config file]"

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

# Backup and format the registry CA certificate
cp "${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt" "${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt.bak"
run_command "[backup registry CA certificate]"

sed -i 's/^/  /' "${REGISTRY_CA_FILE.bak}"
run_command "[format registry ca certificate]"


# Create ssh-key for accessing CoreOS
rm -rf ${SSH_KEY_PATH}
mkdir -p ${SSH_KEY_PATH}
run_command "[create ${SSH_KEY_PATH} directory]"

ssh-keygen -N '' -f ${SSH_PRI_FILE}		
run_command "[create ssh-key for accessing coreos]"


# Define variables
export REGISTRY_CA_CERT_FORMAT="$(cat ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt.bak)"
export REGISTRY_AUTH=$(echo -n "${REGISTRY_ID}:${REGISTRY_PW}" | base64)
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Generate a defined install-config file
rm -rf ${HTTPD_PATH}/install-config.yaml

cat << EOF > $HTTPD_PATH/install-config.yaml 
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
pullSecret: '{"auths":{"${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000": {"auth": "${REGISTRY_AUTH}","email": "xxx@xxx.com"}}}' 
sshKey: '${SSH_PUB_STR}'
additionalTrustBundle: | 
${REGISTRY_CA_CERT_FORMAT}
imageContentSources:
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF
run_command "[create install-config.yaml fole]"

# Delete certificate
rm -rf "${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt.bak"
run_command "[delete ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt.bak file]"

# Add an empty line after the task
echo




# Task:  Generate a manifests
PRINT_TASK "[TASK: Generate a manifests]"

# Create installation directory
rm -rf "${IGNITION_PATH}"
mkdir -p "${IGNITION_PATH}"
run_command "[create installation directory: ${IGNITION_PATH}]"

# Copy install-config.yaml to installation directory
cp "$HTTPD_PATH/install-config.yaml" "${IGNITION_PATH}"
run_command "[copy the install-config.yaml file to the installation directory]"

# Generate manifests
openshift-install create manifests --dir "${IGNITION_PATH}"
run_command "[generate manifests]"

# Check if the file contains "mastersSchedulable: true"
if grep -q "mastersSchedulable: true" "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml"; then
  # Replace "mastersSchedulable: true" with "mastersSchedulable: false"
  sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml""
  echo "'ok: [disable the master node from scheduling custom pods]"
else
  echo "'failed: mastersSchedulable: true' not found, no changes made"
fi

# Add an empty line after the task
echo





# Task: Generate default ignition file
PRINT_TASK "[TASK: Generate default ignition file]"

# Generate and modify ignition configuration files
openshift-install create ignition-configs --dir "${IGNITION_PATH}"
run_command "[generate default ignition file]"

# Add an empty line after the task
echo

# Task: Generate an ignition file containing the node hostname
PRINT_TASK "[TASK: Generate an ignition file containing the node hostname]"

# Copy ignition files with appropriate hostnames
BOOTSTRAP_HOSTNAME="${BOOTSTRAP_HOSTNAME}"
MASTER_HOSTNAMES=("${MASTER01_HOSTNAME}" "${MASTER02_HOSTNAME}" "${MASTER03_HOSTNAME}")
WORKER_HOSTNAMES=("${WORKER01_HOSTNAME" "${WORKER01_HOSTNAME}")

cp "${IGNITION_PATH}/bootstrap.ign" "${IGNITION_PATH}/${BOOTSTRAP_HOSTNAME}-bak.ign"
run_command "[copy and customize the bootstrap.ign file name: ${BOOTSTRAP_HOSTNAME}-bak.ign]"

for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/master.ign" "${IGNITION_PATH}/${MASTER_HOSTNAME}.ign"
    run_command "[copy and customize the master.ign file name: ${MASTER_HOSTNAME}.ign]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/worker.ign" "${IGNITION_PATH}/${WORKER_HOSTNAME}.ign"
    run_command "[copy and customize the worker.ign file name: ${WORKER_HOSTNAME}.ign]"
done

# Update hostname in ignition files
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}'"}"},"mode":420}]}}/' "${IGNITION_PATH}/${BOOTSTRAP_HOSTNAME}.ign"
run_command "[add the appropriate hostname field to the ${BOOTSTRAP_HOSTNAME}.ign file]"

for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'${MASTER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}'"}"},"mode":420}]}}/' "${IGNITION_PATH}/${MASTER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the ${MASTER_HOSTNAME}.ign file]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'${WORKER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}'"}"},"mode":420}]}}/' "${IGNITION_PATH}/${WORKER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the ${MASTER_HOSTNAME}.ign file]"
done

# Set correct permissions
chmod a+r "${IGNITION_PATH}"/*.ign
run_command "[change ignition file permissions]"
