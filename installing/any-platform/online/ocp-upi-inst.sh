#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Specify the OpenShift release version
export OCP_VERSION="4.16.21"

# Specify required parameters for install-config.yaml
export PULL_SECRET="$HOME/ocp-inst/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export CLUSTER_NAME="ocp"
export BASE_DOMAIN="example.com"
export NETWORK_TYPE="OVNKubernetes"                    # OVNKubernetes or OpenShiftSDN(≤ 4.14)

# Specify the OpenShift node infrastructure configuration
export NODE_DISK_KNAME="/dev/sda"
export NODE_NM_CONN_NAME="'Wired connection 1'" 
export NODE_GATEWAY_IP="10.184.134.1"
export NODE_NET_PREFIX="24"
export NODE_DNS_FORWARDER_IP="10.184.134.1"            # Resolve DNS addresses on the Internet

# Specify OpenShift node’s hostname and ip address
export BASTION_NAME="bastion"
export BOOTSTRAP_NAME="bootstrap"
export MASTER01_NAME="master01"
export MASTER02_NAME="master02"
export MASTER03_NAME="master03"
export WORKER01_NAME="worker01"
export WORKER02_NAME="worker02"
export WORKER03_NAME="worker03"
export BASTION_IP="10.184.134.30"                      # API_VIPS and INGRESS_VIPS
export BOOTSTRAP_IP="10.184.134.136"
export MASTER01_IP="10.184.134.82"
export MASTER02_IP="10.184.134.78"
export MASTER03_IP="10.184.134.114"
export WORKER01_IP="10.184.134.58"
export WORKER02_IP="10.184.134.152"
export WORKER03_IP="10.184.134.150"


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

# Specify a publicly resolvable domain name for testing
export NSLOOKUP_TEST_PUBLIC_DOMAIN="redhat.com"

# Do not change the following parameters
export LOCAL_DNS_IP="$BASTION_IP"
export API_VIPS="$BASTION_IP"
export API_INT_VIPS="$BASTION_IP"
export MCS_VIPS="$BASTION_IP"
export INGRESS_VIPS="$BASTION_IP"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=125  # Adjust this to your desired maximum length
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

# Step 1:
PRINT_TASK "TASK [Configure Environment Variables]"

# Verify pull-secret
cat $PULL_SECRET >/dev/null 2>&1
run_command "Verify existence of $PULL_SECRET file"

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
    check_variable "PULL_SECRET"
    check_variable "NETWORK_TYPE"
    check_variable "POD_CIDR"
    check_variable "HOST_PREFIX"
    check_variable "SERVICE_CIDR"
    check_variable "NODE_GATEWAY_IP"
    check_variable "NODE_NET_PREFIX"
    check_variable "NODE_DNS_FORWARDER_IP"
    check_variable "BASTION_NAME"
    check_variable "BOOTSTRAP_NAME"
    check_variable "MASTER01_NAME"
    check_variable "MASTER02_NAME"
    check_variable "MASTER03_NAME"
    check_variable "WORKER01_NAME"
    check_variable "WORKER02_NAME"
    check_variable "WORKER03_NAME"
    check_variable "BASTION_IP"
    check_variable "MASTER01_IP"
    check_variable "MASTER02_IP"
    check_variable "MASTER03_IP"
    check_variable "WORKER01_IP"
    check_variable "WORKER02_IP"
    check_variable "WORKER03_IP"    
    check_variable "BOOTSTRAP_IP"
    check_variable "NODE_DISK_KNAME"
    check_variable "NODE_NM_CONN_NAME"
    check_variable "NFS_DIR"
    check_variable "IMAGE_REGISTRY_PV"
    check_variable "LOCAL_DNS_IP"
    check_variable "API_INT_VIPS"
    check_variable "API_VIPS"
    check_variable "MCS_VIPS"
    check_variable "INGRESS_VIPS"
    check_variable "NFS_SERVER_IP"
    check_variable "NSLOOKUP_TEST_PUBLIC_DOMAIN"
    check_variable "HTTPD_DIR"
    check_variable "INSTALL_DIR"
    # If all variables are set, display a success message  
}

# Call the function to check all variables
check_all_variables

