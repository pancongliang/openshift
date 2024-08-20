#!/bin/bash

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
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}
# ====================================================


# === Task: Set up AWS credentials ===
PRINT_TASK "[TASK: Set up AWS credentials]"
rm -rf $HOME/.aws
mkdir -p $HOME/.aws
cat << EOF > "$HOME/.aws/credentials"
[default]
cli_pager=
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
run_command "[Set up AWS credentials]"

echo
# ====================================================


# === Task: Install openshift-install and oc cli tool===
PRINT_TASK "[TASK: Install openshift-install adn oc-cli tool]"

# Download the openshift-install
wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" &> /dev/null
run_command "[Download openshift-install tool]"

rm -f /usr/local/bin/openshift-install &> /dev/null
tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" &> /dev/null
run_command "[Install openshift-install tool]"

chmod +x /usr/local/bin/openshift-install &> /dev/null
run_command "[modify /usr/local/bin/openshift-install permissions]"
rm -rf openshift-install-linux.tar.gz &> /dev/null

# Delete the old version of oc cli
rm -f /usr/local/bin/oc &> /dev/null
rm -f /usr/local/bin/kubectl &> /dev/null
rm -f //usr/local/bin/README.md &> /dev/null

# Get the RHEL version number
rhel_version=$(rpm -E %{rhel})
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
wget -q "$download_url" -O "$openshift_client"
run_command "[Download OpenShift client tool]"

# Extract the downloaded tarball to /usr/local/bin/
tar -xzf "$openshift_client" -C "/usr/local/bin/" &> /dev/null
run_command "[Install openshift client tool]"

chmod +x /usr/local/bin/oc &> /dev/null
run_command "[modify /usr/local/bin/oc permissions]"
chmod +x /usr/local/bin/kubectl &> /dev/null
run_command "[modify /usr/local/bin/kubectl permissions]"

rm -f /usr/local/bin/README.md &> /dev/null
rm -rf $openshift_client &> /dev/null
echo
# ====================================================

# === Task: Create openshift cluster ===
PRINT_TASK "[TASK: Create openshift cluster]"

# Check if the SSH key exists
if [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH}
    ssh-keygen -N '' -f ${SSH_KEY_PATH}/id_rsa &> /dev/null &> /dev/null
    run_command "[Generate SSH keys:]"
else
    echo "info: [SSH key already exists, skip generation]"
fi

rm -rf $OCP_INSTALL_DIR &> /dev/null
mkdir -p $OCP_INSTALL_DIR &> /dev/null
run_command "[Create install dir: $OCP_INSTALL_DIR]"

cat << EOF > $OCP_INSTALL_DIR/install-config.yaml 
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
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

rm -rf $OCP_INSTALL_DIR/install.log
echo "ok: [Installing the OpenShift cluster]"
/usr/local/bin/openshift-install create cluster --dir "$OCP_INSTALL_DIR" --log-level=info
run_command "[Install OpenShift AWS IPI completed]"

while true; do
    operator_status=$(/usr/local/bin/oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig get co --no-headers | awk '{print $3, $4, $5}')
    if echo "$operator_status" | grep -q -v "True False False"; then
        echo "info: [All cluster operators have not reached the expected status, Waiting...]"
        sleep 60  
    else
        echo "ok: [All cluster operators have reached the expected state]"
        break
    fi
done

echo
# ====================================================


# === Task: Create htpasswd User ===
PRINT_TASK "[TASK: Create htpasswd User]"

yum install httpd-tools -y &> /dev/null
run_command "[Install htpasswd tool]"

rm -rf $OCP_INSTALL_DIR/users.htpasswd
htpasswd -c -B -b $OCP_INSTALL_DIR/users.htpasswd admin redhat &> /dev/null
run_command "[Create a user using the htpasswd tool]"

/usr/local/bin/oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$OCP_INSTALL_DIR/users.htpasswd -n openshift-config &> /dev/null
run_command "[Create a secret using the users.htpasswd file]"

rm -rf $OCP_INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
cat  <<EOF | /usr/local/bin/oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig apply -f - > /dev/null 2>&1
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
/usr/local/bin/oc --kubeconfig=$OCP_INSTALL_DIR/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin &> /dev/null
run_command "[Grant cluster-admin permissions to the admin user]"

echo "info: [Restarting oauth pod, waiting...]"
sleep 100
echo "info: [Restarting oauth pod, waiting...]"
sleep 100
echo "info: [Restarting oauth pod, waiting...]"
sleep 100

echo
# ====================================================

# === Task: Login OCP Cluster ===
#PRINT_TASK "[TASK: Login OCP Cluster]"

#oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443 --insecure-skip-tls-verify &> /dev/null
#run_command "[Log in to the cluster using the htpasswd user]"

#echo
# ====================================================

# === Task: Login cluster information ===
PRINT_TASK "[TASK: Login cluster information]"

echo "info: [Log in to the cluster using the htpasswd user:  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo "info: [Log in to the cluster using kubeconfig:  export KUBECONFIG=$OCP_INSTALL_DIR/auth/kubeconfig]"
echo
# ====================================================
