#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export OCP_VERSION=4.14.50                              # Only supports installation of version 4.14+
export PULL_SECRET_PATH="$HOME/ocp-inst/pull-secret"    # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export INSTALL_DIR="$HOME/ocp-inst/ocp"
export CLUSTER_NAME="copan"
export BASE_DOMAIN="ocp.test"
export VCENTER_USERNAME="xxxxx"
export VCENTER_PASSWORD="xxxxx"
export API_VIPS="10.184.134.15"
export INGRESS_VIPS="10.184.134.16"
export MACHINE_NETWORK_CIDR="10.184.134.0/24"
export CONTROL_PLANE_IPS=("10.184.134.202" "10.184.134.203" "10.184.134.204")
export COMPUTE_IPS=("10.184.134.132" "10.184.134.134" "10.184.134.135")     # Enter the IP according to the number of working nodes
export BOOTSTRAP_IP="10.184.134.97"
export GATEWAY="10.184.134.1"
export NAMESERVER="10.184.134.128"
export NETMASK="24"

export WORKER_CPU_COUNT="10"
export WORKER_MEMORY_MB="32768"
export WORKER_DISK_SIZE="100"
export MASTER_CPU_COUNT="4"
export MASTER_MEMORY_MB="16384"
export MASTER_DISK_SIZEE="100"

export NETWORK_TYPE="OVNKubernetes"
export SSH_KEY_PATH="$HOME/.ssh"
export VCENTER="vcenter.cee.ibmc.devcluster.openshift.com"
export DATACENTERS="ceedatacenter"
export COMPUTE_CLUSTER="/ceedatacenter/host/ceecluster"
export DATASTORE="/ceedatacenter/datastore/vsanDatastore"
export RESOURCE_POOL="/ceedatacenter/host/ceecluster/Resources"
export VM_NETWORKS="cee-vlan-1167"

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
PRINT_TASK "TASK [Trust the vCenter certificate]"

# delete credentials
sudo rm -rf /etc/pki/ca-trust/source/anchors/vcenter.crt >/dev/null 2>&1 || true
sudo rm -rf download.zip
sudo rm -rf vc_certs

wget --no-check-certificate https://vcenter.cee.ibmc.devcluster.openshift.com/certs/download.zip >/dev/null 2>&1
run_command "[download vCenter certificate]"

unzip download.zip -d vc_certs >/dev/null 2>&1
run_command "[unzip the certificate]"

