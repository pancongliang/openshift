#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export OCP_VERSION=4.14.20
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
sudo rm -rf $HOME/.aws
sudo mkdir -p $HOME/.aws
sudo cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[Set up AWS credentials]"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Install openshift-install adn oc-cli]"

# Determine the operating system
OS_TYPE=$(uname -s)
echo "info: [Client Operating System: $OS_TYPE]"

ARCH=$(uname -m)
echo "info: [Client Architecture: $ARCH]"

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
    sudo curl -sL "$download_url" -o "$openshift_install"
    run_command "[Download openshift-install]"

    sudo rm -f /usr/local/bin/openshift-install &> /dev/null
    sudo tar -xzf "$openshift_install" -C "/usr/local/bin/" &> /dev/null
    run_command "[Install openshift-install]"

    sudo chmod +x /usr/local/bin/openshift-install &> /dev/null
    sudo rm -rf "$openshift_install" &> /dev/null

    # Determine the download URL for OpenShift Client
    if [ "$ARCH" = "x86_64" ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-mac.tar.gz"
        openshift_client="openshift-client-mac.tar.gz"
    elif [ "$ARCH" = "arm64" ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-mac-arm64.tar.gz"
        openshift_client="openshift-client-mac-arm64.tar.gz"
    fi

    # Download, install, and clean up OpenShift Client
    sudo curl -sL "$download_url" -o "$openshift_client"
    run_command "[Download openshift-client]"

    sudo rm -f /usr/local/bin/oc &> /dev/null
    sudo rm -f /usr/local/bin/kubectl &> /dev/null
    sudo rm -f /usr/local/bin/README.md &> /dev/null

    sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" &> /dev/null
    run_command "[Install openshift-client]"

    sudo chmod +x /usr/local/bin/oc &> /dev/null
    sudo chmod +x /usr/local/bin/kubectl &> /dev/null
    rm -rf "$openshift_client" &> /dev/null

# Handle Linux
elif [ "$OS_TYPE" = "Linux" ]; then
    # Download the OpenShift Installer
    sudo curl -sL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" -o "openshift-install-linux.tar.gz"
    run_command "[Download openshift-install tool]"

    sudo rm -f /usr/local/bin/openshift-install &> /dev/null
    sudo tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" &> /dev/null
    run_command "[Install openshift-install tool]"

    sudo chmod +x /usr/local/bin/openshift-install &> /dev/null
    run_command "[Modify /usr/local/bin/openshift-install permissions]"
    sudo rm -rf openshift-install-linux.tar.gz &> /dev/null

    # Delete the old version of oc cli
    sudo rm -f /usr/local/bin/oc &> /dev/null
    sudo rm -f /usr/local/bin/kubectl &> /dev/null
    sudo rm -f /usr/local/bin/README.md &> /dev/null

    # Get the RHEL version number
    rhel_version=$(sudo rpm -E %{rhel})
    run_command "[Check RHEL version]"

    # Determine the download URL based on the RHEL version
    if [ "$rhel_version" -eq 8 ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-amd64-rhel8.tar.gz"
        openshift_client="openshift-client-linux-amd64-rhel8.tar.gz"
    elif [ "$rhel_version" -eq 9 ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
        openshift_client="openshift-client-linux.tar.gz"
    fi

    # Download the OpenShift client
    sudo curl -sL "$download_url" -o "$openshift_client"
    run_command "[Download OpenShift client tool]"

    # Extract the downloaded tarball to /usr/local/bin/
    sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" &> /dev/null
    run_command "[Install openshift client tool]"

    sudo chmod +x /usr/local/bin/oc &> /dev/null
    run_command "[Modify /usr/local/bin/oc permissions]"
    sudo chmod +x /usr/local/bin/kubectl &> /dev/null
    run_command "[Modify /usr/local/bin/kubectl permissions]"

    sudo rm -f /usr/local/bin/README.md &> /dev/null
    sudo rm -rf $openshift_client &> /dev/null

    # Install httpd-tools
    dnf install httpd-tools -y &> /dev/null
    run_command "[Install httpd-tools]"
fi

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Create openshift cluster]"

# Check if the SSH key exists
if [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    sudo rm -rf ${SSH_KEY_PATH}
    sudo ssh-keygen -N '' -f ${SSH_KEY_PATH}/id_rsa &> /dev/null &> /dev/null
    run_command "[Generate SSH keys:]"
else
    echo "info: [SSH key already exists, skip generation]"
fi

sudo rm -rf $OCP_INSTALL_DIR &> /dev/null
sudo mkdir -p $OCP_INSTALL_DIR &> /dev/null
run_command "[Create install dir: $OCP_INSTALL_DIR]"

sudo cat << EOF > $OCP_INSTALL_DIR/install-config.yaml 
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
run_command "[Create the install-config.yaml file]"

sudo rm -rf $OCP_INSTALL_DIR/install.log
echo "ok: [Installing the OpenShift cluster]"
openshift-install create cluster --dir "$OCP_INSTALL_DIR" --log-level=info
run_command "[Install OpenShift AWS IPI completed]"

while true; do
    operator_status=$(oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    if echo "$operator_status" | grep -q -v "True False False"; then
        echo "info: [All cluster operators have not reached the expected status, Waiting...]"
        sleep 60  
    else
        echo "ok: [All cluster operators have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Create htpasswd User]"

sudo rm -rf $OCP_INSTALL_DIR/users.htpasswd
sudo htpasswd -c -B -b $OCP_INSTALL_DIR/users.htpasswd admin redhat &> /dev/null
run_command "[Create a user using the htpasswd tool]"

oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$OCP_INSTALL_DIR/users.htpasswd -n openshift-config &> /dev/null
run_command "[Create a secret using the users.htpasswd file]"

sudo rm -rf $OCP_INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
sudo cat  <<EOF | /usr/local/bin/oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig apply -f - > /dev/null 2>&1
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
run_command "[Setting up htpasswd authentication]"

# Grant the 'cluster-admin' cluster role to the user 'admin'
oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin &> /dev/null
run_command "[Grant cluster-admin permissions to the admin user]"

echo "info: [Restarting oauth pod, waiting...]"
sleep 100

while true; do
    operator_status=$(oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    if echo "$operator_status" | grep -q -v "True False False"; then
        echo "info: [All cluster operators have not reached the expected status, Waiting...]"
        sleep 60  
    else
        echo "ok: [All cluster operators have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 5:
#PRINT_TASK "TASK [Login OCP Cluster]"

#oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443 --insecure-skip-tls-verify &> /dev/null
#run_command "[Log in to the cluster using the htpasswd user]"

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Login cluster information]"

echo "info: [Log in to the cluster using the htpasswd user:  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo "info: [Log in to the cluster using kubeconfig:  export KUBECONFIG=$OCP_INSTALL_DIR/auth/kubeconfig]"
echo
# ====================================================
