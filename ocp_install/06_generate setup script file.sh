#!/bin/bash
# === Function to print a task with uniform length ===
# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Task: Generate setup script file
PRINT_TASK "[TASK: Generate setup script file]"

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

rm -rf ${IGNITION_PATH}/*.sh

# Function to generate setup script for a node
generate_setup_script() {
    local HOSTNAME=$1
    local IP_ADDRESS=$2

    # Generate a setup script for the node
    cat << EOF > "${IGNITION_PATH}/set-${HOSTNAME}.sh"
#!/bin/bash
# Configure network settings
nmcli con mod ${NET_IF_NAME} ipv4.addresses ${IP_ADDRESS}/${NETMASK} ipv4.gateway ${GATEWAY_IP} ipv4.dns ${DNS_SERVER_IP} ipv4.method manual connection.autoconnect yes
nmcli con down ${NET_IF_NAME}
nmcli con up ${NET_IF_NAME}

sudo sleep 10

# Install CoreOS using Ignition
sudo coreos-installer install ${COREOS_INSTALL_DEV} --insecure-ignition --ignition-url=http://${BASTION_IP}:8080/pre/append-${HOSTNAME}.ign --insecure-ignition --firstboot-args 'rd.neednet=1' --copy-network
EOF

    # Check if the setup script file was successfully generated
    if [ -f "${IGNITION_PATH}/set-${HOSTNAME}.sh" ]; then
        echo "ok: [generate setup script: ${IGNITION_PATH}/set-${HOSTNAME}.sh]"
    else
        echo "failed: [generate setup script for ${HOSTNAME}"
    fi
}

# Generate setup scripts for each node
generate_setup_script "${BOOTSTRAP_HOSTNAME}" "${BOOTSTRAP_IP}"
generate_setup_script "${MASTER01_HOSTNAME}" "${MASTER01_IP}"
generate_setup_script "${MASTER02_HOSTNAME}" "${MASTER02_IP}"
generate_setup_script "${MASTER03_HOSTNAME}" "${MASTER03_IP}"
generate_setup_script "${WORKER01_HOSTNAME}" "${WORKER01_IP}"
generate_setup_script "${WORKER02_HOSTNAME}" "${WORKER02_IP}"


# Make the script executable
chmod +x ${IGNITION_PATH}/*.sh
run_command "[change ignition file permissions]"
