#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: Command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export OCP_VERSION=4.16.26
export INSTALL_DIR="$HOME/aws-ipi/ocp"
export SSH_KEY_PATH="$HOME/.ssh"
export PULL_SECRET_PATH="$HOME/aws-ipi/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export CLUSTER_NAME="xxxxxx"
export BASE_DOMAIN="xxxxxx"
export REGION="ap-northeast-1"
export AWS_ACCESS_KEY_ID="xxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxx"
export WORKER_INSTANCE_TYPE='m6a.2xlarge'           # (m6a.4xlarge vcpu: 16 mem:64 / Bare Metal: c5n.metal)https://aws.amazon.com/cn/ec2/instance-types/m6a/


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
PRINT_TASK "TASK [Set up AWS Credentials]"

# Create AWS credentials
rm -rf $HOME/.aws >/dev/null 2>&1 || true
mkdir -p $HOME/.aws

cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "Set up aws credentials"

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Install OpenShift Install and Client Tools]"

# Determine the operating system
OS_TYPE=$(uname -s)
echo -e "\e[96mINFO\e[0m Client operating system: $OS_TYPE"

ARCH=$(uname -m)
echo -e "\e[96mINFO\e[0m Client architecture: $ARCH"

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
    echo -e "\e[96mINFO\e[0m Downloading the openshift-install tool"
    curl -sL "$download_url" -o "$openshift_install"
    run_command "Download openshift-install"

    sudo rm -f /usr/local/bin/openshift-install >/dev/null 2>&1 || true
    sudo tar -xzf "$openshift_install" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "Install openshift-install"

    chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
    run_command "Set permissions for /usr/local/bin/openshift-install"
    
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
    echo -e "\e[96mINFO\e[0m Downloading the openshift-client tool"
    curl -sL "$download_url" -o "$openshift_client"
    run_command "Download openshift-client"

    sudo rm -f /usr/local/bin/oc >/dev/null 2>&1 || true
    sudo rm -f /usr/local/bin/kubectl >/dev/null 2>&1 || true
    sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1 || true

    sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "install openshift-client"

    sudo chmod +x /usr/local/bin/oc >/dev/null 2>&1
    run_command "Set permissions for /usr/local/bin/oc"

    sudo chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
    run_command "Set permissions for /usr/local/bin/kubectl"
   
    rm -rf "$openshift_client" >/dev/null 2>&1

# Handle Linux
elif [ "$OS_TYPE" = "Linux" ]; then
    # Download the OpenShift Installer
    echo -e "\e[96mINFO\e[0m Downloading the openshift-install tool"
    curl -sL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" -o "openshift-install-linux.tar.gz"
    run_command "Download openshift-install tool"

    sudo rm -f /usr/local/bin/openshift-install >/dev/null 2>&1 || true
    sudo tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "Install openshift-install tool"

    sudo chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
    run_command "Set permissions for /usr/local/bin/openshift-install"
    rm -rf openshift-install-linux.tar.gz >/dev/null 2>&1

    # Delete the old version of oc cli
    sudo rm -f /usr/local/bin/oc >/dev/null 2>&1 || true
    sudo rm -f /usr/local/bin/kubectl >/dev/null 2>&1 || true
    sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1 || true

    # Get the RHEL version number
    rhel_version=$(rpm -E %{rhel})
    run_command "Check RHEL version"

    # Determine the download URL based on the RHEL version
    if [ "$rhel_version" -eq 8 ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-amd64-rhel8.tar.gz"
        openshift_client="openshift-client-linux-amd64-rhel8.tar.gz"
    elif [ "$rhel_version" -eq 9 ]; then
        download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
        openshift_client="openshift-client-linux.tar.gz"
    fi

    # Download the OpenShift client
    echo -e "\e[96mINFO\e[0m Downloading the openshift-client tool"
    curl -sL "$download_url" -o "$openshift_client"
    run_command "Download openshift client tool"

    # Extract the downloaded tarball to /usr/local/bin/
    sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
    run_command "Install openshift client tool"

    sudo chmod +x /usr/local/bin/oc >/dev/null 2>&1
    run_command "Set permissions for /usr/local/bin/oc"

    sudo chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
    run_command "Set permissions for /usr/local/bin/kubectl"

    sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1 || true
    sudo rm -rf $openshift_client >/dev/null 2>&1 || true
fi

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Create OpenShift Cluster]"

# Check if the SSH key exists
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo -e "\e[96mINFO\e[0m Create ssh-key for accessing node"
else
    echo -e "\e[96mINFO\e[0m Create ssh-key for accessing node"
fi

sudo rm -rf $INSTALL_DIR >/dev/null 2>&1 || true
mkdir -p $INSTALL_DIR >/dev/null 2>&1
run_command "Create install dir: $INSTALL_DIR"

cat << EOF > $INSTALL_DIR/install-config.yaml 
#additionalTrustBundlePolicy: Proxyonly
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
run_command "Create install-config.yaml file"

export PATH="/usr/local/bin:$PATH"

# Generate manifests
/usr/local/bin/openshift-install create manifests --dir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "Generate kubernetes manifests"

cat << EOF > ${INSTALL_DIR}/manifests/custom-openshift-config-secret-htpasswd-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: htpasswd-secret
  namespace: openshift-config
type: Opaque
data:
  htpasswd: YWRtaW46JDJ5JDA1JDNLdkxTckw0TDhXb3Z4cVk3eGpLRWUxVHg0U21PODZBR3VxSzVteVRDTmVLeG80dmNtaFpxCg==
EOF
run_command "Create htpasswd secret manifests"

cat << EOF > ${INSTALL_DIR}/manifests/custom-clusterrolebinding-cluster-admin-0.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin-0
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: admin
EOF
run_command "Create cluster-admin clusterrolebinding manifests"

cat << EOF > ${INSTALL_DIR}/manifests/custom-cluster-oauth.yaml
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
run_command "Create oauth htpasswd identityprovider manifests"

/usr/local/bin/openshift-install create cluster --dir "$INSTALL_DIR" --log-level=info
run_command "Install OpenShift AWS IPI completed"

echo -e "\e[96mINFO\e[0m Login using htpasswd user: oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443"
echo -e "\e[96mINFO\e[0m Login using kubeconfig: export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig"

# Add an empty line after the task
echo
