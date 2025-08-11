#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

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
# Applying environment variables
source 01-set-params.sh
export PATH="/usr/local/bin:$PATH"

# Step 2:
PRINT_TASK "TASK [Changing the hostname and time zone]"

# Change hostname
hostnamectl set-hostname ${BASTION_HOSTNAME}
run_command "[change hostname to ${BASTION_HOSTNAME}]"

# Change time zone to UTC
timedatectl set-timezone UTC
run_command "[change time zone to UTC]"

# Write LANG=en_US.UTF-8 to the ./bash_profile file]
grep -q "^export LANG=en_US.UTF-8" ~/.bash_profile || echo 'export LANG=en_US.UTF-8' >> ~/.bash_profile
run_command "[write LANG=en_US.UTF-8 to the ./bash_profile file]"

# Reload ~/.bash_profile
# source ~/.bash_profile >/dev/null 2>&1 || true
# run_command "[reload ~/.bash_profile]"

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Disable and stop firewalld service]"

# Stop and disable firewalld services
systemctl disable --now firewalld >/dev/null 2>&1
run_command "[firewalld service stopped and disabled]"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Change SELinux security policy]"

# Read the SELinux configuration
permanent_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
# Check if the permanent status is Enforcing
if [[ $permanent_status == "enforcing" ]]; then
    # Change SELinux to permissive
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    permanent_status="permissive"
    echo "ok: [selinux permanent security policy changed to $permanent_status]"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo "ok: [selinux permanent security policy is $permanent_status]"
else
    echo "failed: [selinux permanent security policy is $permanent_status (expected permissive or disabled)]"
fi

# Temporarily set SELinux security policy to permissive
setenforce 0 >/dev/null 2>&1 || true
# Check temporary SELinux security policy
temporary_status=$(getenforce)
# Check if temporary SELinux security policy is permissive or disabled
if [[ $temporary_status == "Permissive" || $temporary_status == "Disabled" ]]; then
    echo "ok: [selinux temporary security policy is disabled]"
else
    echo "failed: [selinux temporary security policy is $temporary_status (expected permissive or disabled)]"
fi

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Install the necessary rpm packages]"

# List of RPM packages to install
packages=("podman" "bind-utils" "bind" "haproxy" "nfs-utils" "httpd" "httpd-tools" "wget" "vim-enhanced" "skopeo" "bash-completion" "jq")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
echo "info: [installing required rpm packages]"
dnf install -y $package_list >/dev/null 2>&1

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "ok: [installed $package package]"
    else
        echo "failed: [installed $package package]"
    fi
done

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Install openshift-install and openshift client tools]"

# Delete the old version of oc cli
rm -f /usr/local/bin/oc >/dev/null 2>&1
rm -f /usr/local/bin/kubectl >/dev/null 2>&1
rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -f openshift-install-linux.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux-amd64-rhel8.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux.tar.gz* >/dev/null 2>&1

# Download the openshift-install
echo "info: [downloading openshift-install tool]"

wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz" >/dev/null 2>&1
run_command "[download openshift-install tool]"

tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "[install openshift-install tool]"

chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
run_command "[modify /usr/local/bin/openshift-install permissions]"

rm -rf openshift-install-linux.tar.gz >/dev/null 2>&1

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
tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "[install openshift-client tool]"

chmod +x /usr/local/bin/oc >/dev/null 2>&1
run_command "[modify /usr/local/bin/oc permissions]"

chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
run_command "[modify /usr/local/bin/kubectl permissions]"

rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -rf $openshift_client >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Setup and check httpd services]"

# Update httpd listen port
update_httpd_listen_port() {
    # Get the current listen port from httpd.conf
    listen_port=$(grep -v "#" /etc/httpd/conf/httpd.conf | grep -i 'Listen' | awk '{print $2}')
    
    # Check if listen port is not 8080
    if [ "$listen_port" != "8080" ]; then
        # Change listen port to 8080
        sed -i 's/^Listen .*/Listen 8080/' /etc/httpd/conf/httpd.conf
        echo "ok: [change http listening port to 8080]"
    else
        echo "skipped: [http listen port is already 8080]"
    fi
}