# Display missing variables, if any
if [ ${#missing_variables[@]} -gt 0 ]; then
    IFS=', '
    echo -e "$FAIL_MSG Missing variables: ${missing_variables[*]}"
    unset IFS
else
    echo -e "$INFO_MSG Confirm all required variables are set"
fi

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Configure Hostname and Time Zone]"

# Change hostname
hostnamectl set-hostname ${BASTION_NAME}
run_command "Set hostname to ${BASTION_NAME}"

# Change time zone to UTC
timedatectl set-timezone UTC
run_command "Set time zone to UTC"

# Write LANG=en_US.UTF-8 to the ~/.bash_profile file
grep -q "^export LANG=en_US.UTF-8" ~/.bash_profile || echo 'export LANG=en_US.UTF-8' >> ~/.bash_profile
run_command "Write LANG=en_US.UTF-8 to ~/.bash_profile"

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
    echo -e "$INFO_MSG Set permanent selinux policy to $permanent_status"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo -e "$INFO_MSG Permanent selinux policy is already $permanent_status"

else
    echo -e "$FAIL_MSG SELinux permanent policy is $permanent_status, expected permissive or disabled"
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
echo -e "$INFO_MSG Downloading RPM packages for installation..."
dnf install -y $package_list >/dev/null 2>&1

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "$INFO_MSG Install $package package"
    else
        echo -e "$FAIL_MSG Install $package package"
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
rm -f /usr/local/bin/oc >/dev/null 2>&1
rm -f /usr/local/bin/kubectl >/dev/null 2>&1
rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -f openshift-install-linux.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux-amd64-rhel8.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux.tar.gz* >/dev/null 2>&1
rm -f /etc/bash_completion.d/oc_completion >/dev/null 2>&1

# Download the openshift-install
echo -e "$INFO_MSG Downloading the openshift-install tool..."

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
echo -e "$INFO_MSG Downloading the openshift-client tool..."

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
        echo -e "$INFO_MSG Set the httpd listening port to 8080"
    else
        echo -e "$INFO_MSG Listening port for httpd is already set to 8080"
    fi
}
# Call the function to update listen port
update_httpd_listen_port

rm -rf /etc/httpd/conf.d/base.conf  >/dev/null 2>&1
# Create a virtual host configuration file
cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName ${BASTION_NAME}
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
    echo -e "$INFO_MSG The nfsnobody user is already present"
else
    useradd nfsnobody
    echo -e "$INFO_MSG Create the nfsnobody user"
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
    echo -e "$INFO_MSG Export configuration for nfs already exists"
