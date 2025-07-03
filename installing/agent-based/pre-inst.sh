#!/bin/bash

# Specify required parameters for install-config.yaml
export CLUSTER_NAME="copan"
export BASE_DOMAIN="ocp.lan"
export MACHINE_NETWORK_CIDR="10.184.134.1/24"
export PULL_SECRET_FILE="$HOME/pull-secret"

# Specify the OpenShift node infrastructure network configuration and installation disk
export COREOS_INSTALL_DEV="/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:0:0"   # or /dev/sdX
export NET_IF_NAME="ens33" 
export GATEWAY_IP="10.184.134.1"
export NETMASK="24"

# Specify OpenShift node’s hostname and IP address
export BASTION_IP="10.184.134.128"  
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"

export MASTER01_IP="10.184.134.15"
export MASTER02_IP="10.184.134.16"
export MASTER03_IP="10.184.134.17"
export WORKER01_IP="10.184.134.18"
export WORKER02_IP="10.184.134.19"

export MASTER01_MAC_ADDR="00:50:56:b0:e7:77"
export MASTER02_MAC_ADDR="00:50:56:b0:3d:26"
export MASTER03_MAC_ADDR="00:50:56:b0:f5:9f"
export WORKER01_MAC_ADDR="00:50:56:b0:0c:d1"
export WORKER02_MAC_ADDR="00:50:56:b0:72:a5"

export SSH_KEY_PATH="$HOME/.ssh"
export RENDEZVOUS_IP="$MASTER01_IP"
export NTP_SERVER="0.rhel.pool.ntp.org"
export NSLOOKUP_TEST_PUBLIC_DOMAIN="redhat.com"
export DNS_SERVER_IP="$BASTION_IP"
export API_IP="$BASTION_IP"
export API_INT_IP="$BASTION_IP"
export APPS_IP="$BASTION_IP"
export LB_IP="$BASTION_IP"

# The following contents do not need to be changed
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
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
packages=("bind-utils" "bind" "haproxy")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
echo "info: [installing required rpm packages]"
dnf install -y $package_list >/dev/null

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "ok: [installed $package package]"
    else
        echo "failed: [installed $package package]"
    fi
done

dnf -y install /usr/bin/nmstatectl
run_command "[installed nmstatectl package]"

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Install openshift-install and openshift client tools]"

# Delete the old version of oc cli
rm -f /usr/local/bin/oc* >/dev/null 2>&1
rm -f /usr/local/bin/kube* >/dev/null 2>&1
rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -f openshift-install-linux.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux-amd64-rhel8.tar.gz* >/dev/null 2>&1
rm -f openshift-client-linux.tar.gz* >/dev/null 2>&1

# Download the openshift-install
echo "info: [downloading openshift-install tool]"

wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE_VERSION}/openshift-install-linux.tar.gz" >/dev/null 2>&1
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

# Step 3:
PRINT_TASK "TASK [Create openshift cluster]"

# Check if the SSH key exists
if [ ! -f "${SSH_KEY_PATH}/id_rsa" ] || [ ! -f "${SSH_KEY_PATH}/id_rsa.pub" ]; then
    rm -rf ${SSH_KEY_PATH} 
    mkdir -p ${SSH_KEY_PATH}
    ssh-keygen -t rsa -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
    echo "ok: [create ssh-key for accessing coreos]"
else
    echo "info: [ssh key already exists, skip generation]"
fi

# Step 9:
PRINT_TASK "TASK [Setup named services]"

# Construct forward DNS zone name and zone file name
FORWARD_ZONE_NAME="${BASE_DOMAIN}"
FORWARD_ZONE_FILE="${BASE_DOMAIN}.zone"

# Generate reverse DNS zone name and reverse zone file name 
# Extract the last two octets from the IP address
IFS='.' read -ra octets <<< "$DNS_SERVER_IP"
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
ns1     IN      A       ${DNS_SERVER_IP}
;
helper  IN      A       ${DNS_SERVER_IP}
helper.ocp4     IN      A       ${DNS_SERVER_IP}
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
sed -i "/${DNS_SERVER_IP}/d" /etc/resolv.conf
sed -i "1s/^/nameserver ${DNS_SERVER_IP}\n/" /etc/resolv.conf
run_command "[add dns ip $DNS_SERVER_IP to /etc/resolv.conf]"

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
    "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${BASTION_IP}"
    "${MASTER01_IP}"
    "${MASTER02_IP}"
    "${MASTER03_IP}"
    "${WORKER01_IP}"
    "${WORKER02_IP}"
    "${WORKER03_IP}"
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
  bind ${LB_IP}:6443
  mode tcp
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:6443 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:6443 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:6443 check inter 1s

listen machine-config-server-22623 
  bind ${LB_IP}:22623
  mode tcp
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:22623 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:22623 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:22623 check inter 1s

listen default-ingress-router-80
  bind ${LB_IP}:80
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:80 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:80 check inter 1s
  
listen default-ingress-router-443
  bind ${LB_IP}:443
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:443 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:443 check inter 1s
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
PRINT_TASK "TASK [Generate a defined agent-config file]"

# Generate a defined install-config file
rm -rf ocp-inst >/dev/null 2>&1
mkdir ocp-inst  >/dev/null 2>&1
run_command "[create an installation directory: ocp-inst]"

cat << EOF > ocp-inst/agent-config.yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: my-cluster
additionalNTPSources:
- "${NTP_SERVER}"
rendezvousIP: "${RENDEZVOUS_IP}"
hosts:
  - hostname: "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: master
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${MASTER01_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${MASTER01_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${MASTER01_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_SERVER_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: master
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${MASTER02_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${MASTER02_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${MASTER02_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_SERVER_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: master
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${MASTER03_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${MASTER03_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${MASTER03_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_SERVER_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: worker
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${WORKER01_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${WORKER01_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${WORKER01_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_SERVER_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: worker
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${WORKER02_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${WORKER02_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${WORKER02_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_SERVER_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
EOF
run_command "[create ocp-inst/agent-config.yaml file]"

# Step 11:
PRINT_TASK "TASK [Generate a defined install-config file]"

cat << EOF > ocp-inst/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 2
controlPlane:
  hyperthreading: Enabled 
  name: master
  replicas: 3
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: "10.128.0.0/14"
    hostPrefix: "23"
  networkType: "OVNKubernetes"
  serviceNetwork: 
  - "172.30.0.0/16"
  machineNetwork:
  - cidr: "${MACHINE_NETWORK_CIDR}"
platform:
  none: {} 
fips: false
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: |
  $(cat $SSH_KEY_PATH/id_rsa.pub)
EOF
run_command "[create ocp-inst/install-config.yaml file]"
