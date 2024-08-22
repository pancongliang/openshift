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
PRINT_TASK "[TASK: Download script]"

# Declare an array of scripts
scripts=(
    "00-del-aws-res.sh"
    "01-set-params.sh"
    "02-create-aws-res.sh"
    "03-inst-pre.sh"
    "04-post-inst-cfg.sh"
)

# Specify the base URL of the GitHub repository
base_url="https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/offline/"

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
