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


# === Task: Add short domain name ===
PRINT_TASK "[TASK: Add short domain name]"

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

printf "%-15s %s\n" "$MASTER01_IP" "$MASTER01_HOSTNAME" >> /etc/hosts
run_command "[add $MASTER01_HOSTNAME short domain name]"

printf "%-15s %s\n" "$MASTER02_IP" "$MASTER02_HOSTNAME" >> /etc/hosts
run_command "[add $MASTER02_HOSTNAME short domain name]"

printf "%-15s %s\n" "$MASTER03_IP" "$MASTER03_HOSTNAME" >> /etc/hosts
run_command "[add $MASTER03_HOSTNAME short domain name]"

printf "%-15s %s\n" "$WORKER01_IP" "$WORKER01_HOSTNAME" >> /etc/hosts
run_command "[add $WORKER01_HOSTNAME short domain name]"

printf "%-15s %s\n" "$WORKER02_IP" "$WORKER02_HOSTNAME" >> /etc/hosts
run_command "[add $WORKER02_HOSTNAME short domain name]"

printf "%-15s %s\n" "$BASTION_IP" "$REGISTRY_HOSTNAME" >> /etc/hosts
run_command "[add $REGISTRY_HOSTNAME short domain name]"
