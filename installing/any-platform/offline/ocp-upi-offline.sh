#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
# set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Specify the OpenShift release version
export OCP_VERSION="4.16.21"

# Specify required parameters for install-config.yaml
export PULL_SECRET_FILE="$HOME/ocp-inst/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export CLUSTER_NAME="ocp"
export BASE_DOMAIN="example.com"
export NETWORK_TYPE="OVNKubernetes"                    # OVNKubernetes or OpenShiftSDN(≤ 4.14)

# Specify the OpenShift node’s installation disk and network manager connection name
export COREOS_INSTALL_DEV="/dev/sda"
export NET_IF_NAME="'Wired connection 1'" 

# Specify the OpenShift node infrastructure network configuration
export GATEWAY_IP="10.184.134.1"
export NETMASK="24"
export DNS_FORWARDER_IP="10.184.134.1"                 # Resolve DNS addresses on the Internet

# Specify OpenShift node’s hostname and ip address
export BASTION_HOSTNAME="bastion"
export BOOTSTRAP_HOSTNAME="bootstrap"
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"
export WORKER03_HOSTNAME="worker03"
export BASTION_IP="10.184.134.77"
export BOOTSTRAP_IP="10.184.134.94"
export MASTER01_IP="10.184.134.81"
export MASTER02_IP="10.184.134.145"
export MASTER03_IP="10.184.134.185"
export WORKER01_IP="10.184.134.229"
export WORKER02_IP="10.184.134.91"
export WORKER03_IP="10.184.134.217"

# Specify required parameters for the Mirror Registry
export REGISTRY_HOSTNAME="mirror.registry"
export REGISTRY_ID="admin"
export REGISTRY_PW="password"                         # 8 characters or more
export REGISTRY_INSTALL_DIR="/opt/quay-install"
export REGISTRY_IP="$BASTION_IP"

# More options — no changes required!
# Specify required parameters for install-config.yaml
export SSH_KEY_PATH="$HOME/.ssh"
export POD_CIDR="10.128.0.0/14"
export HOST_PREFIX="23"
export SERVICE_CIDR="172.30.0.0/16"

# Specify the NFS directory to use for the image-registry pod PV
export NFS_SERVER_IP="$BASTION_IP"
export NFS_DIR="/nfs"
export IMAGE_REGISTRY_PV="image-registry-storage"

# Specify the HTTPD path to serve the Ignition file for download
export HTTPD_DIR="/var/www/html/materials"
export INSTALL_DIR="${HTTPD_DIR}/pre"

# Specify the ImageSetConfiguration file path
export IMAGE_SET_CONF_PATH="${HTTPD_DIR}/oc-mirror"
export OCP_RELEASE_CHANNEL="$(echo $OCP_VERSION | cut -d. -f1,2)"

# Do not change the following parameters
export LOCAL_DNS_IP="$BASTION_IP"
export API_VIPS="$BASTION_IP"
export INGRESS_VIPS="$BASTION_IP"
export MCS_VIPS="$API_VIPS"
export API_IP="$API_VIPS"
export API_INT_IP="$API_VIPS"
export APPS_IP="$INGRESS_VIPS"

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
PRINT_TASK "TASK [Configure Environment Variables]"

cat $PULL_SECRET_FILE >/dev/null 2>&1
run_command "Verify existence of $PULL_SECRET_FILE file"

# Define variables
missing_variables=()

# Define a function to check if a variable is set
check_variable() {
    if [ -z "${!1}" ]; then
        missing_variables+=("$1")
    fi
}

# Check all variables that need validation
check_all_variables() {
    check_variable "OCP_VERSION"
    check_variable "CLUSTER_NAME"
    check_variable "BASE_DOMAIN"
    check_variable "SSH_KEY_PATH"
    check_variable "PULL_SECRET_FILE"
    check_variable "NETWORK_TYPE"
    check_variable "POD_CIDR"
    check_variable "HOST_PREFIX"
    check_variable "SERVICE_CIDR"
    check_variable "GATEWAY_IP"
    check_variable "NETMASK"
    check_variable "DNS_FORWARDER_IP"
    check_variable "BASTION_HOSTNAME"
    check_variable "BOOTSTRAP_HOSTNAME"
    check_variable "MASTER01_HOSTNAME"
    check_variable "MASTER02_HOSTNAME"
    check_variable "MASTER03_HOSTNAME"
    check_variable "WORKER01_HOSTNAME"
    check_variable "WORKER02_HOSTNAME"
    check_variable "WORKER03_HOSTNAME"
    check_variable "BASTION_IP"
    check_variable "MASTER01_IP"
    check_variable "MASTER02_IP"
    check_variable "MASTER03_IP"
    check_variable "WORKER01_IP"
    check_variable "WORKER02_IP"
    check_variable "WORKER03_IP"    
    check_variable "BOOTSTRAP_IP"
    check_variable "COREOS_INSTALL_DEV"
    check_variable "NET_IF_NAME"
    check_variable "REGISTRY_HOSTNAME"
    check_variable "REGISTRY_ID"
    check_variable "REGISTRY_PW"
    check_variable "REGISTRY_INSTALL_DIR"
    check_variable "IMAGE_SET_CONF_PATH"
    check_variable "OCP_RELEASE_CHANNEL"
    check_variable "NFS_DIR"
    check_variable "IMAGE_REGISTRY_PV"
    check_variable "LOCAL_DNS_IP"
    check_variable "REGISTRY_IP"
    check_variable "API_IP"
    check_variable "API_INT_IP"
    check_variable "APPS_IP"
    check_variable "API_VIPS"
    check_variable "MCS_VIPS"
    check_variable "INGRESS_VIPS"
    check_variable "NFS_SERVER_IP"
    check_variable "HTTPD_DIR"
    check_variable "INSTALL_DIR"
    # If all variables are set, display a success message  
}

