#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
# trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR
set -uo pipefail

# Set environment variables
export OCP_VERSION=4.18.20                              # Only supports installation of version 4.14+
export CLUSTER_NAME="copan"
export BASE_DOMAIN="ocp.test"
export VCENTER_USERNAME="xxxxx"
export VCENTER_PASSWORD="xxxxx"
export API_VIPS="10.48.55.150"                          # API VIP (auto-selects an unused IP if unset)
export INGRESS_VIPS="10.48.55.151"                      # Ingress VIP (auto-selects an unused IP if unset)
export MACHINE_NET_CIDR="10.48.55.0/24"                 # Node IP range
export MACHINE_NET_START_IP="100"                       # Start of static IP range, auto-selects unused IPs via ping
export MACHINE_NET_END_IP="230"                         # End of static IP range, auto-selects unused IPs via ping
export MACHINE_NET_GATEWAY="10.48.55.1"
export MACHINE_NET_DNS="10.48.55.125"                   # DNS server that can resolve the vCenter URL
export MACHINE_NET_PREFIX="24"
export VM_NETWORKS="cee-vlan-753"
export PULL_SECRET="$HOME/ocp-inst/pull-secret"         # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export INSTALL_DIR="$HOME/ocp-inst/vsphere/ocp"

export WORKER_REPLICAS="2"
export WORKER_CPU_COUNT="12"                            # Total CPUs, must be a multiple of $WORKER_CORES_PER_SOCKET=4
export WORKER_MEMORY_MB="32768"
export WORKER_DISK_SIZE="100"
export CONTROL_PLANE_CPU_COUNT="4"                      # Total CPUs, must be a multiple of $WORKER_CORES_PER_SOCKET=4
export CONTROL_PLANE_MEMORY_MB="16384"
export CONTROL_PLANE_DISK_SIZE="100"

export WORKER_CORES_PER_SOCKET="4"                      # Cores per VM socket; total CPUs / coresPerSocket = number of sockets
export CONTROL_PLANE_CORES_PER_SOCKET="4"               # Cores per VM socket; total CPUs / coresPerSocket = number of sockets

export NETWORK_TYPE="OVNKubernetes"
export SSH_KEY_PATH="$HOME/.ssh"
export VCENTER="vcenter.cee.ibmc.devcluster.openshift.com"
export DATACENTERS="ceedatacenter"
export COMPUTE_CLUSTER="/ceedatacenter/host/ceecluster"
export DATASTORE="/ceedatacenter/datastore/vsanDatastore"
export RESOURCE_POOL="/ceedatacenter/host/ceecluster/Resources"

# Add user's local bin to PATH
export PATH="$HOME/.local/bin:$PATH"

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
        echo -e "\e[31mFAIL\e[0m $1"
        exit 1
    fi
}

# Define color output variables
INFO_MSG="\e[96mINFO\e[0m"
FAIL_MSG="\e[31mFAIL\e[0m"
ACTION_MSG="\e[33mACTION\e[0m"

# Step 0:
PRINT_TASK "TASK [Automatically find unused IP addresses]"

# Automatically find unused IP addresses and assign them to nodes
# --- 1. Initialize Variables ---
# Convert comma/space separated strings into arrays
API_VIPS=(${API_VIPS:-})
INGRESS_VIPS=(${INGRESS_VIPS:-})
CP=()
WK=()
BOOT=""

# Extract the subnet prefix (e.g., 10.48.55)
ip_prefix=$(echo "$MACHINE_NET_CIDR" | cut -d'.' -f1-3)

# --- 2. Detection Function ---
# Check if an IP is available (Returns 0 if NOT reachable via ping)
is_ip_free() {
    local target_ip=$1
    # -c 1: send 1 packet; -W 1: wait 1 second for response
    if ping -c 1 -W 1 "$target_ip" >/dev/null 2>&1; then
        return 1 # IP is occupied (Ping successful)
    else
        return 0 # IP is free (Ping failed)
    fi
}

