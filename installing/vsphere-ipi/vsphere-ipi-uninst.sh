#!/bin/bash

# Set environment variables
export INSTALL_DIR="$HOME/ocp-inst/ocp"

# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: Command \`$BASH_COMMAND\`]"; exit 1' ERR

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
        echo -e "\e[96mINFO\e[0m $1"
    else
        echo -e "\e[31mFAILED\e[0m $1"
        exit 1
    fi
}

PRINT_TASK "TASK [Uninstalling a cluster]"

/usr/local/bin/openshift-install destroy cluster --dir $INSTALL_DIR --log-level info
run_command "Uninstalled cluster"