# Call the function to check all variables
check_all_variables

# Display missing variables, if any
if [ ${#missing_variables[@]} -gt 0 ]; then
    IFS=', '
    echo -e "\e[31mFAILED\e[0m Missing variables: ${missing_variables[*]}"
    unset IFS
else
    echo -e "\e[96mINFO\e[0m Confirm all required variables are set"
fi

# Add an empty line after the task
echo

# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Step 2:
PRINT_TASK "TASK [Configure Hostname and Time Zone]"

# Change hostname
hostnamectl set-hostname ${BASTION_HOSTNAME}
run_command "Set hostname to ${BASTION_HOSTNAME}"

# Change time zone to UTC
timedatectl set-timezone UTC
run_command "Set time zone to UTC"

# Write LANG=en_US.UTF-8 to the $HOME/bash_profile file]
grep -q "^export LANG=en_US.UTF-8" ~/.bash_profile || echo 'export LANG=en_US.UTF-8' >> ~/.bash_profile
run_command "Write LANG=en_US.UTF-8 to $HOME/.bash_profile"

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Disable Firewalld Service and Update SELinux Policy]"

# Stop and disable firewalld services
systemctl disable --now firewalld >/dev/null 2>&1
run_command "Stop and disable firewalld service"

# Read the SELinux configuration
permanent_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
# Check if the permanent status is Enforcing
if [[ $permanent_status == "enforcing" ]]; then
    # Change SELinux to permissive
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    permanent_status="permissive"
    echo -e "\e[96mINFO\e[0m Set permanent selinux policy to $permanent_status"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo -e "\e[96mINFO\e[0m Permanent selinux policy is already $permanent_status"

else
    echo -e "\e[31mFAILED\e[0m SELinux permanent policy is $permanent_status, expected permissive or disabled"
fi

# Temporarily set SELinux security policy to permissive
setenforce 0 >/dev/null 2>&1 || true
run_command "Disable temporary selinux enforcement"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Install Required RPM Packages]"

# List of RPM packages to install
packages=("podman" "bind-utils" "bind" "httpd" "httpd-tools" "haproxy" "nfs-utils" "wget" "skopeo" "jq" "bash-completion" "vim-enhanced")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
echo -e "\e[96mINFO\e[0m Downloading RPM packages for installation..."
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

# Update openssh and openssh-clients
dnf update openssh openssh-clients -y >/dev/null 2>&1
run_command "Update openssh and openssh-clients package"

# Update ontainer-tools and crun
dnf update container-tools crun -y >/dev/null 2>&1
run_command "Update container-tools package"

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Install OpenShift Install and Client Tools]"

# Delete the old version of oc cli
rm -f /usr/local/bin/oc* >/dev/null 2>&1
rm -f /usr/local/bin/kubectl >/dev/null 2>&1
rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -f openshift-install-linux.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux-amd64-rhel8.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux.tar.gz* >/dev/null 2>&1
rm -f /etc/bash_completion.d/oc_completion >/dev/null 2>&1
rm -f oc-mirror.tar.gz* >/dev/null 2>&1

# Download the openshift-install
echo -e "\e[96mINFO\e[0m Downloading the openshift-install tool..."

wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" >/dev/null 2>&1
run_command "Download openshift-install tool"

tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "Install openshift-install tool"

chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
run_command "Set permissions for /usr/local/bin/openshift-install"

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
echo -e "\e[96mINFO\e[0m Downloading the openshift-client tool..."

wget -q "$download_url" -O "$openshift_client"
run_command "Download openshift-client tool"

# Extract the downloaded tarball to /usr/local/bin/
tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "Install openshift-client tool"

chmod +x /usr/local/bin/oc >/dev/null 2>&1
run_command "Set permissions for /usr/local/bin/oc"

chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
run_command "Set permissions for /usr/local/bin/kubectl"

rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -rf $openshift_client >/dev/null 2>&1

# completion command:
bash -c '/usr/local/bin/oc completion bash >> /etc/bash_completion.d/oc_completion' || true
run_command "Enable oc bash completion"

# Download the oc-mirror tool
echo -e "\e[96mINFO\e[0m Downloading the oc-mirror tool..."

# Get the RHEL version number
rhel_version=$(rpm -E %{rhel})
if [ "$rhel_version" -eq 8 ]; then
    download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.14.35/oc-mirror.tar.gz"
    oc_mirror="oc-mirror.tar.gz"
elif [ "$rhel_version" -eq 9 ]; then
    download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"
    oc_mirror="oc-mirror.tar.gz"
fi

wget -q "$download_url" -O "$oc_mirror"
run_command "Download oc-mirror tool"

# Install oc-mirror  tool
tar -xzf "$oc_mirror" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "Install oc-mirror tool"

chmod a+x /usr/local/bin/oc-mirror >/dev/null 2>&1
run_command "Set permissions for /usr/local/bin/oc-mirror"

rm -rf $oc_mirror >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Configure and Verify HTTPD Service]"

# Update httpd listen port
update_httpd_listen_port() {
    # Get the current listen port from httpd.conf
    listen_port=$(grep -v "#" /etc/httpd/conf/httpd.conf | grep -i 'Listen' | awk '{print $2}')
    
    # Check if listen port is not 8080
    if [ "$listen_port" != "8080" ]; then
        # Change listen port to 8080
        sed -i 's/^Listen .*/Listen 8080/' /etc/httpd/conf/httpd.conf
        echo -e "\e[96mINFO\e[0m Set the httpd listening port to 8080"
    else
        echo -e "\e[96mINFO\e[0m Listening port for httpd is already set to 8080"
    fi
}
# Call the function to update listen port
update_httpd_listen_port