# --- 3. Print Initial Status ---
[ ${#API_VIPS[@]} -gt 0 ] && echo -e "$INFO_MSG Preset API VIP: ${API_VIPS[*]}"
[ ${#INGRESS_VIPS[@]} -gt 0 ] && echo -e "$INFO_MSG Preset Ingress VIP: ${INGRESS_VIPS[*]}"

# --- 4. Core Allocation Logic ---
for i in $(seq "$MACHINE_NET_START_IP" "$MACHINE_NET_END_IP"); do
    ip="${ip_prefix}.$i"

    # A. Static Check: Skip if IP is already in the preset VIP lists
    [[ " ${API_VIPS[*]} " == *" $ip "* ]] && continue
    [[ " ${INGRESS_VIPS[*]} " == *" $ip "* ]] && continue

    # B. Dynamic Check: Skip if the IP responds to ping (already active on network)
    if ! is_ip_free "$ip"; then
        continue
    fi

    # C. Sequential Allocation
    # Assign API VIP if none exists
    if [ ${#API_VIPS[@]} -eq 0 ]; then
        API_VIPS+=("$ip")
        echo -e "$INFO_MSG Allocated API_VIP: $ip"
        continue
    fi

    # Assign Ingress VIP if none exists
    if [ ${#INGRESS_VIPS[@]} -eq 0 ]; then
        INGRESS_VIPS+=("$ip")
        echo -e "$INFO_MSG Allocated INGRESS_VIP: $ip"
        continue
    fi

    # Assign 3 IPs for Control Plane
    if [ ${#CP[@]} -lt 3 ]; then
        CP+=("$ip")
        echo -e "$INFO_MSG Allocated Control Plane IP: $ip"
        continue
    fi

    # Assign Worker IPs based on replicas count
    if [ ${#WK[@]} -lt "$WORKER_REPLICAS" ]; then
        WK+=("$ip")
        echo -e "$INFO_MSG Allocated Worker IP: $ip"
        continue
    fi

    # Assign Bootstrap IP (The final required IP)
    if [ -z "$BOOT" ]; then
        BOOT="$ip"
        echo -e "$INFO_MSG Allocated Bootstrap IP: $ip"
        break
    fi
done

# --- 5. Verify Results ---
if [ -z "$BOOT" ]; then
    echo -e "$FAIL_MSG Insufficient IP pool or too many occupied addresses!"
    exit 1
fi

# --- 6. Export Final Variables ---
export CONTROL_PLANE_IPS=("${CP[@]}")
export WORKER_IPS=("${WK[@]}")
export BOOTSTRAP_IP="$BOOT"
export API_VIPS=("${API_VIPS[@]}")
export INGRESS_VIPS=("${INGRESS_VIPS[@]}")

# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Verify pull-secret and trust vCenter certificate]"

# Verify pull-secret
cat $PULL_SECRET >/dev/null 2>&1
run_command "Verify existence of $PULL_SECRET file"

# Verify sudo permission
if sudo -n true 2>/dev/null; then
  echo -e "$INFO_MSG Passwordless sudo permission verified"
else
  echo -e "$FAIL_MSG Passwordless sudo permission is required for this installation"
  exit 1
fi

# delete credentials
sudo rm -rf /etc/pki/ca-trust/source/anchors/vcenter.crt >/dev/null 2>&1 || true
rm -rf download.zip
rm -rf vc_certs

curl -sSLk -o download.zip "https://vcenter.cee.ibmc.devcluster.openshift.com/certs/download.zip" >/dev/null 2>&1
run_command "Download vCenter certificate"

unzip download.zip -d vc_certs >/dev/null 2>&1
run_command "Unzip the certificate"

for f in vc_certs/certs/lin/*.0; do mv -i "$f" "${f%.0}.crt"; done
run_command "Changing the certificate format"

sudo cp vc_certs/certs/lin/*.crt /etc/pki/ca-trust/source/anchors/vcenter.crt >/dev/null 2>&1
run_command "Copy the certificate to /etc/pki/ca-trust/source/anchors/vcenter.crt"

sudo update-ca-trust extract >/dev/null 2>&1
run_command "Trust vCenter certificate"

rm -rf download.zip
rm -rf vc_certs

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Install OpenShift Install and Client Tools]"

# Delete the old version of oc cli
rm -f $HOME/.local/bin/oc >/dev/null 2>&1
rm -f $HOME/.local/bin/kubectl >/dev/null 2>&1
rm -f $HOME/.local/bin/openshift-install >/dev/null 2>&1
rm -f $HOME/.local/bin/README.md >/dev/null 2>&1
rm -f openshift-install-linux.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux-amd64-rhel8.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux.tar.gz* >/dev/null 2>&1

# Create user-local bin directory
mkdir -p $HOME/.local/bin/
run_command "Create $HOME/.local/bin/ directory"

# Download the openshift-install
echo -e "$INFO_MSG Downloading the openshift-install tool..."

curl -sSLk -o openshift-install-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" >/dev/null 2>&1
run_command "Download openshift-install tool"

tar -xzf "openshift-install-linux.tar.gz" -C "$HOME/.local/bin/" >/dev/null 2>&1
run_command "Install openshift-install tool"

chmod +x $HOME/.local/bin/openshift-install >/dev/null 2>&1
run_command "Set permissions for $HOME/.local/bin/openshift-install"

rm -rf openshift-install-linux.tar.gz >/dev/null 2>&1

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
echo -e "$INFO_MSG Downloading the openshift-client tool..."

curl -sSLk -o $openshift_client "$download_url" >/dev/null 2>&1
run_command "Download openshift-client tool"

# Extract the downloaded tarball to $HOME/.local/bin/
tar -xzf "$openshift_client" -C "$HOME/.local/bin/" >/dev/null 2>&1
run_command "Install openshift-client tool"

chmod +x $HOME/.local/bin/oc >/dev/null 2>&1
run_command "Set permissions fo $HOME/.local/bin/oc"

chmod +x $HOME/.local/bin/kubectl >/dev/null 2>&1
run_command "Set permissions fo $HOME/.local/bin/kubectl"

rm -f $HOME/.local/bin/README.md >/dev/null 2>&1
rm -rf $openshift_client >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Create OpenShift Cluster]"

# Delete old records
export API_OAUTH_ANNOTATION="Openshift vSphere-IPI API and OAUTH URL Resolve"
sudo sed -i "/# ${API_OAUTH_ANNOTATION}/d; /api.$CLUSTER_NAME.$BASE_DOMAIN/d; /oauth-openshift.apps.$CLUSTER_NAME.$BASE_DOMAIN/d" /etc/hosts

# OpenShift Node Hostname Resolve
{
  echo "# ${API_OAUTH_ANNOTATION}"
  printf "%-15s %s\n" "$API_VIPS"         "api.$CLUSTER_NAME.$BASE_DOMAIN"
  printf "%-15s %s\n" "$INGRESS_VIPS"     "oauth-openshift.apps.$CLUSTER_NAME.$BASE_DOMAIN"
} | sudo tee -a /etc/hosts >/dev/null
run_command "Add API and OAUTH entry to /etc/hosts file"

# Check if the SSH key exists
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo -e "$INFO_MSG Create ssh-key for accessing node"
else
    echo -e "$INFO_MSG SSH key for accessing the node already exists"
fi

rm -rf $INSTALL_DIR >/dev/null 2>&1 || true
mkdir -p $INSTALL_DIR >/dev/null 2>&1
run_command "Create install dir: $INSTALL_DIR"

# Extract the major and minor version numbers
MAIN_MINOR_VERSION=$(echo "$OCP_VERSION" | awk -F. '{print $1"."$2}')

# Determine whether featureSet needs to be added
if [[ "$MAIN_MINOR_VERSION" == "4.14" || "$MAIN_MINOR_VERSION" == "4.15" ]]; then
  FEATURE_SET_LINE="featureSet: TechPreviewNoUpgrade"
else
  FEATURE_SET_LINE=""
fi

cat << EOF > $INSTALL_DIR/install-config.yaml 2>/dev/null
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
      coresPerSocket: $WORKER_CORES_PER_SOCKET
      memoryMB: $WORKER_MEMORY_MB
      osDisk:
        diskSizeGB: $WORKER_DISK_SIZE
  replicas: ${#WORKER_IPS[@]}
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    vsphere:
      cpus: $CONTROL_PLANE_CPU_COUNT
      coresPerSocket: $CONTROL_PLANE_CORES_PER_SOCKET
      memoryMB: $CONTROL_PLANE_MEMORY_MB
      osDisk:
        diskSizeGB: $CONTROL_PLANE_DISK_SIZE
  replicas: ${#CONTROL_PLANE_IPS[@]}
metadata:
  creationTimestamp: null
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: "$MACHINE_NET_CIDR"
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
        - ${BOOTSTRAP_IP}/${MACHINE_NET_PREFIX}
        gateway: ${MACHINE_NET_GATEWAY}
        nameservers:
        - ${MACHINE_NET_DNS}
EOF
run_command "Create initial $INSTALL_DIR/install-config.yaml"

# Append control-plane nodes
for ip in "${CONTROL_PLANE_IPS[@]}"; do
cat << EOF >> $INSTALL_DIR/install-config.yaml
    - role: control-plane
      networkDevice:
        ipAddrs:
        - ${ip}/${MACHINE_NET_PREFIX}
        gateway: ${MACHINE_NET_GATEWAY}
        nameservers:
        - ${MACHINE_NET_DNS}
EOF
done
run_command "Append control-plane nodes $INSTALL_DIR/install-config.yaml"
# Append compute nodes
for ip in "${WORKER_IPS[@]}"; do
cat << EOF >> $INSTALL_DIR/install-config.yaml
    - role: compute
      networkDevice:
        ipAddrs:
        - ${ip}/${MACHINE_NET_PREFIX}
        gateway: ${MACHINE_NET_GATEWAY}
        nameservers:
        - ${MACHINE_NET_DNS}
EOF
done
run_command "Append compute nodes $INSTALL_DIR/install-config.yaml"

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
pullSecret: '$(cat $PULL_SECRET)'
sshKey: |
  $(cat $SSH_KEY_PATH/id_rsa.pub)
EOF
run_command "Append remaining configuration $INSTALL_DIR/install-config.yaml"

# Generate manifests
openshift-install create manifests --dir "${INSTALL_DIR}" >/dev/null 2>&1
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

openshift-install create cluster --dir "$INSTALL_DIR" --log-level=info
run_command "Installation complete"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Add Node Entry to /etc/hosts File]"

# Delete all master and worker node entries matching the cluster name from /etc/hosts
export NODE_ANNOTATION="Openshift vSphere-IPI Node Resolve"
sudo sed -i "/# ${NODE_ANNOTATION}/d; /${CLUSTER_NAME}-.*-master-.*$/d; /${CLUSTER_NAME}-.*-worker-.*$/d" /etc/hosts
run_command "Remove the entry with the same host name as the node in /etc/hosts"

# Generate the latest IP→hostname mappings and append them to /etc/hosts
{
  echo "# ${NODE_ANNOTATION}"
  oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get node -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="ExternalIP")].address}{" "}{.metadata.name}{"\n"}{end}' \
    | while read -r IP NAME; do
        [[ -z "$IP" ]] && continue
        printf "%-15s %s\n" "$IP" "$NAME"
      done
} | sudo tee -a /etc/hosts >/dev/null
run_command "Generate the latest IP and hostname mappings and append them to /etc/hosts"

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Kubeconfig Setup and OCP Login Guide]"

# Backup and configure kubeconfig
grep -q "^export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" ~/.bashrc || echo "export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" >> ~/.bashrc
run_command "Default login: use kubeconfig"

echo -e "$INFO_MSG HTPasswd login: unset KUBECONFIG && oc login -u admin -p redhat https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
echo -e "$INFO_MSG Please manually run: source ~/.bashrc"

# Add an empty line after the task
echo
