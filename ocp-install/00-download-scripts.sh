#!/bin/bash

# Declare an array of scripts
scripts=(
    "00_security.sh"
    "00_subscription.sh"
    "01_ocp_env_parameter.sh"
    "02_install_infrastructure.sh"
    "03_install_mirror_registry.sh"
    "04_mirror_ocp_image.sh"
    "05_generate_ignition.sh"
    "06_generate_setup_script_file.sh"
    "07_configure_after_installation.sh"
)

# Specify the base URL of the GitHub repository
base_url="https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/"

# Use a loop to download the scripts
for script in "${scripts[@]}"; do
    wget "${base_url}${script}"
done
