#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export REGISTRY_HOSTNAME="mirror.registry.example.com"
export REGISTRY_HOST_IP="10.184.134.30"
export REGISTRY_ID="admin"
export REGISTRY_PW="password"
export REGISTRY_INSTALL_DIR="/opt/quay-install"
export OCP_TRUSTED_CA="true"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Function to check command success and display appropriate message
run_command() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo -e "\e[96mINFO\e[0m $1"
    else
        echo -e "\e[31mFAILED\e[0m $1"
        exit 1
    fi
}

# Step 1:
PRINT_TASK "TASK [Delete existing duplicate data]"

# Check if there is an quay-app.service
 if [ -f /etc/systemd/system/quay-pod.service ]; then
    echo -e "\e[96mINFO\e[0m Mirror registry detected starting uninstall"
    if ${REGISTRY_INSTALL_DIR}/mirror-registry uninstall -v --autoApprove --quayRoot "${REGISTRY_INSTALL_DIR}" > /dev/null 2>&1; then
        echo -e "\e[96mINFO\e[0m Uninstall the mirror registry"
    else
        echo -e "\e[31mFAILED\e[0m Uninstall the mirror registry"
        exit 1 
    fi
else
    echo -e "\e[96mINFO\e[0m No mirror registry is running"
fi

# Delete existing duplicate data
rm -rf "/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.ca.pem" >/dev/null 2>&1
rm -rf "${REGISTRY_INSTALL_DIR}" >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 2: 
PRINT_TASK "TASK [Install Infrastructure RPM]"

# List of RPM packages to install
packages=("wget" "podman")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
echo -e "\e[96mINFO\e[0m Installing RPM package..."
dnf install -y $package_list >/dev/null 2>&1

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "\e[96mINFO\e[0m Install $package package"
    else
        echo -e "\e[31mFAILED\e[0m Install $package package"
    fi
done

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Install Mirror Registry]"

# Create installation directory
sudo mkdir -p ${REGISTRY_INSTALL_DIR}
sudo mkdir -p ${REGISTRY_INSTALL_DIR}/quay-storage
sudo mkdir -p ${REGISTRY_INSTALL_DIR}/sqlite-storage
sudo chmod -R 777 ${REGISTRY_INSTALL_DIR}
run_command "Create the ${REGISTRY_INSTALL_DIR} directory and modify its permissions"

# Download mirror registry
echo -e "\e[96mINFO\e[0m Downloading the mirror registry package"

# wget -P ${REGISTRY_INSTALL_DIR} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz >/dev/null 2>&1
sudo wget -O ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz >/dev/null 2>&1
run_command "Download mirror-registry package"

# Extract the downloaded mirror-registry package
sudo tar xvf ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_DIR}/ >/dev/null 2>&1
run_command "Extract the mirror-registry package"


# Add registry entry to /etc/hosts
if ! grep -q "$REGISTRY_HOSTNAME" /etc/hosts; then
  echo "# Add registry entry to /etc/hosts" | sudo tee -a /etc/hosts > /dev/null
  echo "$REGISTRY_HOST_IP $REGISTRY_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
  echo -e "\e[96mINFO\e[0m Add registry entry to /etc/hosts"
else
  echo -e "\e[96mINFO\e[0m Registry entry already exists in /etc/hosts"
fi

# Install mirror-registry
echo -e "\e[96mINFO\e[0m Installing the mirror registry..."
sudo ${REGISTRY_INSTALL_DIR}/mirror-registry install \
     --quayHostname ${REGISTRY_HOSTNAME} \
     --quayRoot ${REGISTRY_INSTALL_DIR} \
     --quayStorage ${REGISTRY_INSTALL_DIR}/quay-storage \
     --sqliteStorage ${REGISTRY_INSTALL_DIR}/sqlite-storage \
     --initUser ${REGISTRY_ID} \
     --initPassword ${REGISTRY_PW}
run_command "Installation complete"

# Wait for quay-pod pods to be in Running state
MAX_RETRIES=100               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started

while true; do
    # Get the status of all pods
    output=$(sudo podman pod ps | awk 'NR>1' | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b3\b)')

    CHAR=${SPINNER[$((retry_count % 4))]}

    if [ -n "$output" ]; then
        # Pod is running
        if $progress_started; then
            printf "\n"  # Ensure newline after spinner line
        fi
        echo -e "\e[96mINFO\e[0m Quay pod is in 'Running' state"
        break
    else
        # Pod not yet running, show spinner
        if ! $progress_started; then
            progress_started=true
        fi
        # Display spinner on same line
        printf "\r\e[96mINFO\e[0m Waiting for quay pod to be in 'Running' state %s" "$CHAR"
        tput el  # Clear to end of line
    fi

    sleep $SLEEP_INTERVAL
    retry_count=$((retry_count + 1))

    # Exit if max retries exceeded
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r"   # Move to line start
        tput el       # Clear line
        echo -e "\e[31mFAILED\e[0m Quay pod did not reach 'Running' state after $MAX_RETRIES retries"
        exit 1
    fi