# Call the function to update listen port
update_httpd_listen_port

# Create virtual host configuration
create_virtual_host_config() {
# Create a virtual host configuration file
cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName ${BASTION_HOSTNAME}
   DocumentRoot ${HTTPD_DIR}
</VirtualHost>
EOF
}

# Create virtual host configuration
create_virtual_host_config

# Check if virtual host configuration is valid
check_virtual_host_configuration() {
    # Define expected values for server name and document root
    expected_server_name="${BASTION_HOSTNAME}"
    expected_document_root="${HTTPD_DIR}"
    
    # Path to virtual host configuration file
    virtual_host_config="/etc/httpd/conf.d/base.conf"
    
    # Check if expected values are present in the config
    if grep -q "ServerName $expected_server_name" "$virtual_host_config" && \
       grep -q "DocumentRoot $expected_document_root" "$virtual_host_config"; then
        echo "ok: [create virtual host configuration]"
    else
        echo "failed: [create virtual host configuration]"
    fi
}

# Check virtual host configuration
check_virtual_host_configuration

# Create http dir
rm -rf ${HTTPD_DIR} >/dev/null 2>&1
sleep 1
mkdir -p ${HTTPD_DIR} >/dev/null 2>&1
run_command "[create http: ${HTTPD_DIR} director]"

# Enable and start service
systemctl enable httpd >/dev/null 2>&1
run_command "[set the httpd service to start automatically at boot]"

systemctl restart httpd >/dev/null 2>&1
run_command "[restart httpd service]"

# Wait for the service to restart
sleep 15

# Test httpd configuration
rm -rf httpd-test ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
sleep 1
touch ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
run_command "[create httpd test file]"

wget -q http://${BASTION_IP}:8080/httpd-test
run_command "[test httpd download function]"

rm -rf httpd-test ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
run_command "[delete the httpd test file]"

# Add an empty line after the task
echo

# Step 8:
PRINT_TASK "TASK [Setup nfs services]"

# Create NFS directories
rm -rf ${NFS_DIR} >/dev/null 2>&1
sleep 1
mkdir -p ${NFS_DIR} >/dev/null 2>&1
run_command "[create nfs director: ${NFS_DIR}]"

# Add nfsnobody user if not exists
if id "nfsnobody" >/dev/null 2>&1; then
    echo "skipped: [nfsnobody user exists]"
else
    useradd nfsnobody
    echo "ok: [add nfsnobody user]"
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_DIR} >/dev/null 2>&1
run_command "[changing ownership of an NFS directory]"

chmod -R 777 ${NFS_DIR} >/dev/null 2>&1
run_command "[change NFS directory permissions]"

# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "skipped: [nfs export configuration already exists]"
else
    echo "$export_config_line" >> "/etc/exports"
    echo "ok: [add nfs export configuration]"
fi

# Enable and start service
systemctl enable nfs-server >/dev/null 2>&1
run_command "[set the nfs-server service to start automatically at boot]"

systemctl restart nfs-server >/dev/null 2>&1
run_command "[restart nfs-server service]"

# Wait for the service to restart
sleep 15

# Create the mount point
umount /tmp/nfs-test >/dev/null 2>&1 || true
rm -rf /tmp/nfs-test >/dev/null 2>&1
sleep 1
mkdir -p /tmp/nfs-test >/dev/null 2>&1
run_command "[create an nfs mount directory for testing: /tmp/nfs-test]"

# Attempt to mount the NFS share
mount -t nfs ${NFS_SERVER_IP}:${NFS_DIR} /tmp/nfs-test >/dev/null 2>&1
run_command "[test mounts the nfs shared directory: /tmp/nfs-test]"

# Wait mount the NFS share
sleep 10

# Unmount the NFS share
fuser -km /tmp/nfs-test >/dev/null 2>&1 || true
umount /tmp/nfs-test >/dev/null 2>&1 || true
run_command "[unmount the nfs shared directory: /tmp/nfs-test]"