for f in vc_certs/certs/lin/*.0; do mv -i "$f" "${f%.0}.crt"; done
run_command "[changing the certificate format]"

sudo cp vc_certs/certs/lin/*.crt /etc/pki/ca-trust/source/anchors/vcenter.crt >/dev/null 2>&1
run_command "[copy the certificate to /etc/pki/ca-trust/source/anchors/vcenter.crt]"

sudo update-ca-trust extract >/dev/null 2>&1
run_command "[trust vCenter certificate]"

sudo rm -rf download.zip
sudo rm -rf vc_certs

# Add an empty line after the task
echo


# Step 2:
PRINT_TASK "TASK [Install openshift-install and openshift-client tools]"

# Delete the old version of oc cli
sudo rm -f /usr/local/bin/oc >/dev/null 2>&1
sudo rm -f /usr/local/bin/kube* >/dev/null 2>&1
sudo rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1
sudo rm -f openshift-install-linux.tar.gz* >/dev/null 2>&1
sudo rm -f openshift-client-linux-amd64-rhel8.tar.gz* >/dev/null 2>&1
sudo rm -f openshift-client-linux.tar.gz* >/dev/null 2>&1

# Download the openshift-install
echo "info: [downloading openshift-install tool]"

wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" >/dev/null 2>&1
run_command "[download openshift-install tool]"

sudo tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "[install openshift-install tool]"

sudo chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
run_command "[modify /usr/local/bin/openshift-install permissions]"

sudo rm -rf openshift-install-linux.tar.gz >/dev/null 2>&1

# Get the RHEL version number
rhel_version=$(rpm -E %{rhel})
run_command "[check RHEL version]"

# Determine the download URL based on the RHEL version
if [ "$rhel_version" -eq 8 ]; then
    download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-amd64-rhel8.tar.gz"
    openshift_client="openshift-client-linux-amd64-rhel8.tar.gz"
elif [ "$rhel_version" -eq 9 ]; then
    download_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
    openshift_client="openshift-client-linux.tar.gz"
fi

# Download the OpenShift client
echo "info: [downloading openshift-client tool]"

wget -q "$download_url" -O "$openshift_client"
run_command "[download openshift-client tool]"

# Extract the downloaded tarball to /usr/local/bin/
sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "[install openshift-client tool]"

sudo chmod +x /usr/local/bin/oc >/dev/null 2>&1
run_command "[modify /usr/local/bin/oc permissions]"

sudo chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
run_command "[modify /usr/local/bin/kubectl permissions]"

sudo rm -f /usr/local/bin/README.md >/dev/null 2>&1
sudo rm -rf $openshift_client >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Create openshift cluster]"

# Delete old records
export API_OAUTH_ANNOTATION="Openshift vSphere-IPI API and OAUTH URL Resolve"
sudo sed -i "/# ${API_OAUTH_ANNOTATION}/d; /api.$CLUSTER_NAME.$BASE_DOMAIN/d; /oauth-openshift.apps.$CLUSTER_NAME.$BASE_DOMAIN/d" /etc/hosts

# OpenShift Node Hostname Resolve
{
  echo "# ${API_OAUTH_ANNOTATION}"
  printf "%-15s %s\n" "$API_VIPS"         "api.$CLUSTER_NAME.$BASE_DOMAIN"
  printf "%-15s %s\n" "$INGRESS_VIPS"     "oauth-openshift.apps.$CLUSTER_NAME.$BASE_DOMAIN"
} | sudo tee -a /etc/hosts >/dev/null
run_command "[add api and oauth entry to /etc/hosts file]"

# Check if the SSH key exists
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo "ok: [create ssh-key for accessing coreos]"
else
    echo "info: [ssh key already exists, skip generation]"
fi

sudo rm -rf $INSTALL_DIR >/dev/null 2>&1 || true
mkdir -p $INSTALL_DIR >/dev/null 2>&1
run_command "[create install dir: $INSTALL_DIR]"

# Extract the major and minor version numbers
MAIN_MINOR_VERSION=$(echo "$OCP_VERSION" | awk -F. '{print $1"."$2}')

# Determine whether featureSet needs to be added
if [[ "$MAIN_MINOR_VERSION" == "4.14" || "$MAIN_MINOR_VERSION" == "4.15" ]]; then
  FEATURE_SET_LINE="featureSet: TechPreviewNoUpgrade"
else
  FEATURE_SET_LINE=""
fi

cat << EOF > $INSTALL_DIR/install-config.yaml
$FEATURE_SET_LINE
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    vsphere:
      cpus: $WORKER_CPU_COUNT
      corePerSocket: 1
      memoryMB: $WORKER_MEMORY_MB
      osDisk:
        diskSizeGB: $WORKER_DISK_SIZE
  replicas: ${#COMPUTE_IPS[@]}
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    vsphere:
      cpus: $MASTER_CPU_COUNT
      corePerSocket: 1
      memoryMB: $MASTER_MEMORY_MB
      osDisk:
        diskSizeGB: $MASTER_DISK_SIZE
  replicas: ${#CONTROL_PLANE_IPS[@]}
metadata:
  creationTimestamp: null
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: "$MACHINE_NETWORK_CIDR"
  networkType: $NETWORK_TYPE
  serviceNetwork:
  - 172.30.0.0/16
platform:
  vsphere:
    apiVIPs:
    - $API_VIPS
    ingressVIPs:
    - $INGRESS_VIPS
    hosts:
    - role: bootstrap
      networkDevice:
        ipAddrs:
        - ${BOOTSTRAP_IP}/${NETMASK}
        gateway: ${GATEWAY}
        nameservers:
        - ${NAMESERVER}
EOF
run_command "[create initial $INSTALL_DIR/install-config.yaml]"

# Append control-plane nodes
for ip in "${CONTROL_PLANE_IPS[@]}"; do
cat << EOF >> $INSTALL_DIR/install-config.yaml
    - role: control-plane
      networkDevice:
        ipAddrs:
        - ${ip}/${NETMASK}
        gateway: ${GATEWAY}
        nameservers:
        - ${NAMESERVER}
EOF
done
run_command "[append control-plane nodes $INSTALL_DIR/install-config.yaml]"
# Append compute nodes
for ip in "${COMPUTE_IPS[@]}"; do
cat << EOF >> $INSTALL_DIR/install-config.yaml
    - role: compute
      networkDevice:
        ipAddrs:
        - ${ip}/${NETMASK}
        gateway: ${GATEWAY}
        nameservers:
        - ${NAMESERVER}
EOF
done
run_command "[append compute nodes $INSTALL_DIR/install-config.yaml]"

# Append compute nodes
cat << EOF >> $INSTALL_DIR/install-config.yaml
    failureDomains:
    - name: generated-failure-domain
      region: generated-region
      server: $VCENTER
      topology:
        computeCluster: $COMPUTE_CLUSTER
        datacenter: $DATACENTERS
        datastore: $DATASTORE
        networks:
        - $VM_NETWORKS
        resourcePool: $RESOURCE_POOL
      zone: generated-zone
    vcenters:
    - datacenters:
      - ceedatacenter
      password: "$VCENTER_PASSWORD"
      port: 443
      server: $VCENTER
      user: "$VCENTER_USERNAME"
publish: External
pullSecret: '$(cat $PULL_SECRET_PATH)'
sshKey: |
  $(cat $SSH_KEY_PATH/id_rsa.pub)
EOF
run_command "[append remaining configuration $INSTALL_DIR/install-config.yaml]"

echo "ok: [installing the OpenShift cluster]"

export PATH="/usr/local/bin:$PATH"

# /usr/local/bin/openshift-install create cluster --dir "$INSTALL_DIR" --log-level=info
run_command "[install OpenShift VMware IPI completed]"

# Check cluster operator status
MAX_RETRIES=60
SLEEP_INTERVAL=15
progress_started=false
retry_count=0

while true; do
    # Get the status of all cluster operators
    output=$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get co --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    
    # Check cluster operators status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, cluster operator may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
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
PRINT_TASK "TASK [Set up kubeconfig for automatic login and create an htpasswd user]"

# kubeconfig login:
rm -rf ${INSTALL_DIR}/auth/kubeconfigbk >/dev/null 2>&1
cp ${INSTALL_DIR}/auth/kubeconfig ${INSTALL_DIR}/auth/kubeconfigbk >/dev/null 2>&1
grep -q "^export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" ~/.bash_profile || echo "export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" >> ~/.bash_profile
run_command "[add kubeconfig to ~/.bash_profile]"

# completion command:
sudo bash -c '/usr/local/bin/oc completion bash >> /etc/bash_completion.d/oc_completion' || true
run_command "[add oc_completion]"

rm -rf $INSTALL_DIR/users.htpasswd
echo 'admin:$2y$05$.9uG3eMC1vrnhLIj8.v.POcGpFEN/STrpOw7yGQ5dnMmLbrKVVCmu' > $INSTALL_DIR/users.htpasswd
run_command "[create a user using the htpasswd tool]"

sleep 10

/usr/local/bin/oc --kubeconfig=$INSTALL_DIR/auth/kubeconfig delete secret htpasswd-secret -n openshift-config >/dev/null 2>&1 || true
/usr/local/bin/oc --kubeconfig=$INSTALL_DIR/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$INSTALL_DIR/users.htpasswd -n openshift-config >/dev/null 2>&1
run_command "[create a secret using the users.htpasswd file]"

rm -rf $INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
cat  <<EOF | /usr/local/bin/oc --kubeconfig=$INSTALL_DIR/auth/kubeconfig apply -f - > /dev/null 2>&1
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

sleep 15

# Wait for OpenShift authentication pods to be in 'Running' state
export AUTH_NAMESPACE="openshift-authentication"
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0

while true; do
    # Get the status of all pods
    output=$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get po -n "$AUTH_NAMESPACE" --no-headers 2>/dev/null | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, oauth pods may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all oauth pods are in 'running' state]"
        break
    fi
done

# Grant the 'cluster-admin' cluster role to the user 'admin'
/usr/local/bin/oc --kubeconfig=$INSTALL_DIR/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin >/dev/null 2>&1 || true
run_command "[grant cluster-admin permissions to the admin user]"

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Checking the openshift cluster status]"

# Check cluster operator status
MAX_RETRIES=60
SLEEP_INTERVAL=15
progress_started=false
retry_count=0

while true; do
    # Get the status of all cluster operators
    output=$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get co --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    
    # Check cluster operators status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, cluster operator may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
MAX_RETRIES=60
SLEEP_INTERVAL=15
progress_started=false
retry_count=0

while true; do
    # Get the status of all mcp
    output=$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get mcp --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    
    # Check mcp status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for all mcps to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, mcp may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all mcp have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Add node entry to /etc/hosts file]"

# Delete all master and worker node entries matching the cluster name from /etc/hosts
export NODE_ANNOTATION="Openshift vSphere-IPI Node Resolve"
sudo sed -i "/# ${NODE_ANNOTATION}/d; /${CLUSTER_NAME}-.*-master-.*$/d; /${CLUSTER_NAME}-.*-worker-.*$/d" /etc/hosts
run_command "[delete the entry with the same host name as the node in /etc/hosts]"

# Generate the latest IP→hostname mappings and append them to /etc/hosts
{
  echo "# ${NODE_ANNOTATION}"
  /usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get node -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="ExternalIP")].address}{" "}{.metadata.name}{"\n"}{end}' \
    | while read -r IP NAME; do
        [[ -z "$IP" ]] && continue
        printf "%-15s %s\n" "$IP" "$NAME"
      done
} | sudo tee -a /etc/hosts >/dev/null
run_command "[generate the latest IP and hostname mappings and append them to /etc/hosts]"

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Login openshift cluster information]"

echo "info: [log in to the cluster using the htpasswd user:  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo "info: [log in to the cluster using kubeconfig:  export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig]"

# Add an empty line after the task
echo