rm -rf /etc/httpd/conf.d/base.conf  >/dev/null 2>&1
# Create a virtual host configuration file
cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName ${BASTION_HOSTNAME}
   DocumentRoot ${HTTPD_DIR}
</VirtualHost>
EOF
run_command "Create virtual host configuration"

# Create http directory
rm -rf ${HTTPD_DIR} >/dev/null 2>&1
sleep 1
mkdir -p ${HTTPD_DIR} >/dev/null 2>&1
run_command "Create ${HTTPD_DIR} directory"

# Enable and start service
systemctl enable httpd >/dev/null 2>&1
run_command "Enable httpd service at boot"

systemctl restart httpd >/dev/null 2>&1
run_command "Restart httpd service"

# Test httpd configuration
rm -rf ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
sleep 1
touch ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
run_command "Create a test file to verify httpd download functionality"

wget -q http://${BASTION_IP}:8080/httpd-test
run_command "Verify httpd download functionality"

rm -rf httpd-test ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
run_command "Remove the httpd test file"

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Configure and Verify NFS Service]"

# Add nfsnobody user if not exists
if id "nfsnobody" >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m The nfsnobody user is already present"
else
    useradd nfsnobody
    echo -e "\e[96mINFO\e[0m Create the nfsnobody user"
fi

# Create NFS directories
rm -rf ${NFS_DIR} >/dev/null 2>&1
sleep 1
mkdir -p ${NFS_DIR}/${IMAGE_REGISTRY_PV} >/dev/null 2>&1
run_command "Create nfs directory"

chmod -R 777 ${NFS_DIR} >/dev/null 2>&1
run_command "Set permissions of nfs directory"

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_DIR} >/dev/null 2>&1
run_command "Set ownership of nfs directory"

# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo -e "\e[96mINFO\e[0m Export configuration for nfs already exists"
else
    echo "$export_config_line" >> "/etc/exports"
    echo -e "\e[96mINFO\e[0m Setting up nfs export configuration"
fi

# Enable and start service
systemctl enable nfs-server >/dev/null 2>&1
run_command "Enable nfs server service at boot"

systemctl restart nfs-server >/dev/null 2>&1
run_command "Restart nfs server service"

# Wait for the service to restart
sleep 3

# Create the mount point
umount /tmp/nfs-test >/dev/null 2>&1 || true
rm -rf /tmp/nfs-test >/dev/null 2>&1
sleep 1
mkdir -p /tmp/nfs-test >/dev/null 2>&1
run_command "Create test mount directory: /tmp/nfs-test"

# Attempt to mount the NFS share
mount -t nfs ${NFS_SERVER_IP}:${NFS_DIR} /tmp/nfs-test >/dev/null 2>&1
run_command "Mount nfs shared directory for testing: /tmp/nfs-test"

# Wait mount the NFS share
sleep 3

# Unmount the NFS share
fuser -km /tmp/nfs-test >/dev/null 2>&1 || true
umount /tmp/nfs-test >/dev/null 2>&1 || true
run_command "Unmount nfs shared directory: /tmp/nfs-test"

# Delete /tmp/nfs-test
rm -rf /tmp/nfs-test >/dev/null 2>&1
run_command "Remove test mount directory: /tmp/nfs-test"

# Add an empty line after the task
echo

# Step 8:
PRINT_TASK "TASK [Configure and Verify Named Service]"

# Construct forward DNS zone name and zone file name
FORWARD_ZONE_NAME="${BASE_DOMAIN}"
FORWARD_ZONE_FILE="${BASE_DOMAIN}.zone"

# Generate reverse DNS zone name and reverse zone file name 
IFS='.' read -ra octets <<< "$LOCAL_DNS_IP"
OCTET0="${octets[0]}"
OCTET1="${octets[1]}"
REVERSE_ZONE_NAME="${OCTET1}.${OCTET0}.in-addr.arpa"
REVERSE_ZONE_FILE="${OCTET1}.${OCTET0}.zone"

# Generate named service configuration file
cat << EOF > /etc/named.conf
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { ::1; };
    directory       "/var/named";
    dump-file       "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file   "/var/named/data/named.secroots";
    recursing-file  "/var/named/data/named.recursing";
    allow-query     { any; };
    forwarders      { ${DNS_FORWARDER_IP}; };

    recursion yes;
    dnssec-validation yes;
    managed-keys-directory "/var/named/dynamic";
    pid-file "/run/named/named.pid";
    session-keyfile "/run/named/session.key";
};

zone "${FORWARD_ZONE_NAME}" IN {
    type master;
    file "${FORWARD_ZONE_FILE}";
    allow-query { any; };
};

