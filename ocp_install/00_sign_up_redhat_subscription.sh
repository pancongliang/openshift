#!/bin/bash

#######################################################

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=45  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

#######################################################

# Task: Sign up for a Red Hat Subscription
PRINT_TASK "[TASK: Sign up for a Red Hat Subscription]"

read -p "Please input the OpenShift Version (for example 4.5.12):" OCP_VER
read -s -p "Please input the Red Hat Subscribe UserName:" SUB_USER
echo -e "\r"
read -s -p "Please input the Red Hat Subscribe Password:" SUB_PASSWD
echo -e "\r"

subscription-manager register --force --user ${SUB_USER} --password ${SUB_PASSWD}
subscription-manager refresh
subscription-manager list --available --matches '*OpenShift Container Platform*' | grep "Pool ID"
read -p "Please input the Pool ID you got:" POOL_ID
subscription-manager attach --pool=${POOL_ID}