# Delete /tmp/nfs-test
rm -rf /tmp/nfs-test >/dev/null 2>&1
run_command "[delete the test mounted nfs directory: /tmp/nfs-test]"

# Add an empty line after the task
echo

# Step 9:
PRINT_TASK "TASK [Setup named services]"

# Construct forward DNS zone name and zone file name
FORWARD_ZONE_NAME="${BASE_DOMAIN}"
FORWARD_ZONE_FILE="${BASE_DOMAIN}.zone"

# Generate reverse DNS zone name and reverse zone file name 
# Extract the last two octets from the IP address
IFS='.' read -ra octets <<< "$LOCAL_DNS_IP"
OCTET0="${octets[0]}"
OCTET1="${octets[1]}"

# Construct reverse DNS zone name and zone file name
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
run_command "[generate named configuration file]"

# Clean up: Delete duplicate file
rm -f /var/named/${FORWARD_ZONE_FILE}

# Create forward zone file
# Function to format and align DNS entries
format_dns_entry() {
    domain="$1"
    ip="$2"
    printf "%-40s IN  A      %s\n" "$domain" "$ip"
}

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
$(format_dns_entry "api.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_IP}")
$(format_dns_entry "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_INT_IP}")
;
; The wildcard also identifies the load balancer.
$(format_dns_entry "*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}." "${APPS_IP}")
;
; Create entries for the master hosts.
$(format_dns_entry "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER01_IP}")
$(format_dns_entry "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER02_IP}")
$(format_dns_entry "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER03_IP}")
;
; Create entries for the worker hosts.
$(format_dns_entry "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER01_IP}")
$(format_dns_entry "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER02_IP}")
$(format_dns_entry "${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER03_IP}")
;
; Create an entry for the bootstrap host.
$(format_dns_entry "${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${BOOTSTRAP_IP}")
EOF
run_command "[generate forward DNS zone file: /var/named/${FORWARD_ZONE_FILE}]"

# Clean up: Delete duplicate file
rm -f /var/named/${REVERSE_ZONE_FILE} >/dev/null 2>&1

# Input file containing the original reverse DNS zone configuration
reverse_zone_input_file="/var/named/reverse_zone_input_file"

# Output file for the formatted reverse DNS zone configuration
reverse_zone_output_file="/var/named/${REVERSE_ZONE_FILE}"