zone "${REVERSE_ZONE_NAME}" IN {
    type master;
    file "${REVERSE_ZONE_FILE}";
    allow-query { any; };
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

include "/etc/named.rfc1912.zones";
EOF
run_command "Generate named configuration file"

# Create Forward Zone file
rm -f /var/named/${FORWARD_ZONE_FILE}  >/dev/null 2>&1

cat << EOF > "/var/named/${FORWARD_ZONE_FILE}"
\$TTL 1W
@       IN      SOA     ns1.${BASE_DOMAIN}.        root (
                        201907070      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.${BASE_DOMAIN}.
;
;
ns1     IN      A       ${LOCAL_DNS_IP}
;
; The api identifies the IP of load balancer.
$(printf "%-35s IN  A      %s\n" "api.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_IP}")
$(printf "%-35s IN  A      %s\n" "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_INT_IP}")
;
; The wildcard also identifies the load balancer.
$(printf "%-35s IN  A      %s\n" "*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}." "${APPS_IP}")
;
; Create entries for the master hosts.
$(printf "%-35s IN  A      %s\n" "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER01_IP}")
$(printf "%-35s IN  A      %s\n" "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER02_IP}")
$(printf "%-35s IN  A      %s\n" "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER03_IP}")
;
; Create entries for the worker hosts.
$(printf "%-35s IN  A      %s\n" "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER01_IP}")
$(printf "%-35s IN  A      %s\n" "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER02_IP}")
$(printf "%-35s IN  A      %s\n" "${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER03_IP}")
;
; Create an entry for the bootstrap host.
$(printf "%-35s IN  A      %s\n" "${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${BOOTSTRAP_IP}")
;
; Create entries for the mirror registry hosts.
$(printf "%-40s IN  A      %s\n" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}." "${REGISTRY_IP}")
EOF
run_command "Generate forward DNS zone file: /var/named/${FORWARD_ZONE_FILE}"

# Create Reverse Zone file
get_reverse_ip() {
  local ip=$1
  IFS='.' read -r a b c d <<< "$ip"
  echo "${d}.${c}"
}

rm -f /var/named/${REVERSE_ZONE_FILE} >/dev/null 2>&1

cat << EOF > "/var/named/${REVERSE_ZONE_FILE}"
\$TTL 1W
@       IN      SOA     ns1.${BASE_DOMAIN}.        root (
                        2019070700      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.${BASE_DOMAIN}.
;
; The syntax is "last two octets" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of load balancer.
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$API_IP")" "api.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$API_INT_IP")" "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}.")
;
; Create entries for the master hosts.
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$MASTER01_IP")" "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$MASTER02_IP")" "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$MASTER03_IP")" "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
;
; Create entries for the worker hosts.
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$WORKER01_IP")" "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$WORKER02_IP")" "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$WORKER03_IP")" "${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
;
; Create an entry for the bootstrap host.
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$BOOTSTRAP_IP")" "${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
EOF
run_command "Generate reverse DNS zone file: /var/named/${REVERSE_ZONE_FILE}"

# Check named configuration file
named-checkconf >/dev/null 2>&1
run_command "Validate named configuration"

# Check forward zone file
named-checkzone ${FORWARD_ZONE_FILE} /var/named/${FORWARD_ZONE_FILE} >/dev/null 2>&1
run_command "Validate forward zone file"

# Check reverse zone file
named-checkzone ${REVERSE_ZONE_FILE} /var/named/${REVERSE_ZONE_FILE} >/dev/null 2>&1
run_command "Validate reverse zone file"

