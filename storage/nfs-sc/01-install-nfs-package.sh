#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
#set -u
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
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}
# ====================================================



# === Task: Setup nfs services ===
PRINT_TASK "[TASK: Setup nfs services]"

# install nfs-utils
sudo dnf install nfs-utils -y &> /dev/null
run_command "[install nfs-utils package]"

# Create NFS directories
sudo rm -rf ${NFS_DIR}
sudo mkdir -p ${NFS_DIR}
run_command "[create nfs director: ${NFS_DIR}]"

# Add nfsnobody user if not exists
if id "nfsnobody" &>/dev/null; then
    echo "skipping: [nfsnobody user exists]"
else
    useradd nfsnobody
    echo "ok: [add nfsnobody user]"
fi

# Change ownership and permissions
sudo chown -R nfsnobody.nfsnobody ${NFS_DIR}
run_command "[changing ownership of an NFS directory]"

sudo chmod -R 777 ${NFS_DIR}
run_command "[change NFS directory permissions]"

# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "skipping: [nfs export configuration already exists]"
else
    echo "$export_config_line" >> "/etc/exports"
    echo "ok: [add nfs export configuration]"
fi

sudo systemctl enable nfs-server
run_command "[enable nfs-server service]"

sudo systemctl restart nfs-server
run_command "[restart nfs-server service]"
