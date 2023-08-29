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



检查/etc/selinux/config中的selinux permanent security policy
如果是Enforcing则更改为permissive，更改完成后提示"OK: [selinux permanent security policy is $permanent_status]"
如果是disabled 则无需更改直接提示"OK: [selinux permanent security policy is $permanent_status]"
如果更改失败则提示"Failed: [selinux permanent security policy is $permanent_status (expected Permissive or Disabled)]"

# Check if SELinux is enforcing and update config if needed
if [ "$SELINUX" = "Enforcing" ]; then
  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
fi

# Temporarily set SELinux to permissive
setenforce 0 &>/dev/null

# Check current SELinux status (temporary)
temporary_status=$(getenforce)
echo "Current SELinux status (temporary): $temporary_status"

# Check permanent SELinux status
config_file_status=$(grep -E "^SELINUX=" /etc/selinux/config | awk -F= '{print $2}')
echo "Permanent SELinux status: $config_file_status"

# Check if both temporary and permanent statuses are not permissive or disabled
if [ "$temporary_status" != "Permissive" -a "$temporary_status" != "Disabled" ] || \
   [ "$config_file_status" != "permissive" -a "$config_file_status" != "disabled" ]; then
    echo "Error: SELinux should be set to 'permissive' or 'disabled'."
fi

#######################################################
