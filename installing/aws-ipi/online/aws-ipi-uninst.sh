#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'printf "\e[31mFAILED\e[0m Line %s - Command: %s\n" "$LINENO" "$BASH_COMMAND"; exit 1' ERR

# Set environment variables
export INSTALL_DIR="$HOME/aws-ipi/ocp"
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
        printf "\033[96mINFO\033[0m %s\n" "$1"
    else
        printf "\033[31mFAILED\033[0m %s\n" "$1"
        exit 1
    fi
}

# Step 1:
PRINT_TASK "TASK [Uninstalling a cluster]"

# Create AWS credentials
rm -rf $HOME/.aws
mkdir -p $HOME/.aws

cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "Set up AWS credentials"

printf "\e[96mINFO\e[0m Starting the OpenShift cluster uninstallation...\n"
/usr/local/bin/openshift-install destroy cluster --dir $INSTALL_DIR --log-level info
