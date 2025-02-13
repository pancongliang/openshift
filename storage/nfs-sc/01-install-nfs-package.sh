#!/bin/bash
# set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# === Function to print a task with uniform length ===
# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
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


# === Task: Setup nfs services ===
PRINT_TASK "[TASK: Setup nfs services]"

# install nfs-utils
yum install nfs-utils -y &> /dev/null
run_command "[install nfs-utils package]"

# Create NFS directories
rm -rf ${NFS_DIR}
mkdir -p ${NFS_DIR}
run_command "[create nfs director: ${NFS_DIR}]"

# Add nfsnobody user if not exists
if id "nfsnobody" &>/dev/null; then
    echo "skipping: [nfsnobody user exists]"
else
    useradd nfsnobody
    echo "ok: [add nfsnobody user]"
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_DIR}
run_command "[changing ownership of an NFS directory]"

chmod -R 777 ${NFS_DIR}
run_command "[change NFS directory permissions]"

# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "skipping: [nfs export configuration already exists]"
else
    echo "$export_config_line" >> "/etc/exports"
    echo "ok: [add nfs export configuration]"
fi

# List of services to handle
services=("nfs-server")

# Loop through each service in the list
for service in "${services[@]}"; do
    # Restart the service
    systemctl restart "$service" &>/dev/null
    restart_status=$?

    # Enable the service
    systemctl enable "$service" &>/dev/null
    enable_status=$?

    if [ $restart_status -eq 0 ] && [ $enable_status -eq 0 ]; then
        echo "ok: [restart and enable $service service]"
    else
        echo "failed: [restart and enable $service service]"
    fi
done
