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
PRINT_TASK "[TASK: View docker.registry.example.com:5000 repositor]"

curl -s -u admin:redhat https://docker.registry.example.com:5000/v2/_catalog | jq .repositories[]
# curl -s -u admin:password https://mirror.registry.example.com:8443/v2/_catalog | jq .repositories[]
