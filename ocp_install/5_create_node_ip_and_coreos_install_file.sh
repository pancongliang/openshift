#!/bin/bash

# Function to generate setup script for a node
generate_setup_script() {
    local HOSTNAME=$1
    local IP_ADDRESS=$2

    # Generate a setup script for the node
    cat << EOF > ${IGNITION_PATH}/set-${HOSTNAME}.sh
#!/bin/bash
# Configure network settings
nmcli con mod ${NET_IF_NAME} ipv4.addresses ${IP_ADDRESS}/${NETMASK} ipv4.gateway ${GATEWAY_IP} ipv4.dns ${DNS_IP} ipv4.method manual connection.autoconnect yes
nmcli con down ${NET_IF_NAME}
nmcli con up ${NET_IF_NAME}

# Install CoreOS using Ignition
sudo coreos-installer install ${COREOS_INSTALL_DEV} --insecure-ignition --ignition-url=http://${BASTION_IP}:8080/pre/${HOSTNAME}.ign --insecure-ignition --firstboot-args 'rd.neednet=1' --copy-network
EOF

    # Make the script executable
    chmod +x ${IGNITION_PATH}/set-${HOSTNAME}.sh
}

# Generate setup scripts for each node
generate_setup_script ${BOOTSTRAP_HOSTNAME} ${BOOTSTRAP_IP}
generate_setup_script ${MASTER01_HOSTNAME} ${MASTER01_IP}
generate_setup_script ${MASTER02_HOSTNAME} ${MASTER02_IP}
generate_setup_script ${MASTER03_HOSTNAME} ${MASTER03_IP}
generate_setup_script ${WORKER01_HOSTNAME} ${WORKER01_IP}
generate_setup_script ${WORKER02_HOSTNAME} ${WORKER02_IP}

# Check if files were generated successfully
generated_files=("set-${BOOTSTRAP_HOSTNAME}.sh"
                 "set-${MASTER01_HOSTNAME}.sh"
                 "set-${MASTER02_HOSTNAME}.sh"
                 "set-${MASTER03_HOSTNAME}.sh"
                 "set-${WORKER01_HOSTNAME}.sh"
                 "set-${WORKER02_HOSTNAME}.sh")

success=true

for file in "${generated_files[@]}"; do
    if [ ! -f "${IGNITION_PATH}/${file}" ]; then
        echo "Error: ${file} CoreOS configuration file generated failed."
        success=false
    fi
done

if [ "${success}" = true ]; then
    echo "CoreOS configuration file generated successfully."
fi

# Display generated files
ls -l "${IGNITION_PATH}"/*.sh