else
    echo "$export_config_line" >> "/etc/exports"
    echo -e "$INFO_MSG Setting up nfs export configuration"
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
    forwarders      { ${NODE_DNS_FORWARDER_IP}; };

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
$(printf "%-35s IN  A      %s\n" "api.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_VIPS}")
$(printf "%-35s IN  A      %s\n" "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_INT_VIPS}")
;
; The wildcard also identifies the load balancer.
$(printf "%-35s IN  A      %s\n" "*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}." "${INGRESS_VIPS}")
;
; Create entries for the master hosts.
$(printf "%-35s IN  A      %s\n" "${MASTER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER01_IP}")
$(printf "%-35s IN  A      %s\n" "${MASTER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER02_IP}")
$(printf "%-35s IN  A      %s\n" "${MASTER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER03_IP}")
;
; Create entries for the worker hosts.
$(printf "%-35s IN  A      %s\n" "${WORKER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER01_IP}")
$(printf "%-35s IN  A      %s\n" "${WORKER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER02_IP}")
$(printf "%-35s IN  A      %s\n" "${WORKER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER03_IP}")
;
; Create an entry for the bootstrap host.
$(printf "%-35s IN  A      %s\n" "${BOOTSTRAP_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${BOOTSTRAP_IP}")
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
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$API_VIPS")" "api.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$API_INT_VIPS")" "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}.")
;
; Create entries for the master hosts.
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$MASTER01_IP")" "${MASTER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$MASTER02_IP")" "${MASTER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$MASTER03_IP")" "${MASTER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
;
; Create entries for the worker hosts.
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$WORKER01_IP")" "${WORKER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$WORKER02_IP")" "${WORKER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$WORKER03_IP")" "${WORKER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
;
; Create an entry for the bootstrap host.
$(printf "%-15s IN  PTR      %s\n" "$(get_reverse_ip "$BOOTSTRAP_IP")" "${BOOTSTRAP_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.")
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
    echo -e "$INFO_MSG Prevent NetworkManager from modifying /etc/resolv.conf"
else
    echo -e "$INFO_MSG Prevent NetworkManager from modifying /etc/resolv.conf"
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
    "${MASTER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${BOOTSTRAP_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${API_VIPS}"
    "${MASTER01_IP}"
    "${MASTER02_IP}"
    "${MASTER03_IP}"
    "${WORKER01_IP}"
    "${WORKER02_IP}"
    "${WORKER03_IP}"
    "${BOOTSTRAP_IP}"
    "${NSLOOKUP_TEST_PUBLIC_DOMAIN}"
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
    echo -e "$INFO_MSG Verify DNS resolution with nslookup"
else
    echo -e "$FAIL_MSG DNS resolve failed for the following domain/ip: ${failed_hostnames[*]}"
fi

# Delete old records
export NODE_ANNOTATION="Openshift UPI Node Resolve"

sed -i "/# ${NODE_ANNOTATION}/d;
        /${BOOTSTRAP_NAME}/d;
        /${MASTER01_NAME}/d;
        /${MASTER02_NAME}/d;
        /${MASTER03_NAME}/d;
        /${WORKER01_NAME}/d;
        /${WORKER02_NAME}/d;
        /${WORKER03_NAME}/d" /etc/hosts

# OpenShift Node Hostname Resolve
{
  echo "# ${NODE_ANNOTATION}"
  printf "%-15s %s\n" "${BOOTSTRAP_IP}"    "${BOOTSTRAP_NAME}"
  printf "%-15s %s\n" "${MASTER01_IP}"     "${MASTER01_NAME}"
  printf "%-15s %s\n" "${MASTER02_IP}"     "${MASTER02_NAME}"
  printf "%-15s %s\n" "${MASTER03_IP}"     "${MASTER03_NAME}"
  printf "%-15s %s\n" "${WORKER01_IP}"     "${WORKER01_NAME}"
  printf "%-15s %s\n" "${WORKER02_IP}"     "${WORKER02_NAME}"
  printf "%-15s %s\n" "${WORKER03_IP}"     "${WORKER03_NAME}"
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
  server ${BOOTSTRAP_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2 backup
  server ${MASTER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2
  server ${MASTER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2
  server ${MASTER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:6443 weight 1 verify none check check-ssl inter 10s fall 2 rise 2

listen machine-config-server-22623
  bind ${MCS_VIPS}:22623
  mode tcp
  server ${BOOTSTRAP_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:22623 check inter 1s backup
  server ${MASTER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:22623 check inter 1s
  server ${MASTER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:22623 check inter 1s
  server ${MASTER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:22623 check inter 1s

listen ingress-router-80
  bind ${INGRESS_VIPS}:80
  mode tcp
  balance source
  server ${WORKER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:80 check inter 1s
  server ${WORKER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:80 check inter 1s
  server ${WORKER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:80 check inter 1s
  
listen ingress-router-443
  bind ${INGRESS_VIPS}:443
  mode tcp
  balance source
  server ${WORKER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:443 check inter 1s
  server ${WORKER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:443 check inter 1s
  server ${WORKER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:443 check inter 1s

listen ingress-router-health-check
  mode http
  balance roundrobin
  option httpchk GET /healthz/ready
  option log-health-checks
  http-check expect status 200
  timeout check 5s
  server ${WORKER01_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:1936 check inter 10s fall 2 rise 2
  server ${WORKER02_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:1936 check inter 10s fall 2 rise 2
  server ${WORKER03_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:1936 check inter 10s fall 2 rise 2
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

# Step 10:
PRINT_TASK "TASK [Create Installation Configuration File]"

# Create ssh-key for accessing node
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo -e "$INFO_MSG Create an ssh-key for accessing the node"
else
    echo -e "$INFO_MSG SSH key for accessing the node already exists"
fi

# If known_hosts exists, clear it without error
[ -f "${SSH_KEY_PATH}/known_hosts" ] && > "${SSH_KEY_PATH}/known_hosts" || true

# Define variables
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
pullSecret: '$(cat $PULL_SECRET)'
sshKey: '${SSH_PUB_STR}'
EOF
run_command "Create ${HTTPD_DIR}/install-config.yaml file"

# Add an empty line after the task
echo

# Step 11:
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
  echo -e "$INFO_MSG Disable the master node from scheduling custom pods"
else
  echo -e "$INFO_MSG Disable the master node from scheduling custom pods"
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

# Step 12:
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
        *)  echo -e "$FAIL_MSG Unknown host type for ${HOSTNAME}" ;;
    esac

# Create the setup script for the node
cat << EOF > "${INSTALL_DIR}/${HOSTNAME}"
#!/bin/bash
# Configure network settings
sudo nmcli con mod ${NODE_NM_CONN_NAME} ipv4.addresses ${IP_ADDRESS}/${NODE_NET_PREFIX} ipv4.gateway ${NODE_GATEWAY_IP} ipv4.dns ${LOCAL_DNS_IP} ipv4.method manual connection.autoconnect yes
sudo nmcli con down ${NODE_NM_CONN_NAME}
sudo nmcli con up ${NODE_NM_CONN_NAME}

sudo sleep 10

# Install CoreOS using the appropriate Ignition file
sudo coreos-installer install ${NODE_DISK_KNAME} --insecure-ignition --ignition-url=http://${BASTION_IP}:8080/pre/${IGN_FILE} --firstboot-args 'rd.neednet=1' --copy-network
EOF

    # Check if the setup script was successfully created
    if [ -f "${INSTALL_DIR}/${HOSTNAME}" ]; then
        echo -e "$INFO_MSG Generate setup script: ${INSTALL_DIR}/${HOSTNAME}"
    else
        echo -e "$FAIL_MSG Generate setup script for ${HOSTNAME}"
    fi
}

# Generate setup scripts for each node
generate_setup_script "bs" "${BOOTSTRAP_IP}" # → bs
generate_setup_script "m${MASTER01_NAME: -1}" "${MASTER01_IP}"  # → m1
generate_setup_script "m${MASTER02_NAME: -1}" "${MASTER02_IP}"  # → m2
generate_setup_script "m${MASTER03_NAME: -1}" "${MASTER03_IP}"  # → m3
generate_setup_script "w${WORKER01_NAME: -1}" "${WORKER01_IP}"  # → w1
generate_setup_script "w${WORKER02_NAME: -1}" "${WORKER02_IP}"  # → w2
generate_setup_script "w${WORKER03_NAME: -1}" "${WORKER03_IP}"  # → w3

# Set correct permissions
chmod a+r ${INSTALL_DIR}/*.ign
run_command "Set permissions for ${INSTALL_DIR}/*.ign file"

# Make the script executable
chmod a+rx "${INSTALL_DIR}"/{bs,m*,w*}
run_command "Set permissions on ocp install scripts"

# Add an empty line after the task
echo

# Step 13:
PRINT_TASK "TASK [Generate CSR and Bootstrap/Cluster Monitoring Scripts]"

# Generate approve csr script file]
rm -rf "${INSTALL_DIR}/approve-csr.sh" >/dev/null 2>&1
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

# Generated script to monitor bootstrap readiness
rm -rf ${INSTALL_DIR}/check-bootstrap.sh >/dev/null 2>&1
cat <<EOC > ${INSTALL_DIR}/check-bootstrap.sh
#!/bin/bash
MAX_RETRIES=300              # Maximum number of retries
SLEEP_INTERVAL=3             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
CONTAINER="cluster-bootstrap"
PORTS="6443|22623"

# Step 1: Wait for the bootstrap container to be running
for i in \$(seq 1 \$MAX_RETRIES); do
    # Display spinner while waiting
    printf "\r$INFO_MSG Checking container '%s'... %s" "\$CONTAINER" "\${SPINNER[\$((i % 4))]}"
    # Check container status via SSH and podman
    CONTAINER_STATUS=\$(ssh \$ssh_opts core@$BOOTSTRAP_IP sudo podman ps --filter "name=\$CONTAINER" --format "{{.Status}}" 2>/dev/null | tr -d '\r\n')
    # If container is running, print success message and break
    if [[ "\$CONTAINER_STATUS" == Up* ]]; then
        printf "\r$INFO_MSG Container '%s' is Running%*s\n" "\$CONTAINER" \$((LINE_WIDTH - \${#CONTAINER} - 20)) ""
        break
    fi
    # If max retries reached, print failure and exit
    if [[ \$i -eq \$MAX_RETRIES ]]; then
        printf "\r$FAIL_MSG Container '%s' is Not Running%*s\n" "\$CONTAINER" \$((LINE_WIDTH - \${#CONTAINER} - 25)) ""
        exit 1
    fi

    sleep \$SLEEP_INTERVAL
done

# Step 2: Wait for required ports (6443 and 22623) to be listening
for i in \$(seq 1 \$MAX_RETRIES); do
    # Display spinner while waiting
    printf "\r$INFO_MSG Checking ports 6443 and 22623... %s" "\${SPINNER[\$((i % 4))]}"
    # Check port status via SSH and netstat
    PORT_STATUS=\$(ssh \$ssh_opts core@$BOOTSTRAP_IP sudo netstat -ntplu 2>/dev/null | tr -d '\r\n')
    # If ports are listening, print success message and break
    if echo "\$PORT_STATUS" | grep -qE "\$PORTS"; then
        printf "\r$INFO_MSG Ports 6443 and 22623 are now listening%*s\n" \$((LINE_WIDTH - 35)) ""
        break
    fi
    # If max retries reached, print failure and exit
    if [[ \$i -eq \$MAX_RETRIES ]]; then
        printf "\r$FAIL_MSG Ports 6443 and 22623 are not ready%*s\n" \$((LINE_WIDTH - 30)) ""
        exit 1
    fi

    sleep \$SLEEP_INTERVAL
done

# Step 3: Final message indicating bootstrap is ready
printf "$INFO_MSG You can now install Control Plane & Worker nodes%*s\n" \$((LINE_WIDTH - 50)) ""
EOC
run_command "Generated script to monitor bootstrap readiness: ${INSTALL_DIR}/check-bootstrap.sh"

# Make it executable
chmod +x ${INSTALL_DIR}/check-bootstrap.sh

# Generated script to monitor cluster readiness
rm -rf ${INSTALL_DIR}/check-cluster.sh >/dev/null 2>&1
cat <<EOF > ${INSTALL_DIR}/check-cluster.sh
#!/bin/bash
# Wait for all cluster nodes to be Ready
NODES=("$MASTER01_NAME" "$MASTER02_NAME" "$MASTER03_NAME" "$WORKER01_NAME" "$WORKER02_NAME" "$WORKER03_NAME")
MAX_RETRIES=1800             # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

# Main loop: wait until all nodes are Ready or timeout
while true; do
    NOT_READY_NODES=() # Array to hold nodes that are not Ready yet
    # Check each node's Ready status
    for NODE in "\${NODES[@]}"; do
        FULLNAME="\${NODE}.${CLUSTER_NAME}.${BASE_DOMAIN}"
        STATUS=\$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get node "\$FULLNAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        # If node is not Ready, add it to the list
        if [[ "\$STATUS" != "True" ]]; then
            NOT_READY_NODES+=("\$FULLNAME")
        fi
    done
    # If all nodes are Ready, print success message and exit loop
    if [ \${#NOT_READY_NODES[@]} -eq 0 ]; then
        if \$progress_started; then
            # Overwrite spinner line and print success message
            printf "\r$INFO_MSG All Cluster Nodes are Ready%*s\n" \$((LINE_WIDTH - 18)) ""
        else
            echo -e "$INFO_MSG All Cluster Nodes are Ready"
        fi
        break
    else
        # Spinner logic to show progress while waiting
        CHAR=\${SPINNER[\$((retry_count % 4))]}
        if ! \$progress_started; then
            printf "$INFO_MSG Waiting for all Cluster Nodes to be Ready... %s" "\$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG Waiting for all Cluster Nodes to be Ready... %s" "\$CHAR"
        fi
        # Sleep between retries and increment retry counter
        sleep "\$SLEEP_INTERVAL"
        retry_count=\$((retry_count + 1))
        # Timeout handling: exit if max retries exceeded
        if [[ \$retry_count -ge \$MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG Cluster Nodes not Ready%*s\n" \$((LINE_WIDTH - 17)) ""
            exit 1
        fi
    fi
done

# Wait for all MachineConfigPools (MCPs) to be Ready
MAX_RETRIES=1800             # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get MCP statuses: Ready, Updated, Degraded
    output=\$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get mcp --no-headers 2>/dev/null | awk '{print \$3, \$4, \$5}')
    # If any MCP is not Ready/Updated/Degraded as expected
    if echo "\$output" | grep -q -v "True False False"; then
        CHAR=\${SPINNER[\$((retry_count % 4))]}
        if ! \$progress_started; then
            printf "$INFO_MSG Waiting for all MachineConfigPools to be Ready... %s" "\$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG Waiting for all MachineConfigPools to be Ready... %s" "\$CHAR"
        fi

        sleep "\$SLEEP_INTERVAL"
        retry_count=\$((retry_count + 1))
        # Timeout handling
        if [[ \$retry_count -ge \$MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG MachineConfigPools not Ready%*s\n" \$((LINE_WIDTH - 20)) ""
            exit 1
        fi
    else
        # All MCPs are Ready    
        if \$progress_started; then
            printf "\r$INFO_MSG All MachineConfigPools are Ready%*s\n" \$((LINE_WIDTH - 18)) ""
        else
            printf "$INFO_MSG All MachineConfigPools are Ready%*s\n" \$((LINE_WIDTH - 18)) ""
        fi
        break
    fi
done

# Wait for all Cluster Operators (COs) to be Ready
MAX_RETRIES=1800             # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get Cluster Operator statuses: Available, Progressing, Degraded
    output=\$(/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get co --no-headers 2>/dev/null | awk '{print \$3, \$4, \$5}')
    # If any CO is not Available/Progressing/Degraded as expected
    if echo "\$output" | grep -q -v "True False False"; then
        CHAR=\${SPINNER[\$((retry_count % 4))]}
        if ! \$progress_started; then
            printf "$INFO_MSG Waiting for all Cluster Operators to be Ready... %s" "\$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG Waiting for all Cluster Operators to be Ready... %s" "\$CHAR"
        fi

        sleep "\$SLEEP_INTERVAL"
        retry_count=\$((retry_count + 1))
        # Timeout handling
        if [[ \$retry_count -ge \$MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG Cluster Operators not Ready%*s\n" \$((LINE_WIDTH - 31)) ""
            exit 1
        fi
    else
        # All Cluster Operators are Ready    
        if \$progress_started; then
            printf "\r$INFO_MSG All Cluster Operators are Ready%*s\n" \$((LINE_WIDTH - 32)) ""
        else
            printf "$INFO_MSG All Cluster Operators are Ready%*s\n" \$((LINE_WIDTH - 32)) ""
        fi
        break
    fi
done
EOF
run_command "Generated script to monitor cluster readiness: ${INSTALL_DIR}/check-cluster.sh"

# Make it executable
chmod +x ${INSTALL_DIR}/check-cluster.sh

# Add an empty line after the task
echo

# Step 14:
PRINT_TASK "TASK [Booting From RHCOS ISO and Installing OCP]"

# Set column width
COL_WIDTH=35
printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$BOOTSTRAP_NAME node installation steps:" "Boot RHCOS ISO → curl -s http://$BASTION_IP:8080/pre/bs | sh → reboot"

printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$BASTION_NAME check bootstrap status:" "bash ${INSTALL_DIR}/check-bootstrap.sh"

printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$MASTER01_NAME node installation steps:" "Boot RHCOS ISO → curl -s http://$BASTION_IP:8080/pre/m${MASTER01_NAME: -1} | sh → reboot"
printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$MASTER02_NAME node installation steps:" "Boot RHCOS ISO → curl -s http://$BASTION_IP:8080/pre/m${MASTER02_NAME: -1} | sh → reboot"
printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$MASTER03_NAME node installation steps:" "Boot RHCOS ISO → curl -s http://$BASTION_IP:8080/pre/m${MASTER03_NAME: -1} | sh → reboot"

printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$WORKER01_NAME node installation steps:" "Boot RHCOS ISO → curl -s http://$BASTION_IP:8080/pre/w${WORKER01_NAME: -1} | sh → reboot"
printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$WORKER02_NAME node installation steps:" "Boot RHCOS ISO → curl -s http://$BASTION_IP:8080/pre/w${WORKER02_NAME: -1} | sh → reboot"
printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$WORKER03_NAME node installation steps:" "Boot RHCOS ISO → curl -s http://$BASTION_IP:8080/pre/w${WORKER03_NAME: -1} | sh → reboot"

printf "$ACTION_MSG %-*s → %s\n" $COL_WIDTH "$BASTION_NAME check installation status:" "bash ${INSTALL_DIR}/check-cluster.sh"

# Add an empty line after the task
echo

# Step 15:
PRINT_TASK "TASK [Kubeconfig Setup and OCP Login Guide]"

# Load shell environment
grep -q "^export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" ~/.bashrc || echo "export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" >> ~/.bashrc
run_command "Loading Kubeconfig and completion: source ~/.bashrc && source /etc/bash_completion.d/oc_completion"

echo -e "$INFO_MSG HTPasswd login: unset KUBECONFIG && oc login -u admin -p redhat https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"

# Add an empty line after the task
echo