# Change ownership
chown named. /var/named/*.zone
run_command "Set ownership of /var/named zone files"

# Enable and start service
systemctl enable named >/dev/null 2>&1
run_command "Enable named service at boot"

systemctl restart named >/dev/null 2>&1
run_command "Restart named service"

# Add dns ip to resolv.conf
sed -i "/${LOCAL_DNS_IP}/d" /etc/resolv.conf
sed -i "1s/^/nameserver ${LOCAL_DNS_IP}\n/" /etc/resolv.conf
run_command "Add DNS IP $LOCAL_DNS_IP to /etc/resolv.conf"

# Append “dns=none” immediately below the “[main]” section in the main NM config
if ! sed -n '/^\[main\]/,/^\[/{/dns=none/p}' /etc/NetworkManager/NetworkManager.conf | grep -q 'dns=none'; then
    sed -i '/^\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
    echo -e "\e[96mINFO\e[0m Prevent NetworkManager from modifying /etc/resolv.conf"
else
    echo -e "\e[96mINFO\e[0m Prevent NetworkManager from modifying /etc/resolv.conf"
fi

# Restart service
systemctl restart NetworkManager >/dev/null 2>&1
run_command "Restart the network manager service"

# Wait for the service to restart
sleep 3

# List of hostnames and IP addresses to check
hostnames=(
    "api.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${API_IP}"
    "${MASTER01_IP}"
    "${MASTER02_IP}"
    "${MASTER03_IP}"
    "${WORKER01_IP}"
    "${WORKER02_IP}"
    "${WORKER03_IP}"
    "${BOOTSTRAP_IP}"
)

# Loop through hostnames and perform nslookup
all_successful=true
failed_hostnames=()

for hostname in "${hostnames[@]}"; do
    nslookup_result=$(nslookup "$hostname" 2>&1)
    if [ $? -ne 0 ]; then
        all_successful=false
        failed_hostnames+=("$hostname")
    fi
done

# Display results
if [ "$all_successful" = true ]; then
    echo -e "\e[96mINFO\e[0m Verify DNS resolution with nslookup"
else
    echo -e "\e[31mFAILED\e[0m DNS resolve failed for the following domain/ip: ${failed_hostnames[*]}"
fi

# Delete old records
export NODE_ANNOTATION="Openshift UPI Node Resolve"

sed -i "/# ${NODE_ANNOTATION}/d;
        /${BOOTSTRAP_HOSTNAME}/d;
        /${MASTER01_HOSTNAME}/d;
        /${MASTER02_HOSTNAME}/d;
        /${MASTER03_HOSTNAME}/d;
        /${WORKER01_HOSTNAME}/d;
        /${WORKER02_HOSTNAME}/d;
        /${WORKER03_HOSTNAME}/d" /etc/hosts

# OpenShift Node Hostname Resolve
{
  echo "# ${NODE_ANNOTATION}"
  printf "%-15s %s\n" "${BOOTSTRAP_IP}"    "${BOOTSTRAP_HOSTNAME}"
  printf "%-15s %s\n" "${MASTER01_IP}"     "${MASTER01_HOSTNAME}"
  printf "%-15s %s\n" "${MASTER02_IP}"     "${MASTER02_HOSTNAME}"
  printf "%-15s %s\n" "${MASTER03_IP}"     "${MASTER03_HOSTNAME}"
  printf "%-15s %s\n" "${WORKER01_IP}"     "${WORKER01_HOSTNAME}"
  printf "%-15s %s\n" "${WORKER02_IP}"     "${WORKER02_HOSTNAME}"
  printf "%-15s %s\n" "${WORKER03_IP}"     "${WORKER03_HOSTNAME}"
} | tee -a /etc/hosts >/dev/null
run_command "Update /etc/hosts with hostname and IP"

# Add an empty line after the task
echo

# Step 9:
PRINT_TASK "TASK [Configure and Verify HAProxy Service]"

# Setup haproxy services configuration
# https://access.redhat.com/solutions/4677531
cat << EOF > /etc/haproxy/haproxy.cfg 
global
  log         127.0.0.1 local2
  pidfile     /var/run/haproxy.pid
  maxconn     4000
  daemon

defaults
  mode                    http
  log                     global
  option                  dontlognull
  option http-server-close
  option                  redispatch
  retries                 3
  timeout http-request    10s
  timeout queue           1m
  timeout connect         10s
  timeout client          1m
  timeout server          1m
  timeout http-keep-alive 10s
  timeout check           10s
  maxconn                 3000

frontend stats
  bind *:1936
  mode            http
  log             global
  maxconn 10
  stats enable
  stats hide-version
  stats refresh 30s
  stats show-node
  stats show-desc Stats for ocp4 cluster
  stats auth admin:passwd
  stats uri /stats

listen kube-apiserver-6443
  bind ${API_VIPS}:6443
  mode tcp
  balance roundrobin
  option  httpchk GET /readyz HTTP/1.0
  option  log-health-checks
  timeout check 10s
  server ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2 backup
  server ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2
  server ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2
  server ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2

listen machine-config-server-22623
  bind ${MCS_VIPS}:22623
  mode tcp
  server ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:22623 check inter 1s backup
  server ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:22623 check inter 1s
  server ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:22623 check inter 1s
  server ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:22623 check inter 1s

listen ingress-router-80
  bind ${INGRESS_VIPS}:80
  mode tcp
  balance source
  server ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:80 check inter 1s
  server ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:80 check inter 1s
  server ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:80 check inter 1s
  
listen ingress-router-443
  bind ${INGRESS_VIPS}:443
  mode tcp
  balance source
  server ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:443 check inter 1s
  server ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:443 check inter 1s
  server ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:443 check inter 1s

listen ingress-router-health-check
  mode http
  balance roundrobin
  option httpchk GET /healthz/ready
  option log-health-checks
  http-check expect status 200
  timeout check 5s
  server ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:1936 check inter 10s fall 2 rise 2
  server ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:1936 check inter 10s fall 2 rise 2
  server ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:1936 check inter 10s fall 2 rise 2
EOF
run_command "Generate haproxy configuration file"

# Path to HAProxy configuration file
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1
run_command "Validate haproxy configuration"

# Enable and start service
systemctl enable --now haproxy >/dev/null 2>&1
run_command "Enable haproxy service at boot"

systemctl restart haproxy >/dev/null 2>&1
run_command "Restart haproxy service"

# Configure HAProxy logs to be written to /var/log/haproxy.log
#rm -rf /etc/rsyslog.d/haproxy.conf
#cat <<EOF >/etc/rsyslog.d/haproxy.conf
#local2.*    /var/log/haproxy.log
#EOF
#run_command "Generate /etc/rsyslog.d/haproxy.conf configuration file"

#rm -rf /etc/rsyslog.conf
#cat << EOF > /etc/rsyslog.conf
## rsyslog configuration file
#
## For more information see /usr/share/doc/rsyslog-*/rsyslog_conf.html
## or latest version online at http://www.rsyslog.com/doc/rsyslog_conf.html 
## If you experience problems, see http://www.rsyslog.com/doc/troubleshoot.html
#
##### GLOBAL DIRECTIVES ####
#
## Where to place auxiliary files
#global(workDirectory="/var/lib/rsyslog")
#
## Use default timestamp format
#module(load="builtin:omfile" Template="RSYSLOG_TraditionalFileFormat")
#
##### MODULES ####
#
#module(load="imuxsock"    # provides support for local system logging (e.g. via logger command)
#       SysSock.Use="off") # Turn off message reception via local log socket; 
#                          # local messages are retrieved through imjournal now.
#module(load="imjournal"             # provides access to the systemd journal
#       UsePid="system" # PID nummber is retrieved as the ID of the process the journal entry originates from
#       StateFile="imjournal.state") # File to store the position in the journal
##module(load="imklog") # reads kernel messages (the same are read from journald)
##module(load="immark") # provides --MARK-- message capability
#
## Include all config files in /etc/rsyslog.d/
#include(file="/etc/rsyslog.d/*.conf" mode="optional")
#
## Provides UDP syslog reception
## for parameters see http://www.rsyslog.com/doc/imudp.html
#module(load="imudp") # needs to be done just once
#input(type="imudp" port="514")
#
## Provides TCP syslog reception
## for parameters see http://www.rsyslog.com/doc/imtcp.html
##module(load="imtcp") # needs to be done just once
##input(type="imtcp" port="514")
#
##### RULES ####
#
## Log all kernel messages to the console.
## Logging much else clutters up the screen.
##kern.*                                                 /dev/console
#
## Log anything (except mail) of level info or higher.
## Don't log private authentication messages!
#*.info;mail.none;authpriv.none;cron.none                /var/log/messages
#
## The authpriv file has restricted access.
#authpriv.*                                              /var/log/secure
#
## Log all the mail messages in one place.
#mail.*                                                  -/var/log/maillog
#
#
## Log cron stuff
#cron.*                                                  /var/log/cron
#
## Everybody gets emergency messages
##*.emerg                                                 :omusrmsg:*
#
## Save news errors of level crit and higher in a special file.
#uucp,news.crit                                          /var/log/spooler
#
## Save boot messages also to boot.log
#local7.*                                                /var/log/boot.log
#
#
## ### sample forwarding rule ###
##action(type="omfwd"  
## # An on-disk queue is created for this action. If the remote host is
## # down, messages are spooled to disk and sent when it is up again.
##queue.filename="fwdRule1"       # unique name prefix for spool files
##queue.maxdiskspace="1g"         # 1gb space limit (use as much as possible)
##queue.saveonshutdown="on"       # save messages to disk on shutdown
##queue.type="LinkedList"         # run asynchronously
##action.resumeRetryCount="-1"    # infinite retries if host is down
## # Remote Logging (we use TCP for reliable delivery)
## # remote_host is: name/ip, e.g. 192.168.0.1, port optional e.g. 10514
##Target="remote_host" Port="XXX" Protocol="tcp")
#EOF
#run_command "Generate rsyslog configuration to write HAProxy logs to /var/log/haproxy.log"

