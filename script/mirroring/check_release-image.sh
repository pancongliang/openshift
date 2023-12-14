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

PRINT_TASK "[TASK: docker.registry.example.com:5000/ocp4/openshift4]"
podman search docker.registry.example.com:5000/ocp4/openshift4 --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret

PRINT_TASK "[TASK: docker.registry.example.com:5000/openshift/release-images]"
podman search docker.registry.example.com:5000/openshift/release-images --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret

PRINT_TASK "[TASK: mirror.registry.example.com:8443/openshift/release-images]"
podman search mirror.registry.example.com:8443/openshift/release-images --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret
