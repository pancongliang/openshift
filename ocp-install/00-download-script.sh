#!/bin/bash

# Declare an array of scripts
scripts=(
    "00-security.sh"
    "00-subscription.sh"
    "01-ocp-env-parameter.sh"
    "02-install-infrastructure.sh"
    "03-install-mirror-registry.sh"
    "04-mirror-ocp-image.sh"
    "05-generate-ignition.sh"
    "06-generate-setup-script-file.sh"
    "07-configure-after-installation.sh"
)

# Specify the base URL of the GitHub repository
base_url="https://raw.githubusercontent.com/pancongliang/openshift/main/ocp-install/"

# Function to download scripts
download_scripts() {
    for script in "${scripts[@]}"; do
        wget -q "${base_url}${script}"
        if [ $? -eq 0 ]; then
            echo "ok: [download ${script}]"
        else
            echo "failed: [download ${script}]"
        fi
    done

    exit 0  # Exit the script after all tasks are done
}

# Execute the function
download_scripts