# Enable and start service
#systemctl enable --now rsyslog >/dev/null 2>&1
#run_command "Enable rsyslog service at boot"

#systemctl restart rsyslog
#run_command "Restart rsyslog service"

# Add an empty line after the task
echo


# Offline settings
# Step 10: 
PRINT_TASK "TASK [Install Mirror Registry]"

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
rm -rf /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem >/dev/null 2>&1 || true
rm -rf "${REGISTRY_INSTALL_DIR}" >/dev/null 2>&1 || true

# Create installation directory
mkdir -p ${REGISTRY_INSTALL_DIR}
mkdir -p ${REGISTRY_INSTALL_DIR}/quay-storage
mkdir -p ${REGISTRY_INSTALL_DIR}/sqlite-storage
run_command "Create registry installation directory: ${INSTALL_DIR}"

chmod -R 777 ${REGISTRY_INSTALL_DIR}
run_command "Set permissions of ${REGISTRY_INSTALL_DIR} directory"

# Download mirror registry
echo -e "\e[96mINFO\e[0m Downloading the mirror registry package"

wget -O ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz >/dev/null 2>&1
run_command "Download mirror registry package"

# Extract the downloaded mirror registry package
tar xvf ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_DIR}/ >/dev/null 2>&1
run_command "Extract the mirror registry package"

echo -e "\e[96mINFO\e[0m Installing the mirror registry..."
# Install mirror registry
${REGISTRY_INSTALL_DIR}/mirror-registry install \
     --quayHostname ${REGISTRY_HOSTNAME}.${BASE_DOMAIN} \
     --quayRoot ${REGISTRY_INSTALL_DIR} \
     --quayStorage ${REGISTRY_INSTALL_DIR}/quay-storage \
     --sqliteStorage ${REGISTRY_INSTALL_DIR}/sqlite-storage \
     --initUser ${REGISTRY_ID} \
     --initPassword ${REGISTRY_PW}
run_command "Installed mirror registry"

# Copy the rootCA certificate to the trusted source
cp ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem
run_command "Copy rootCA certificate to trusted anchors"

# Trust the rootCA certificate
update-ca-trust >/dev/null 2>&1
run_command "Trust the rootCA certificate"

rm -rf pause.tar quay.tar redis.tar >/dev/null 2>&1 || true

sleep 5

# Login to the registry
rm -rf $XDG_RUNTIME_DIR/containers >/dev/null 2>&1 || true
mkdir -p $XDG_RUNTIME_DIR/containers >/dev/null 2>&1 || true
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" >/dev/null 2>&1
run_command "Login registry https://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443"

# Add an empty line after the task
echo

# Step 11:
PRINT_TASK "TASK [Create Installation Configuration File]"

# Backup and format the registry CA certificate
rm -rf "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak"
cp "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem" "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak"
run_command "Backup registry rootCA certificate"

sed -i 's/^/  /' "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak"
run_command "Format registry rootCA certificate"

# Create ssh-key for accessing node
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo -e "\e[96mINFO\e[0m Create an ssh-key for accessing the node"
else
    echo -e "\e[96mINFO\e[0m SSH key for accessing the node already exists"
fi

# If known_hosts exists, clear it without error
[ -f "${SSH_KEY_PATH}/known_hosts" ] && > "${SSH_KEY_PATH}/known_hosts" || true

