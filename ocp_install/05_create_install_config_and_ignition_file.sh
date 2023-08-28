#!/bin/bash

#######################################################

# Function to print a task with uniform length
print_task() {
    max_length=45  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

#######################################################

# Task: Generate a defined install-config file
PRINT_TASK "[TASK: Generate a defined install-config file]"

# Define variables
REGISTRY_CA_FILE="${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt"

# Backup and format the registry CA certificate
cp "${REGISTRY_CA_FILE}" "${REGISTRY_CA_FILE.bak}"
sed -i 's/^/  /' "${REGISTRY_CA_FILE.bak}"

# Define variables
export REGISTRY_CA="$(cat ${REGISTRY_CA_FILE.bak})"
export REGISTRY_ID_PW=$(echo -n "${REGISTRY_ID}:${REGISTRY_PW}" | base64)
export ID_RSA_PUB=$(cat "${ID_RSA_PUB_FILE}")

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
pullSecret: '{"auths":{"${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000": {"auth": "${REGISTRY_ID_PW}","email": "xxx@xxx.com"}}}' 
sshKey: '${ID_RSA_PUB}'
additionalTrustBundle: | 
${REGISTRY_CA}
imageContentSources:
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

# Delete certificate
rm -rf "$REGISTRY_CA_FILE.bak"

echo "Generated install-config files."

# Add an empty line after the task
echo

#######################################################

# Task:  Generate a manifests
PRINT_TASK "[TASK: Generate a manifests]"
# Create installation directory
rm -rf "${IGNITION_PATH}"
mkdir -p "${IGNITION_PATH}"

# Copy install-config.yaml to installation directory
cp "$HTTPD_PATH/install-config.yaml" "${IGNITION_PATH}"

# Generate manifests
openshift-install create manifests --dir "${IGNITION_PATH}"

# Add an empty line after the task
echo
#######################################################

# Task:  Disable master node scheduling
PRINT_TASK "[TASK: Disable master node scheduling]"

# Verify the initial value
initial_value=$(grep "mastersSchedulable: true" "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml")
if [ -n "$initial_value" ]; then
    echo "Initial value found: $initial_value"    
    # Modify the file using sed
    sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml"

    # Verify the modification
    modified_value=$(grep "mastersSchedulable: false" "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml")
    if [ -n "$modified_value" ]; then
        echo "Master node scheduling disabled successful: $modified_value"
    else
        echo "Master node scheduling disabled failed."
    fi
fi

# Add an empty line after the task
echo
#######################################################

# Task: Generate a ignition file
PRINT_TASK "[TASK: Generate a ignition file]"

# Generate and modify ignition configuration files
openshift-install create ignition-configs --dir "${IGNITION_PATH}"

# Set correct permissions
chmod a+r "${IGNITION_PATH}"/*.ign

# Add an empty line after the task
echo
#######################################################

# Task: Generate an ignition file containing the node hostname
PRINT_TASK "[TASK: Generate an ignition file containing the node hostname]"

# Copy ignition files with appropriate hostnames
cp "${IGNITION_PATH}/bootstrap.ign" "${IGNITION_PATH}/${BOOTSTRAP_HOSTNAME}-bak.ign"

for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/master.ign" "${IGNITION_PATH}/${MASTER_HOSTNAME}.ign"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/worker.ign" "${IGNITION_PATH}/${WORKER_HOSTNAME}.ign"
done

# Update hostname in ignition files
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}'"}"},"mode":420}]}}/' "${IGNITION_PATH}/${BOOTSTRAP_HOSTNAME}.ign"

for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'${MASTER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}'"}"},"mode":420}]}}/' "${IGNITION_PATH}/${MASTER_HOSTNAME}.ign"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'${WORKER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}'"}"},"mode":420}]}}/' "${IGNITION_PATH}/${WORKER_HOSTNAME}.ign"
done

# Set correct permissions
chmod a+r "${IGNITION_PATH}"/*.ign


# ====== Validation script section ====== #
# Check if the ignition file is copied
check_files_generated() {
    if [ -f "${IGNITION_PATH}/${BOOTSTRAP_HOSTNAME}-bak.ign" ]; then
        for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
            if [ ! -f "${IGNITION_PATH}/${MASTER_HOSTNAME}.ign" ]; then
                echo "Master ignition file for ${MASTER_HOSTNAME} was not generated."
                exit 1
            fi
        done
        for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
            if [ ! -f "${IGNITION_PATH}/${WORKER_HOSTNAME}.ign" ]; then
                echo "Worker ignition file for ${WORKER_HOSTNAME} was not generated."
                exit 1
            fi
        done
        if [ ! -f "${IGNITION_PATH}/${BOOTSTRAP_HOSTNAME}-bak.ign" ]; then
            echo "Bootstrap ignition file was not generated."
            exit 1
        fi
    else
        echo "Bootstrap ignition file was not generated."
        exit 1
    fi
    echo "All ignition files have been successfully generated."
}

check_sed_changes() {
    # Check Bootstrap file's sed changes
    bootstrap_changes=$(grep -c "\"storage\":{\"files\":\[{\"path\":\"/etc/hostname\",\"contents\":{\"source\":\"data:${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}\"}" "${IGNITION_PATH}/${BOOTSTRAP_HOSTNAME}.ign")
    if [ "$bootstrap_changes" -eq 0 ]; then
        echo "Hostname changes for Bootstrap ignition file were not applied."
        exit 1
    fi

    # Check sed changes for Master files
    for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
        master_changes=$(grep -c "\"storage\":{\"files\":\[{\"path\":\"/etc/hostname\",\"contents\":{\"source\":\"data:${MASTER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}\"}" "${IGNITION_PATH}/${MASTER_HOSTNAME}.ign")
        if [ "$master_changes" -eq 0 ]; then
            echo "Hostname changes for Master ignition file (${MASTER_HOSTNAME}) were not applied."
            exit 1
        fi
    done

    # Check sed changes for Worker files
    for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
        worker_changes=$(grep -c "\"storage\":{\"files\":\[{\"path\":\"/etc/hostname\",\"contents\":{\"source\":\"data:${WORKER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}\"}" "${IGNITION_PATH}/${WORKER_HOSTNAME}.ign")
        if [ "$worker_changes" -eq 0 ]; then
            echo "Hostname changes for Worker ignition file (${WORKER_HOSTNAME}) were not applied."
            exit 1
        fi
    done
    echo "All ignition custom hostname changes have been successfully applied."
}

check_files_generated
check_sed_changes

# Add an empty line after the task
echo
#######################################################

# Task: Set ignition file permissions and display generated files
PRINT_TASK "[TASK: ignition file permissions and display generated files]"

# Set correct permissions and list files
chmod a+r "${IGNITION_PATH}"/*.ign
ls -l "${IGNITION_PATH}"/*.ign
