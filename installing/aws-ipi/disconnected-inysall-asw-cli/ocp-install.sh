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



# === Task: Install infrastructure rpm ===
PRINT_TASK "[TASK: Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "zip" "vim" "podman" "bind-utils" "bash-completion" "jq" "skopeo" "httpd-tools")

# Install the RPM package and return the execution result
for package in "${packages[@]}"; do
    sudo yum install -y "$package" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [install $package package]"
    else
        echo "failed: [install $package package]"
    fi
done

# Add an empty line after the task
echo
# ====================================================



# === Task: Install openshift tool ===
PRINT_TASK "[TASK: Install openshift tool]"

# Step 1: Delete openshift tool
# ----------------------------------------------------
# Delete openshift tool
files=(
    "/usr/local/bin/kubectl"
    "/usr/local/bin/oc"
    "/usr/local/bin/oc-mirror"
    "/usr/local/bin/openshift-install"
    "/usr/local/bin/openshift-install-linux.tar.gz"
    "/usr/local/bin/openshift-client-linux.tar.gz"
    "/usr/local/bin/oc-mirror.tar.gz"
)
for file in "${files[@]}"; do
    sudo rm -rf $file 2>/dev/null
done


# Step 2: Function to download and install tool
# ----------------------------------------------------
# Function to download and install .tar.gz tools
install_tar_gz() {
    local tool_name="$1"
    local tool_url="$2"  
    # Download the tool
    sudo wget -P "/usr/local/bin" "$tool_url" &> /dev/null    
    if [ $? -eq 0 ]; then
        echo "ok: [download $tool_name tool]"        
        # Extract the downloaded tool
        tar xvf "/usr/local/bin/$(basename $tool_url)" -C "/usr/local/bin/" &> /dev/null
        # Remove the downloaded .tar.gz file
        rm -f "/usr/local/bin/$(basename $tool_url)"
    else
        echo "failed: [download $tool_name tool]"
    fi
}

# Install .tar.gz tools
install_tar_gz "openshift-install" "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE}/openshift-install-linux.tar.gz"
install_tar_gz "openshift-client" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz"
install_tar_gz "oc-mirror" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"

