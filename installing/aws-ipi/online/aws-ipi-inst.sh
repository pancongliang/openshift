#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export OCP_VERSION=4.16.20
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
export SSH_KEY_PATH="$HOME/.ssh"
export PULL_SECRET_PATH="$HOME/aws-ipi/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export REGION="ap-northeast-1"
export AWS_ACCESS_KEY_ID="xxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxx"
export WORKER_INSTANCE_TYPE='m6a.2xlarge'             # (m6a.4xlarge vcpu: 16 mem:64 / Bare Metal: c5n.metal)https://aws.amazon.com/cn/ec2/instance-types/m6a/


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
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 1:
PRINT_TASK "TASK [Set up AWS credentials]"

# Create AWS credentials
rm -rf $HOME/.aws
mkdir -p $HOME/.aws

cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[set up aws credentials]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Install openshift-install adn oc-cli]"

# Determine the operating system
OS_TYPE=$(uname -s)
echo "info: [client operating system: $OS_TYPE]"

ARCH=$(uname -m)
echo "info: [client architecture: $ARCH]"

# Handle macOS
if [ "$OS_TYPE" = "Darwin" ]; then
    # Determine the download URL based on the architecture
    if [ "$ARCH" = "x86_64" ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-mac.tar.gz"
        openshift_install="openshift-install-mac.tar.gz"
    elif [ "$ARCH" = "arm64" ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-mac-arm64.tar.gz"
        openshift_install="openshift-install-mac-arm64.tar.gz"
    fi

    # Download, install, and clean up OpenShift Installer
    curl -sL "$download_url" -o "$openshift_install"
    run_command "[download openshift-install]"

    sudo rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
    sudo tar -xzf "$openshift_install" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "[install openshift-install]"

    sudo chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
    rm -rf "$openshift_install" >/dev/null 2>&1

    # Determine the download URL for OpenShift Client
    if [ "$ARCH" = "x86_64" ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-mac.tar.gz"
        openshift_client="openshift-client-mac.tar.gz"
    elif [ "$ARCH" = "arm64" ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-mac-arm64.tar.gz"
        openshift_client="openshift-client-mac-arm64.tar.gz"
    fi

    # Download, install, and clean up OpenShift Client
    curl -sL "$download_url" -o "$openshift_client"
    run_command "[download openshift-client]"

    sudo rm -f /usr/local/bin/oc >/dev/null 2>&1
    sudo rm -f /usr/local/bin/kubectl >/dev/null 2>&1
    sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1

    sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "[install openshift-client]"

    sudo chmod +x /usr/local/bin/oc >/dev/null 2>&1
    sudo chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
    rm -rf "$openshift_client" >/dev/null 2>&1

# Handle Linux
elif [ "$OS_TYPE" = "Linux" ]; then
    # Download the OpenShift Installer
    curl -sL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" -o "openshift-install-linux.tar.gz"
    run_command "[download openshift-install tool]"

    sudo rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
    sudo tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "[install openshift-install tool]"

    sudo chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
    run_command "[modify /usr/local/bin/openshift-install permissions]"
    rm -rf openshift-install-linux.tar.gz >/dev/null 2>&1

    # Delete the old version of oc cli
    sudo rm -f /usr/local/bin/oc >/dev/null 2>&1
    sudo rm -f /usr/local/bin/kubectl >/dev/null 2>&1
    sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1

    # Get the RHEL version number
    rhel_version=$(rpm -E %{rhel})
    run_command "[check rhel version]"

    # Determine the download URL based on the RHEL version
    if [ "$rhel_version" -eq 8 ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-amd64-rhel8.tar.gz"
        openshift_client="openshift-client-linux-amd64-rhel8.tar.gz"
    elif [ "$rhel_version" -eq 9 ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
        openshift_client="openshift-client-linux.tar.gz"
    fi

    # Download the OpenShift client
    curl -sL "$download_url" -o "$openshift_client"
    run_command "[download openshift client tool]"

    # Extract the downloaded tarball to /usr/local/bin/
    sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "[install openshift client tool]"

    sudo chmod +x /usr/local/bin/oc >/dev/null 2>&1
    run_command "[modify /usr/local/bin/oc permissions]"
    
    sudo chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
    run_command "[modify /usr/local/bin/kubectl permissions]"

    sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1
    sudo rm -rf $openshift_client >/dev/null 2>&1
fi

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Create openshift cluster]"

# Check if the SSH key exists
if [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH}
    ssh-keygen -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    run_command "[generate ssh keys]"
else
    echo "info: [ssh key already exists, skip generation]"
fi

rm -rf $OCP_INSTALL_DIR >/dev/null 2>&1
mkdir -p $OCP_INSTALL_DIR >/dev/null 2>&1
run_command "[create install dir: $OCP_INSTALL_DIR]"

cat << EOF > $OCP_INSTALL_DIR/install-config.yaml 
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: $WORKER_INSTANCE_TYPE
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  creationTimestamp: null
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $REGION
publish: External
pullSecret: '$(cat $PULL_SECRET_PATH)'
sshKey: |
  $(cat $SSH_KEY_PATH/id_rsa.pub)
EOF
run_command "[create the install-config.yaml file]"

echo "ok: [installing the OpenShift cluster]"

export PATH="/usr/local/bin:$PATH"

openshift-install create cluster --dir "$OCP_INSTALL_DIR" --log-level=info
run_command "[install OpenShift AWS IPI completed]"

# Check cluster operator status
progress_started=false
while true; do
    operator_status=$(oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    
    if echo "$operator_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 60
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Create htpasswd User]"

rm -rf $OCP_INSTALL_DIR/users.htpasswd
echo 'admin:$2y$05$.9uG3eMC1vrnhLIj8.v.POcGpFEN/STrpOw7yGQ5dnMmLbrKVVCmu' > $OCP_INSTALL_DIR/users.htpasswd
run_command "[create a user using the htpasswd tool]"

sleep 10

oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$OCP_INSTALL_DIR/users.htpasswd -n openshift-config >/dev/null 2>&1
run_command "[create a secret using the users.htpasswd file]"

rm -rf $OCP_INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
cat  <<EOF | oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig apply -f - > /dev/null 2>&1
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - htpasswd:
      fileData:
        name: htpasswd-secret
    mappingMethod: claim
    name: htpasswd-user
    type: HTPasswd
EOF
run_command "[setting up htpasswd authentication]"

# Grant the 'cluster-admin' cluster role to the user 'admin'
oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin >/dev/null 2>&1
run_command "[grant cluster-admin permissions to the admin user]"

echo "info: [restarting oauth pod, waiting...]"
sleep 100

# Check cluster operator status
progress_started=false
while true; do
    operator_status=$(oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    
    if echo "$operator_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 60
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
progress_started=false

while true; do
    mcp_status=$(oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig get mcp --no-headers | awk '{print $3, $4, $5}')

    if echo "$mcp_status" | grep -q -v "True False False"; then
        if ! $progress_started; then
            echo -n "info: [waiting for all mcps to reach the expected state"
            progress_started=true  
        fi
        
        echo -n '.'
        sleep 60
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all mcp have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 5:
# PRINT_TASK "TASK [Login OCP Cluster]"

#oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443 --insecure-skip-tls-verify >/dev/null 2>&1
#run_command "[log in to the cluster using the htpasswd user]"

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Login cluster information]"

echo "info: [log in to the cluster using the htpasswd user:  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo "info: [log in to the cluster using kubeconfig:  export KUBECONFIG=$OCP_INSTALL_DIR/auth/kubeconfig]"

# Add an empty line after the task
echo
