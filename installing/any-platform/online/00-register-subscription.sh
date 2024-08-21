
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

# Task: Sign up for a Red Hat Subscription
PRINT_TASK "[TASK: Sign up for a Red Hat Subscription]"

# Prompt for Red Hat Subscribe UserName
read -p "Please input the Red Hat Subscribe UserName: " USER

# Prompt for Red Hat Subscribe Password securely (hidden input)
read -s -p "Please input the Red Hat Subscribe Password: " PASSWD

# Move to a new line after password input
echo -e "\r"

# Register with subscription-manager
subscription-manager register --force --user ${USER} --password ${PASSWD} &> /dev/null

# Refresh subscriptions
subscription-manager refresh &> /dev/null

# Find the desired Pool ID for OpenShift
POOL_ID=$(subscription-manager list --available --matches '*OpenShift Container Platform*' | grep "Pool ID" | tail -n 1 | awk -F: '{print $2}' | tr -d ' ')

# Attach to the chosen Pool
subscription-manager attach --pool="$POOL_ID"

# Add an empty line after the task
echo
# ====================================================