done

# Copy the rootCA certificate to the trusted source
sudo cp ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.ca.pem
run_command "Copy rootCA certificate to trusted anchors"

# Trust the rootCA certificate
sudo update-ca-trust
run_command "Trust the rootCA certificate"

# Delete the tar package generated during installation
sudo rm -rf pause.tar postgres.tar quay.tar redis.tar >/dev/null 2>&1
run_command "Delete the tar package: pause.tar postgres.tar quay.tar redis.tar"

# loggin registry
sudo podman login -u ${REGISTRY_ID} -p ${REGISTRY_PW} https://${REGISTRY_HOSTNAME}:8443 >/dev/null 2>&1
run_command "Login registry https://${REGISTRY_HOSTNAME}:8443"

# Check the environment variable OCP_TRUSTED_CA: continue if "true", exit if otherwise
if [[ "$OCP_TRUSTED_CA" != "true" ]]; then
    echo -e "\e[96mINFO\e[0m Quay Console: https://${REGISTRY_HOSTNAME}:8443"
    echo -e "\e[96mINFO\e[0m podman login ${REGISTRY_HOSTNAME}:8443 -u $REGISTRY_ID -p $REGISTRY_PW"
    echo -e "\e[33mACTION\e[0m Add DNS Records for Mirror Registry to Allow OCP Access"
    exit 0
fi

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Configuring additional trust stores for image registry access]"

# Check if the registry-cas field exists
REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if [[ -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-config --from-file=${REGISTRY_HOSTNAME}..8443=/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command  "Create a configmap containing the registry CA certificate: registry-config"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null 2>&1
  run_command  "Trust the registry-config configmap"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-cas --from-file=${REGISTRY_HOSTNAME}..8443=/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command  "Create a configmap containing the registry CA certificate: registry-cas"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge >/dev/null 2>&1
  run_command  "Trust the registry-cas configmap"
fi

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Update the global pull-secret]"

sudo rm -rf pull-secret >/dev/null 2>&1
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret
run_command  "Export pull-secret file"

podman login -u $REGISTRY_ID -p $REGISTRY_PW --authfile pull-secret ${REGISTRY_HOSTNAME}:8443 >/dev/null 2>&1
run_command  "Authentication identity information to the pull-secret file"

oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret >/dev/null 2>&1
run_command  "Update pull-secret for the cluster"

sudo rm -rf pull-secret >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Checking the cluster status]"


# Wait for all MachineConfigPools (MCPs) to be Ready
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get MCP statuses: Ready, Updated, Degraded
    output=$(/usr/local/bin/oc get mcp --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    # If any MCP is not Ready/Updated/Degraded as expected
    if echo "$output" | grep -q -v "True False False"; then
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for all MCPs to be Ready... %s" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for all MCPs to be Ready... %s" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))
        # Timeout handling
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m MCPs not Ready%*s\n" $((LINE_WIDTH - 20)) ""
            exit 1
        fi
    else
        # All MCPs are Ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m All MCPs are Ready%*s\n" $((LINE_WIDTH - 18)) ""
        else
            printf "\e[96mINFO\e[0m All MCPs are Ready%*s\n" $((LINE_WIDTH - 18)) ""
        fi
        break
    fi
done

# Wait for all Cluster Operators (COs) to be Ready
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get Cluster Operator statuses: Available, Progressing, Degraded
    output=$(/usr/local/bin/oc get co --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    # If any CO is not Available/Progressing/Degraded as expected
    if echo "$output" | grep -q -v "True False False"; then
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))
        # Timeout handling
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m Cluster Operators not Ready%*s\n" $((LINE_WIDTH - 31)) ""
            exit 1
        fi
    else
        # All Cluster Operators are Ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        else
            printf "\e[96mINFO\e[0m All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        fi
        break
    fi
done

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Quay Login Guide]"

echo -e "\e[96mINFO\e[0m Quay Console: https://${REGISTRY_HOSTNAME}:8443"
echo -e "\e[96mINFO\e[0m CLI: podman login ${REGISTRY_HOSTNAME}:8443 -u $REGISTRY_ID -p $REGISTRY_PW"

# Add an empty line after the task
echo

# Step 8:
PRINT_TASK "TASK [Add DNS Record Entries for Mirror Registry]"

echo -e "\e[33mACTION\e[0m Add DNS Records for Mirror Registry to Allow OCP Access"

# Add an empty line after the task
echo