# Define variables
export REGISTRY_CA_CERT_FORMAT="$(cat ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak)"
export REGISTRY_AUTH=$(echo -n "${REGISTRY_ID}:${REGISTRY_PW}" | base64)
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Generate a defined install-config file
rm -rf ${HTTPD_DIR}/install-config.yaml >/dev/null 2>&1
sleep 1
cat << EOF > ${HTTPD_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 0 
controlPlane: 
  hyperthreading: Enabled 
  name: master
  replicas: 3 
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: ${POD_CIDR}
    hostPrefix: ${HOST_PREFIX}
  networkType: ${NETWORK_TYPE}
  serviceNetwork: 
  - ${SERVICE_CIDR}
platform:
  none: {} 
fips: false
pullSecret: '{"auths":{"${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443": {"auth": "${REGISTRY_AUTH}","email": "xxx@xxx.com"}}}' 
sshKey: '${SSH_PUB_STR}'
additionalTrustBundle: | 
${REGISTRY_CA_CERT_FORMAT}
imageContentSources:
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- mirrors:
  - ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
EOF
run_command "Create ${HTTPD_DIR}/install-config.yaml file"

# Add an empty line after the task
echo

# Step 12:
PRINT_TASK "TASK [Creating the Kubernetes Manifest and Ignition Config Files]"

# Create installation directory
rm -rf "${INSTALL_DIR}" >/dev/null 2>&1
sleep 1
mkdir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "Create installation directory: ${INSTALL_DIR}"

# Copy install-config.yaml to installation directory
cp "${HTTPD_DIR}/install-config.yaml" "${INSTALL_DIR}"
run_command "Copy install-config.yaml to installation directory"

# Generate manifests
/usr/local/bin/openshift-install create manifests --dir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "Generate kubernetes manifests"

# Check if the file contains "mastersSchedulable: true"
if grep -q "mastersSchedulable: true" "${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml"; then
  # Replace "mastersSchedulable: true" with "mastersSchedulable: false"
  sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml"
  echo -e "\e[96mINFO\e[0m Disable the master node from scheduling custom pods"
else
  echo -e "\e[96mINFO\e[0m Disable the master node from scheduling custom pods"
fi

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

cat << EOF > ${INSTALL_DIR}/manifests/custom-image-registry-persistentvolume.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${IMAGE_REGISTRY_PV}
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: ${NFS_DIR}/${IMAGE_REGISTRY_PV}
    server: ${NFS_SERVER_IP}
  persistentVolumeReclaimPolicy: Retain
EOF
run_command "Create image registry persistentvolume manifests"

cat << EOF > ${INSTALL_DIR}/manifests/custom-cluster-configs.imageregistry.yaml
apiVersion: imageregistry.operator.openshift.io/v1
kind: Config
metadata:
  name: cluster
spec:
  logLevel: Normal
  managementState: Managed
  observedConfig: null
  operatorLogLevel: Normal
  proxy: {}
  replicas: 1
  requests:
    read:
      maxWaitInQueue: 0s
    write:
      maxWaitInQueue: 0s
  rolloutStrategy: RollingUpdate
  storage:
    managementState: Managed
    pvc:
      claim: 
  unsupportedConfigOverrides: null
EOF
run_command "Create imageregistry config manifests"

# Generate and modify ignition configuration files
/usr/local/bin/openshift-install create ignition-configs --dir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "Create the ignition configuration files"

# Add an empty line after the task
echo

# Step 13:
PRINT_TASK "TASK [Generate OCP Install Script File]"

# Function to generate setup script for a node
generate_setup_script() {
    local HOSTNAME=$1
    local IP_ADDRESS=$2
    local IGN_FILE

    # Determine the ignition file based on the node type
    case "$HOSTNAME" in
        bs) IGN_FILE="bootstrap.ign" ;;
        m*) IGN_FILE="master.ign"    ;;
        w*) IGN_FILE="worker.ign"    ;;
        *)  echo -e "\e[31mFAILED\e[0m Unknown host type for ${HOSTNAME}" ;;
    esac

# Create the setup script for the node
cat << EOF > "${INSTALL_DIR}/${HOSTNAME}"
#!/bin/bash
# Configure network settings
sudo nmcli con mod ${NET_IF_NAME} ipv4.addresses ${IP_ADDRESS}/${NETMASK} ipv4.gateway ${GATEWAY_IP} ipv4.dns ${LOCAL_DNS_IP} ipv4.method manual connection.autoconnect yes
sudo nmcli con down ${NET_IF_NAME}
sudo nmcli con up ${NET_IF_NAME}

sudo sleep 10

# Install CoreOS using the appropriate Ignition file
sudo coreos-installer install ${COREOS_INSTALL_DEV} --insecure-ignition --ignition-url=http://${BASTION_IP}:8080/pre/${IGN_FILE} --firstboot-args 'rd.neednet=1' --copy-network
EOF

    # Check if the setup script was successfully created
    if [ -f "${INSTALL_DIR}/${HOSTNAME}" ]; then
        echo -e "\e[96mINFO\e[0m Generate setup script: ${INSTALL_DIR}/${HOSTNAME}"
    else
        echo -e "\e[31mFAILED\e[0m Generate setup script for ${HOSTNAME}"
    fi
}

# Generate setup scripts for each node
generate_setup_script "bs" "${BOOTSTRAP_IP}" # → bs
generate_setup_script "m${MASTER01_HOSTNAME: -1}" "${MASTER01_IP}"  # → m1
generate_setup_script "m${MASTER02_HOSTNAME: -1}" "${MASTER02_IP}"  # → m2
generate_setup_script "m${MASTER03_HOSTNAME: -1}" "${MASTER03_IP}"  # → m3
generate_setup_script "w${WORKER01_HOSTNAME: -1}" "${WORKER01_IP}"  # → w1
generate_setup_script "w${WORKER02_HOSTNAME: -1}" "${WORKER02_IP}"  # → w2
generate_setup_script "w${WORKER03_HOSTNAME: -1}" "${WORKER03_IP}"  # → w3

