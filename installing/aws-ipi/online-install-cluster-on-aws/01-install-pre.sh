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


# === Task: Install AWS CLI ===
PRINT_TASK "[TASK: Install AWS CLI]"

# Function to install AWS CLI on Linux
install_awscli_linux() {
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" > /dev/null 
    unzip awscliv2.zip > /dev/null 
    sudo ./aws/install &>/dev/null || true
    run_command "[Install AWS CLI]"
    sudo rm -rf aws awscliv2.zip
}

# Function to install AWS CLI on macOS
install_awscli_mac() {
    curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" > /dev/null 
    sudo installer -pkg AWSCLIV2.pkg -target / &>/dev/null || true
    run_command "[Install AWS CLI]"
    sudo rm -rf AWSCLIV2.pkg
}

# Detecting the operating system
os=$(uname -s)

# Installing AWS CLI based on the operating system
case "$os" in
    Linux*)  install_awscli_linux;;
    Darwin*) install_awscli_mac;;
    *) ;;
esac

# Add an empty line after the task
echo
# ====================================================


# === Task: Set up AWS credentials ===
PRINT_TASK "[TASK: Set up AWS credentials]"
rm -rf $HOME/.aws
mkdir -p $HOME/.aws
cat << EOF > "$HOME/.aws/credentials"
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[Set up AWS credentials]"

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
    "/usr/local/bin/openshift-install"
    "/usr/local/bin/openshift-install-linux.tar.gz"
    "/usr/local/bin/openshift-client-linux.tar.gz"
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
    wget -P "/usr/local/bin" "$tool_url" &> /dev/null    
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


# === Task: Generate SSH key for cluster nodes ===
PRINT_TASK "[TASK: Generate SSH key for cluster nodes]"

rm -rf $HOME/.ssh/*
ssh-keygen -N '' -f $HOME/.ssh/id_rsa
run_command "[Generate SSH key for cluster nodes $HOME/.ssh/]"
