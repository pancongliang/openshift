#!/bin/bash

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Step 1:
PRINT_TASK "TASK [Download script]"

# Declare an array of scripts
scripts=(
    "00-reg-sub.sh"
    "01-set-params.sh"
    "02-pre-inst.sh"
    "03-mirror-img.sh"
    "04-post-inst-cfg.sh"
)

# Specify the base URL of the GitHub repository
base_url="https://raw.githubusercontent.com/pancongliang/openshift/main/installing/any-platform/offline/"

# Function to download scripts
download_scripts() {
    for script in "${scripts[@]}"; do
        curl -s -O "${base_url}${script}"
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
