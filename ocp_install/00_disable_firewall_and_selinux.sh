#!/bin/bash

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

######

# Task: Disable and stop firewalld service
PRINT_TASK "[TASK: Disable and stop firewalld service]"

# List of services to handle
services=("firewalld")

# Loop through each service in the list
for service in "${services[@]}"; do
    # Disable the service
    systemctl disable "$service" &>/dev/null
    disable_status=$?
    # Stop the service
    systemctl stop "$service" &>/dev/null
    stop_status=$?
    # Check if both disable and stop commands executed successfully
    if [ $disable_status -eq 0 ] && [ $stop_status -eq 0 ]; then
        echo "ok: [$service service stopped and disabled]"
    else
        echo "failed: [$service service is not stopped or disabled]"
    fi
done

# Add an empty line after the task
echo
######

# Task: Change SELinux security policy
PRINT_TASK "[TASK: Change SELinux security policy]"

# Temporarily set SELinux security policy to permissive
setenforce 0 &>/dev/null
# Check temporary SELinux security policy
temporary_status=$(getenforce)
# Check if temporary SELinux security policy is permissive or disabled
if [[ $temporary_status == "Permissive" || $temporary_status == "Disabled" ]]; then
    echo "OK: [selinux temporary security policy is $temporary_status]"
else
    echo "Failed: [selinux temporary security policy is $temporary_status (expected Permissive or Disabled)]"
fi


# Read the SELinux configuration
permanent_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
# Check if the permanent status is Enforcing
if [[ $permanent_status == "enforcing" ]]; then
    # Change SELinux to permissive
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    permanent_status="permissive"
    echo "OK: SELinux permanent security policy changed to $permanent_status"
elif [[ $permanent_status == "disabled" ]]; then
    echo "OK: SELinux permanent security policy is $permanent_status"
else
    echo "Failed: SELinux permanent security policy is $permanent_status (expected Permissive or Disabled)"
fi
# Check if SELinux is enforcing and update config if needed
if [ "$SELINUX" = "Enforcing" ]; then
  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
fi