# Create the input file with initial content
cat << EOF > "$reverse_zone_input_file"
\$TTL 1W
@       IN      SOA     ns1.${BASE_DOMAIN}.        root (
                        2019070700      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.${BASE_DOMAIN}.
;
; The syntax is "last octet" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of load balancer.
${API_IP}                IN      PTR     api.${CLUSTER_NAME}.${BASE_DOMAIN}.
${API_INT_IP}            IN      PTR     api-int.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create entries for the master hosts.
${MASTER01_IP}           IN      PTR     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${MASTER02_IP}           IN      PTR     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${MASTER03_IP}           IN      PTR     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create entries for the worker hosts.
${WORKER01_IP}           IN      PTR     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${WORKER02_IP}           IN      PTR     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${WORKER03_IP}           IN      PTR     ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create an entry for the bootstrap host.
${BOOTSTRAP_IP}          IN      PTR     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
EOF

# Function to generate IP address conversion to reverse format
convert_to_reverse_ip() {
    local ip="$1"
    IFS='.' read -ra octets <<< "$ip"
    reverse_ip="${octets[3]}.${octets[2]}"
    echo "$reverse_ip"
}

# Clear output file
> "$reverse_zone_output_file" 

# Use the function "convert_to_reverse_ip" to convert IP addresses, and format the output
while IFS= read -r line; do
    if [[ $line == *PTR* ]]; then
        # Extract IP and PTR from the line
        ip=$(echo "$line" | awk '{print $1}')
        ptr=$(echo "$line" | awk '{print $4}')

        # Convert IP to reverse format
        reversed_ip=$(convert_to_reverse_ip "$ip")

        # Format the output with appropriate spacing
        formatted_line=$(printf "%-19s IN  PTR      %-40s\n" "$reversed_ip" "$ptr")
        echo "$formatted_line" >> "$reverse_zone_output_file"
    else
        # If not a PTR line, keep the line unchanged
        echo "$line" >> "$reverse_zone_output_file"
    fi
done < "$reverse_zone_input_file"

# Clean up: Delete input file
rm -f "$reverse_zone_input_file"

# Verify if the reverse DNS zone file was generated successfully
if [ -f "$reverse_zone_output_file" ]; then
    echo "ok: [generate reverse DNS zone file: $reverse_zone_output_file]"
else
    echo "failed: [generate reverse DNS zone file]"
fi

# Check named configuration file
named-checkconf >/dev/null 2>&1
run_command "[named configuration is valid]"

# Check forward zone file
named-checkzone ${FORWARD_ZONE_FILE} /var/named/${FORWARD_ZONE_FILE} >/dev/null 2>&1
run_command "[forward zone file is valid]"

# Check reverse zone file
named-checkzone ${REVERSE_ZONE_FILE} /var/named/${REVERSE_ZONE_FILE} >/dev/null 2>&1
run_command "[reverse zone file is valid]"

# Change ownership
chown named. /var/named/*.zone
run_command "[change ownership /var/named/*.zone]"

# Enable and start service
systemctl enable named >/dev/null 2>&1
run_command "[set the named service to start automatically at boot]"

systemctl restart named >/dev/null 2>&1
run_command "[restart named service]"

# Add dns ip to resolv.conf
sed -i "/${LOCAL_DNS_IP}/d" /etc/resolv.conf
sed -i "1s/^/nameserver ${LOCAL_DNS_IP}\n/" /etc/resolv.conf
run_command "[add dns ip $LOCAL_DNS_IP to /etc/resolv.conf]"

# Append “dns=none” immediately below the “[main]” section in the main NM config
if ! sed -n '/^\[main\]/,/^\[/{/dns=none/p}' /etc/NetworkManager/NetworkManager.conf | grep -q 'dns=none'; then
    sed -i '/^\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
    echo "ok: [prevent network manager from dynamically updating /etc/resolv.conf]"
else
    echo "skipped: [prevent network manager from dynamically updating /etc/resolv.conf]"
fi

# Restart service
systemctl restart NetworkManager >/dev/null 2>&1
run_command "[restart network manager service]"

# Wait for the service to restart
sleep 15

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
    echo "ok: [nslookup all domain names/ip addresses]"
else
    echo "failed: [dns resolve failed for the following domain/ip: ${failed_hostnames[*]}]"
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
run_command "[add hostname and ip to /etc/hosts]"

# Add an empty line after the task
echo

# Step 10:
PRINT_TASK "TASK [Setup HAproxy services]"

# Setup haproxy services configuration
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

listen api-server-6443 
  bind ${API_VIPS}:6443
  mode tcp
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:6443 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:6443 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:6443 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:6443 check inter 1s

listen machine-config-server-22623 
  bind ${MCS_VIPS}:22623
  mode tcp
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:22623 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:22623 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:22623 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:22623 check inter 1s

listen default-ingress-router-80
  bind ${INGRESS_VIPS}:80
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:80 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:80 check inter 1s
  server     ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:80 check inter 1s
  
listen default-ingress-router-443
  bind ${INGRESS_VIPS}:443
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:443 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:443 check inter 1s
  server     ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:443 check inter 1s
EOF
run_command "[generate haproxy configuration file]"

# Path to HAProxy configuration file
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1
run_command "[haproxy configuration is valid]"

# Enable and start service
systemctl enable --now haproxy >/dev/null 2>&1
run_command "[set the haproxy service to start automatically at boot]"

systemctl restart haproxy >/dev/null 2>&1
run_command "[restart haproxy service]"

# Wait for the service to restart
sleep 15

# Add an empty line after the task
echo

# Step 11:
PRINT_TASK "TASK [Creating the installation configuration file]"

# Create ssh-key for accessing CoreOS
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo "ok: [create ssh-key for accessing coreos]"
else
    echo "info: [ssh key already exists, skip generation]"
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
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: '${SSH_PUB_STR}'
EOF
run_command "[create ${HTTPD_DIR}/install-config.yaml file]"

# Add an empty line after the task
echo

# Step 12:
PRINT_TASK "TASK [Generate the kubernetes manifest and ignition config files]"

# Create installation directory
rm -rf "${INSTALL_DIR}" >/dev/null 2>&1
sleep 1
mkdir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "[create installation directory: ${INSTALL_DIR}]"

# Copy install-config.yaml to installation directory
cp "${HTTPD_DIR}/install-config.yaml" "${INSTALL_DIR}"
run_command "[copy the install-config.yaml file to the installation directory]"

# Generate manifests
/usr/local/bin/openshift-install create manifests --dir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "[generate the kubernetes manifest]"

# Check if the file contains "mastersSchedulable: true"
if grep -q "mastersSchedulable: true" "${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml"; then
  # Replace "mastersSchedulable: true" with "mastersSchedulable: false"
  sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml"
  echo "ok: [disable the master node from scheduling custom pods]"
else
  echo "skipped: [scheduling of custom pods on master nodes is already disabled]"
fi

# Generate and modify ignition configuration files
/usr/local/bin/openshift-install create ignition-configs --dir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "[generate the ignition config files]"

# Add an empty line after the task
echo

# Step 13:
PRINT_TASK "TASK [Generate setup script file]"

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
        *)  echo "failed: [unknown host type for ${HOSTNAME}]" ;;
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
        echo "ok: [generate setup script: ${INSTALL_DIR}/${HOSTNAME}]"
    else
        echo "failed: [generate setup script for ${HOSTNAME}]"
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
chmod a+r "${INSTALL_DIR}"/*.ign

# Make the script executable
chmod a+rx "${INSTALL_DIR}"/{bs,m*,w*}
run_command "[change ocp intall script file permissions]"

# Add an empty line after the task
echo

# Step 14:
PRINT_TASK "TASK [Generate approve csr script file]"

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
run_command "[generate approve csr script: ${INSTALL_DIR}/ocp4cert-approver.sh]"

# Run the CSR auto-approver script
bash ${INSTALL_DIR}/ocp4cert-approver.sh &
run_command "[run the csr auto-approver script: ${INSTALL_DIR}/ocp4cert-approver.sh]"

# Add an empty line after the task
echo

## Step 13:
#PRINT_TASK "TASK [Generate an ignition file containing the node hostname]"
#
## Copy ignition files with appropriate hostnames
#BOOTSTRAP_HOSTNAME="bs"
#MASTER_ABBREVS=("m${MASTER01_HOSTNAME: -1}" "m${MASTER02_HOSTNAME: -1}" "m${MASTER03_HOSTNAME: -1}")
#WORKER_ABBREVS=("w${WORKER01_HOSTNAME: -1}" "w${WORKER02_HOSTNAME: -1}" "w${WORKER03_HOSTNAME: -1}")
#
#MASTER_FULL_HOSTNAMES=("${MASTER01_HOSTNAME}" "${MASTER02_HOSTNAME}" "${MASTER03_HOSTNAME}")
#WORKER_FULL_HOSTNAMES=("${WORKER01_HOSTNAME}" "${WORKER02_HOSTNAME}" "${WORKER03_HOSTNAME}")
#
#cp "${INSTALL_DIR}/bootstrap.ign" "${INSTALL_DIR}/append-${BOOTSTRAP_HOSTNAME}.ign"
#run_command "[copy bootstrap.ign to ${INSTALL_DIR}/append-${BOOTSTRAP_HOSTNAME}.ign]"
#
#for ABBREV in "${MASTER_ABBREVS[@]}"; do
#    cp "${INSTALL_DIR}/master.ign" "${INSTALL_DIR}/append-${ABBREV}.ign"
#    run_command "[copy master.ign to ${INSTALL_DIR}/append-${ABBREV}.ign]"
#done
#
#for ABBREV in "${WORKER_ABBREVS[@]}"; do
#    cp "${INSTALL_DIR}/worker.ign" "${INSTALL_DIR}/append-${ABBREV}.ign"
#    run_command "[copy worker.ign to ${INSTALL_DIR}/append-${ABBREV}.ign]"
#done
#
## Update master hostname in ignition files
#for i in "${!MASTER_FULL_HOSTNAMES[@]}"; do
#    MASTER_FULL_NAME="${MASTER_FULL_HOSTNAMES[$i]}"
#    MASTER_ABBREV_NAME="${MASTER_ABBREVS[$i]}"
#    
#    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${MASTER_FULL_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},#"mode":420}]}}/' "${INSTALL_DIR}/append-${MASTER_ABBREV_NAME}.ign"
#    run_command "[update hostname in ${INSTALL_DIR}/append-${MASTER_ABBREV_NAME}.ign]"
#done
#
## Update worker hostname in ignition files
#for i in "${!WORKER_FULL_HOSTNAMES[@]}"; do
#    WORKER_FULL_NAME="${WORKER_FULL_HOSTNAMES[$i]}"
#    WORKER_ABBREV_NAME="${WORKER_ABBREVS[$i]}"
#    
#    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${WORKER_FULL_NAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},#"mode":420}]}}/' "${INSTALL_DIR}/append-${WORKER_ABBREV_NAME}.ign"
#    run_command "[update hostname in ${INSTALL_DIR}/append-${WORKER_ABBREV_NAME}.ign]"
#done
#
## Set correct permissions
#chmod a+r "${INSTALL_DIR}"/*.ign
#run_command "[change ignition file permissions]"
#
## Add an empty line after the task
#echo
#
## Step 14:
#PRINT_TASK "TASK [Generate setup script file]"
#
## Function to generate setup script for a node
#generate_setup_script() {
#    local HOSTNAME=$1
#    local IP_ADDRESS=$2
#
## Generate a setup script for the node
#cat << EOF > "${INSTALL_DIR}/${HOSTNAME}"
##!/bin/bash
## Configure network settings
#sudo nmcli con mod ${NET_IF_NAME} ipv4.addresses ${IP_ADDRESS}/${NETMASK} ipv4.gateway ${GATEWAY_IP} ipv4.dns ${LOCAL_DNS_IP} ipv4.method manual #connection.autoconnect yes
#sudo nmcli con down ${NET_IF_NAME}
#sudo nmcli con up ${NET_IF_NAME}
#
#sudo sleep 10
#
## Install CoreOS using Ignition
#sudo coreos-installer install ${COREOS_INSTALL_DEV} --insecure-ignition --ignition-url=http://${BASTION_IP}:8080/pre/append-${HOSTNAME}.ign --firstboot-args 'rd.neednet=1' --copy-network
#EOF
#
#    # Check if the setup script file was successfully generated
#    if [ -f "${INSTALL_DIR}/${HOSTNAME}" ]; then
#        echo "ok: [generate setup script: ${INSTALL_DIR}/${HOSTNAME}]"
#    else
#        echo "failed: [generate setup script for ${HOSTNAME}]"
#    fi
#}
#
## Generate setup scripts for each node
#generate_setup_script "bs" "${BOOTSTRAP_IP}"
#generate_setup_script "m${MASTER01_HOSTNAME: -1}" "${MASTER01_IP}"  # → m1
#generate_setup_script "m${MASTER02_HOSTNAME: -1}" "${MASTER02_IP}"  # → m2
#generate_setup_script "m${MASTER03_HOSTNAME: -1}" "${MASTER03_IP}"  # → m3
#generate_setup_script "w${WORKER01_HOSTNAME: -1}" "${WORKER01_IP}"  # → w1
#generate_setup_script "w${WORKER02_HOSTNAME: -1}" "${WORKER02_IP}"  # → w2
#generate_setup_script "w${WORKER03_HOSTNAME: -1}" "${WORKER03_IP}"  # → w3
#
## Make the script executable
#chmod a+rx "${INSTALL_DIR}"/{bs,m*,w*}
#run_command "[change ocp intall script file permissions]"
#
## Add an empty line after the task
#echo
