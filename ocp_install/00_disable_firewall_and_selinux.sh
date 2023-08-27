#!/bin/bash
#######################################################

echo ====== Disable and check firewalld ======
# disable firewalld
systemctl disable firewalld
systemctl stop firewalld

# Wait for a short moment for httpd to start
sleep 10

# Check if a service is disabled
check_service_disabled() {
    service_name=$1
    if systemctl is-enabled "$service_name" | grep -q "disabled"; then
        return 0
    else
        return 1
    fi
}

# Check if a service is stopped
check_service_stopped() {
    service_name=$1
    if systemctl is-active "$service_name" | grep -q "inactive"; then
        return 0
    else
        return 1
    fi
}

# Display status message
display_status_message() {
    service_name=$1
    if check_service_disabled "$service_name" && check_service_stopped "$service_name"; then
        echo "$service_name service is successfully disabled and stopped."
    elif ! check_service_disabled "$service_name"; then
        echo "Error: $service_name service is not disabled."
    elif ! check_service_stopped "$service_name"; then
        echo "Error: $service_name service is not stopped."
    else
        echo "Error: Unable to determine status of $service_name service."
    fi
}

# Check and display status for specific services
display_status_message "firewalld"

#######################################################

echo ====== Disable and check SeLinux ======
# Get current SELinux status
SELINUX=$(getenforce)
echo "$SELINUX"

# Check if SELinux is enforcing and update config if needed
if [ "$SELINUX" = "Enforcing" ]; then
  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
fi

# Temporarily set SELinux to permissive
setenforce 0 &>/dev/null

# Check current SELinux status (temporary)
current_status=$(getenforce)
echo "Current SELinux status (temporary): $current_status"

# Check permanent SELinux status
config_file_status=$(grep -E "^SELINUX=" /etc/selinux/config | awk -F= '{print $2}')
echo "Permanent SELinux status: $config_file_status"

# Check if both temporary and permanent statuses are not permissive or disabled
if [ "$current_status" != "Permissive" -a "$current_status" != "Disabled" ] || \
   [ "$config_file_status" != "permissive" -a "$config_file_status" != "disabled" ]; then
    echo "Error: SELinux should be set to 'permissive' or 'disabled'."
fi

#######################################################