# Set correct permissions
chmod a+r ${INSTALL_DIR}/*.ign
run_command "Set permissions for ${INSTALL_DIR}/*.ign file"

# Make the script executable
chmod a+rx "${INSTALL_DIR}"/{bs,m*,w*}
run_command "Set permissions on ocp install scripts"

# Add an empty line after the task
echo

# Step 14:
PRINT_TASK "TASK [Generate scripts for CSR approval and OpenShift image mirroring]"

# If the file exists, delete it
rm -rf "${INSTALL_DIR}/approve-csr.sh" >/dev/null 2>&1

# Generate approve csr script file]
cat << EOF > "${INSTALL_DIR}/ocp4cert-approver.sh"
#!/bin/bash
source 01-set-params.sh >/dev/null 2>&1
export PATH="/usr/local/bin:$PATH"
for i in {1..3600}; do 
  oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | xargs --no-run-if-empty oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig adm certificate approve >/dev/null 2>&1
  sleep 10
done 
EOF
run_command "Generate csr approval script: ${INSTALL_DIR}/ocp4cert-approver.sh"

# Run the CSR auto-approver script
bash ${INSTALL_DIR}/ocp4cert-approver.sh &
run_command "Execute csr auto approval script: ${INSTALL_DIR}/ocp4cert-approver.sh"

# Create script to mirror the OpenShift image
cat << EOF > ${INSTALL_DIR}/mirror-img.sh
#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
# set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line \$LINENO - Command: \$BASH_COMMAND"; exit 1' ERR

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110
    task_title="\$1"
    title_length=\${#task_title}
    stars=\$((max_length - title_length))
    echo "\$task_title\$(printf '*%.0s' \$(seq 1 \$stars))"
}

# Function to check command success and display appropriate message
run_command() {
    local exit_code=\$?
    if [ \$exit_code -eq 0 ]; then
        echo -e "\e[96mINFO\e[0m \$1"
    else
        echo -e "\e[31mFAILED\e[0m \$1"
        exit 1
    fi
}

# Offline settings
# Step 1:
PRINT_TASK "TASK [Mirror OCP Release Images to Mirror Registry]"

# Login to the registry
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "${PULL_SECRET_FILE}" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" >/dev/null 2>&1
run_command "Add authentication information to pull-secret"

# Save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json
cat "${PULL_SECRET_FILE}" | jq . > \$XDG_RUNTIME_DIR/containers/auth.json
run_command "Save pull-secret file to \$XDG_RUNTIME_DIR/containers/auth.json"

# Create ImageSetConfiguration directory
rm -rf ${IMAGE_SET_CONF_PATH} >/dev/null 2>&1
mkdir ${IMAGE_SET_CONF_PATH} >/dev/null 2>&1
run_command "Create ${IMAGE_SET_CONF_PATH} directory"

# Create ImageSetConfiguration file
cat <<YAML_EOF > "${IMAGE_SET_CONF_PATH}/imageset-config.yaml"
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
  registry:
    imageURL: ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443/mirror/metadata
    skipTLS: false
mirror:
  platform:
    channels:
      - name: stable-${OCP_RELEASE_CHANNEL}
        minVersion: ${OCP_VERSION}
        maxVersion: ${OCP_VERSION}
        shortestPath: true
YAML_EOF
run_command "Create ${IMAGE_SET_CONF_PATH}/imageset-config.yaml file"

# Mirroring ocp release image
/usr/local/bin/oc-mirror --config=${IMAGE_SET_CONF_PATH}/imageset-config.yaml docker://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443 --dest-skip-tls

rm -rf oc-mirror-workspace
EOF
run_command "Generate ocp image mirroring script: ${INSTALL_DIR}/mirror-img.sh"

# Add an empty line after the task
echo

# Step 15:
PRINT_TASK "TASK [Kubeconfig Setup and OCP Login Guide]"

# Backup and configure kubeconfig
grep -q "^export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" ~/.bash_profile || echo "export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" >> ~/.bash_profile
run_command "Default login: use kubeconfig"

echo -e "\e[96mINFO\e[0m HTPasswd login: unset KUBECONFIG && oc login -u admin -p redhat https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
echo -e "\e[33mACTION\e[0m Please manually run: source /etc/bash_completion.d/oc_completion && source $HOME/.bash_profile"

# Add an empty line after the task
echo

# Step 16:
PRINT_TASK "TASK [Mirror the OpenShift release image, boot from RHCOS ISO, and install the cluster]"

echo -e "\e[33mACTION\e[0m $BASTION_HOSTNAME mirror release image:       → bash ${INSTALL_DIR}/mirror-img.sh"
echo -e "\e[33mACTION\e[0m $BOOTSTRAP_HOSTNAME node installation steps:  → Boot RHCOS ISO   → curl -s http://$BASTION_IP:8080/pre/bs | sh   → reboot"
echo -e "\e[33mACTION\e[0m $BASTION_HOSTNAME load shell environment:     → source /etc/bash_completion.d/oc_completion && source \$HOME/.bash_profile"
echo -e "\e[33mACTION\e[0m $BASTION_HOSTNAME check bootstrap status:     → bash ${INSTALL_DIR}/bootstrap-check.sh"
echo -e "\e[33mACTION\e[0m $MASTER01_HOSTNAME node installation steps:   → Boot RHCOS ISO   → curl -s http://$BASTION_IP:8080/pre/m${MASTER01_HOSTNAME: -1} | sh   → reboot"
echo -e "\e[33mACTION\e[0m $MASTER02_HOSTNAME node installation steps:   → Boot RHCOS ISO   → curl -s http://$BASTION_IP:8080/pre/m${MASTER02_HOSTNAME: -1} | sh   → reboot"
echo -e "\e[33mACTION\e[0m $MASTER03_HOSTNAME node installation steps:   → Boot RHCOS ISO   → curl -s http://$BASTION_IP:8080/pre/m${MASTER03_HOSTNAME: -1} | sh   → reboot"
echo -e "\e[33mACTION\e[0m $WORKER01_HOSTNAME node installation steps:   → Boot RHCOS ISO   → curl -s http://$BASTION_IP:8080/pre/w${WORKER01_HOSTNAME: -1} | sh   → reboot"
echo -e "\e[33mACTION\e[0m $WORKER02_HOSTNAME node installation steps:   → Boot RHCOS ISO   → curl -s http://$BASTION_IP:8080/pre/w${WORKER02_HOSTNAME: -1} | sh   → reboot"
echo -e "\e[33mACTION\e[0m $WORKER03_HOSTNAME node installation steps:   → Boot RHCOS ISO   → curl -s http://$BASTION_IP:8080/pre/w${WORKER03_HOSTNAME: -1} | sh   → reboot"



# Add an empty line after the task
echo
