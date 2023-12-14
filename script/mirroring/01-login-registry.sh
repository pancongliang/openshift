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

# Task: Generate setup script file
PRINT_TASK "[TASK: Login Registry]"

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

export LOCAL_REGISTRY=docker.registry.example.com:5000
run_command "[set registry domain name variables]"


rm -rf /run/user/0/containers/auth.json &> /dev/null
podman login -u admin -p redhat ${LOCAL_REGISTRY} &> /dev/null
run_command "[login ${LOCAL_REGISTRY}]"

podman login -u admin -p redhat --authfile /root/pull-secret ${LOCAL_REGISTRY} &> /dev/null
run_command "[add ${LOCAL_REGISTRY} --authfile]"

cat /root/pull-secret | jq . > /run/user/0/containers/auth.json
run_command "[save the credentials to /run/user/0/containers/auth.json]"
