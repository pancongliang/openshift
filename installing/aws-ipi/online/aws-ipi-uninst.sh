#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
export AWS_ACCESS_KEY_ID="xxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxx"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

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

# Step 1:
PRINT_TASK "TASK [Set up AWS credentials]"

sudo rm -rf $HOME/.aws
sudo mkdir -p $HOME/.aws
cat << EOF | sudo tee "$HOME/.aws/credentials" > /dev/null
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[set up aws credentials]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Uninstalling a cluster]"

echo "info: [uninstalling the cluster, waiting...]"
openshift-install destroy cluster --dir $OCP_INSTALL_DIR --log-level info
run_command "[uninstalled cluster]"
