#!/bin/bash
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

# Step 1:
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
echo 'export LANG=en_US.UTF-8' >> ~/.bash_profile
run_command "[write LANG=en_US.UTF-8 to the ./bash_profile file]"

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
packages=("wget" "net-tools" "vim-enhanced" "podman" "butane" "bind-utils" "bind" "haproxy" "git" "bash-completion" "jq" "nfs-utils" "httpd" "httpd-tools" "skopeo" "conmon" "httpd-manual")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
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

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Install openshift tool]"

# Download the openshift-install
wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE_VERSION}/openshift-install-linux.tar.gz" >/dev/null 2>&1
run_command "[download openshift-install tool]"

rm -f /usr/local/bin/openshift-install >/dev/null 2>&1
tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "[install openshift-install tool]"

chmod +x /usr/local/bin/openshift-install >/dev/null 2>&1
run_command "[modify /usr/local/bin/openshift-install permissions]"

rm -rf openshift-install-linux.tar.gz >/dev/null 2>&1

# Delete the old version of oc cli
rm -f /usr/local/bin/oc >/dev/null 2>&1
rm -f /usr/local/bin/kubectl >/dev/null 2>&1
rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -f /usr/local/bin/kubectx >/dev/null 2>&1
rm -f /usr/local/bin/kubens >/dev/null 2>&1

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
wget -q "$download_url" -O "$openshift_client"
run_command "[download openshift client tool]"

# Extract the downloaded tarball to /usr/local/bin/
tar -xzf "$openshift_client" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "[install openshift client tool]"

chmod +x /usr/local/bin/oc >/dev/null 2>&1
run_command "[modify /usr/local/bin/oc permissions]"

chmod +x /usr/local/bin/kubectl >/dev/null 2>&1
run_command "[modify /usr/local/bin/kubectl permissions]"

rm -f /usr/local/bin/README.md >/dev/null 2>&1
rm -rf $openshift_client >/dev/null 2>&1

# Get the RHEL version number
rhel_version=$(rpm -E %{rhel})
if [ "$rhel_version" -eq 8 ]; then
    download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.14.35/oc-mirror.tar.gz"
    oc_mirror="oc-mirror.tar.gz"
elif [ "$rhel_version" -eq 9 ]; then
    download_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"
    oc_mirror="oc-mirror.tar.gz"
fi

# Download the oc-mirror tool
wget -q "$download_url" -O "$oc_mirror"
run_command "[download oc-mirror tool]"

# Remove the old oc-mirror binary and install the new one
rm -rf /usr/local/bin/oc-mirror >/dev/null 2>&1
tar -xzf "$oc_mirror" -C "/usr/local/bin/" >/dev/null 2>&1
run_command "[install oc-mirror tool]"

chmod a+x /usr/local/bin/oc-mirror >/dev/null 2>&1
run_command "[modify /usr/local/bin/oc-mirror permissions]"

rm -rf $oc_mirror >/dev/null 2>&1

curl -sLo /usr/local/bin/kubectx https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx >/dev/null 2>&1
run_command "[install kubectx tool]"

curl -sLo /usr/local/bin/kubens https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens >/dev/null 2>&1
run_command "[install kubens tool]"

chmod +x /usr/local/bin/kubectx >/dev/null 2>&1
run_command "[modify /usr/local/bin/kubectx permissions]"

chmod +x /usr/local/bin/kubens >/dev/null 2>&1
run_command "[modify /usr/local/bin/kubens permissions]"

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
        echo "skipping: [http listen port is already 8080]"
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
touch ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
run_command "[create httpd test file]"

wget -q http://${BASTION_IP}:8080/httpd-test
run_command "[test httpd download function]"

rm -rf httpd-test ${HTTPD_DIR}/httpd-test >/dev/null 2>&1
run_command "[delete the httpd test file]"

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Setup nfs services]"

# Create NFS directories
rm -rf ${NFS_DIR} >/dev/null 2>&1
mkdir -p ${NFS_DIR} >/dev/null 2>&1
run_command "[create nfs director: ${NFS_DIR}]"

# Add nfsnobody user if not exists
if id "nfsnobody" >/dev/null 2>&1; then
    echo "skipping: [nfsnobody user exists]"
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
    echo "skipping: [nfs export configuration already exists]"
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
mkdir -p /tmp/nfs-test >/dev/null 2>&1
run_command "[create an nfs mount directory for testing: /tmp/nfs-test]"

# Attempt to mount the NFS share
mount -t nfs ${NFS_SERVER_IP}:${NFS_DIR} /tmp/nfs-test >/dev/null 2>&1
run_command "[test mounts the nfs shared directory: /tmp/nfs-test]"

# Unmount the NFS share
fuser -km /tmp/nfs-test >/dev/null 2>&1 || true
umount /tmp/nfs-test >/dev/null 2>&1 || true
run_command "[unmount the nfs shared directory: /tmp/nfs-test]"

# Delete /tmp/nfs-test
rm -rf /tmp/nfs-test >/dev/null 2>&1
run_command "[delete the test mounted nfs directory: /tmp/nfs-test]"

# Add an empty line after the task
echo

# Step 8:
PRINT_TASK "TASK [Setup named services]"

# Construct forward DNS zone name and zone file name
FORWARD_ZONE_NAME="${BASE_DOMAIN}"
FORWARD_ZONE_FILE="${BASE_DOMAIN}.zone"

# Check if the forward DNS zone name and zone file name are generated successfully
if [ -n "$FORWARD_ZONE_NAME" ] && [ -n "$FORWARD_ZONE_FILE" ]; then
    echo "ok: [generate forward DNS zone name $FORWARD_ZONE_NAME]"
    echo "ok: [generate forward zone file name $FORWARD_ZONE_FILE]"
else
    echo "failed: [generate forward DNS zone name or forward zone file name]"
fi

# Generate reverse DNS zone name and reverse zone file name 
# Extract the last two octets from the IP address
IFS='.' read -ra octets <<< "$DNS_SERVER_IP"
OCTET0="${octets[0]}"
OCTET1="${octets[1]}"

# Construct reverse DNS zone name and zone file name
REVERSE_ZONE_NAME="${OCTET1}.${OCTET0}.in-addr.arpa"
REVERSE_ZONE_FILE="${OCTET1}.${OCTET0}.zone"

# Check if the reverse DNS zone name and zone file name are generated successfully
if [ -n "$REVERSE_ZONE_NAME" ] && [ -n "$REVERSE_ZONE_FILE" ]; then
    echo "ok: [generate reverse DNS zone name $REVERSE_ZONE_NAME]"
    echo "ok: [generate reverse zone file name $REVERSE_ZONE_FILE]"
else
    echo "failed: [generate reverse DNS zone name or reverse zone file name]"
fi

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
; Create an entry for the bootstrap host.
$(format_dns_entry "${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${BOOTSTRAP_IP}")
;
; Create entries for the mirror registry hosts.
$(format_dns_entry "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}." "${REGISTRY_IP}")
EOF
run_command "[generate forward DNS zone file: /var/named/${FORWARD_ZONE_FILE}]"

# Clean up: Delete duplicate file
rm -f /var/named/${REVERSE_ZONE_FILE}

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

# Step 6: Add dns ip to resolv.conf and change zone permissions
# ----------------------------------------------------
# Add dns ip to resolv.conf
sed -i "/${DNS_SERVER_IP}/d" /etc/resolv.conf >/dev/null 2>&1
sed -i "1s/^/nameserver ${DNS_SERVER_IP}\n/" /etc/resolv.conf >/dev/null 2>&1
run_command "[add dns ip $DNS_SERVER_IP to /etc/resolv.conf]"

# Change ownership
chown named. /var/named/*.zone >/dev/null 2>&1
run_command "[change ownership /var/named/*.zone]"

# Enable and start service
systemctl enable named  >/dev/null 2>&1
run_command "[set the named service to start automatically at boot]"

systemctl restart named  >/dev/null 2>&1
run_command "[restart named service]"

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
    "${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${BASTION_IP}"
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


# Add an empty line after the task
echo

# Step 9:
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
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:6443 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:6443 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:6443 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:6443 check inter 1s

listen machine-config-server-22623 
  bind ${LB_IP}:22623
  mode tcp
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:22623 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:22623 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:22623 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:22623 check inter 1s

listen default-ingress-router-80
  bind ${LB_IP}:80
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:80 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:80 check inter 1s
  server     ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:80 check inter 1s
  
listen default-ingress-router-443
  bind ${LB_IP}:443
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:443 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:443 check inter 1s
  server     ${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER03_IP}:443 check inter 1s
EOF
run_command "[generate haproxy configuration file"

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

# Step 10:
PRINT_TASK "TASK [Install mirror registry]"

# Check if there is an active mirror registry pod
if sudo podman pod ps | grep -E 'quay-pod.*Running' >/dev/null 2>&1; then
    # If the mirror registry pod is running, uninstall it
    ${REGISTRY_INSTALL_DIR}/mirror-registry uninstall --autoApprove --quayRoot ${REGISTRY_INSTALL_DIR} >/dev/null 2>&1
    # Check the exit status of the uninstall command
    if [ $? -eq 0 ]; then
        echo "ok: [uninstall the mirror registry]"
    else
        echo "failed: [uninstall the mirror registry]"
    fi
else
    echo "skipping: [no active mirror registry pod found]"
fi

# Delete existing duplicate data
files=(
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem"
    "${REGISTRY_INSTALL_DIR}"
)

for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        sudo rm -rf "$file" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "ok: [delete existing duplicate data: $file]"
        else
            echo "failed: [delete existing duplicate data: $file]"
        fi
    else
        echo "skipping: [no duplicate data: $file]"
    fi
done

# Create installation directory
mkdir -p ${REGISTRY_INSTALL_DIR}
mkdir -p ${REGISTRY_INSTALL_DIR}/quay-storage
mkdir -p ${REGISTRY_INSTALL_DIR}/sqlite-storage
chmod -R 777 ${REGISTRY_INSTALL_DIR}
run_command "[create ${REGISTRY_INSTALL_DIR} directory]"

# Download mirror-registry
# wget -P ${REGISTRY_INSTALL_DIR} https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz >/dev/null 2>&1
wget -O ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz >/dev/null 2>&1
run_command "[download mirror-registry package]"

# Extract the downloaded mirror-registry package
tar xvf ${REGISTRY_INSTALL_DIR}/mirror-registry.tar.gz -C ${REGISTRY_INSTALL_DIR}/ >/dev/null 2>&1
run_command "[extract the mirror-registry package]"

echo "ok: [start installing mirror-registry...]"
# Install mirror-registry
sudo ${REGISTRY_INSTALL_DIR}/mirror-registry install -v \
     --quayHostname ${REGISTRY_HOSTNAME}.${BASE_DOMAIN} \
     --quayRoot ${REGISTRY_INSTALL_DIR} \
     --quayStorage ${REGISTRY_INSTALL_DIR}/quay-storage \
     --sqliteStorage ${REGISTRY_INSTALL_DIR}/sqlite-storage \
     --initUser ${REGISTRY_ID} \
     --initPassword ${REGISTRY_PW}
run_command "[installation of mirror registry completed]"

progress_started=false
while true; do
    # Get the status of all pods
    output=$(sudo podman pod ps | awk 'NR>1' | grep -P '(?=.*\bquay-pod\b)(?=.*\bRunning\b)(?=.*\b3\b)')
    
    # Check if the pod is not in the "Running" state
    if [ -z "$output" ]; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for quay pod to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 10
    else
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [quay pod is in 'running' state]"
        break
    fi
done

# Copy the rootCA certificate to the trusted source
cp ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem
run_command "[copy the rootCA certificate to the trusted source: /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.pem]"

# Trust the rootCA certificate
update-ca-trust >/dev/null 2>&1
run_command "[trust the rootCA certificate]"

# Delete the tar package generated during installation
rm -rf pause.tar postgres.tar quay.tar redis.tar >/dev/null 2>&1
run_command "[delete the tar package: pause.tar postgres.tar quay.tar redis.tar]"

sleep 5

# Login to the registry
rm -rf $XDG_RUNTIME_DIR/containers
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443" >/dev/null 2>&1
run_command "[login registry https://${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:8443]"

# Add an empty line after the task
echo

# Step 11:
PRINT_TASK "TASK [Generate a defined install-config file]"

# Backup and format the registry CA certificate
rm -rf "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak"
cp "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem" "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak"
run_command "[backup registry CA certificate]"

sed -i 's/^/  /' "${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak"
run_command "[format registry ca certificate]"

# Create ssh-key for accessing CoreOS
rm -rf ${SSH_KEY_PATH} >/dev/null 2>&1
ssh-keygen -N '' -f ${SSH_KEY_PATH}/id_rsa >/dev/null 2>&1
run_command "[create ssh-key for accessing coreos]"

# Define variables
export REGISTRY_CA_CERT_FORMAT="$(cat ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak)"
export REGISTRY_AUTH=$(echo -n "${REGISTRY_ID}:${REGISTRY_PW}" | base64)
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Generate a defined install-config file
rm -rf ${HTTPD_DIR}/install-config.yaml >/dev/null 2>&1

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
run_command "[create ${HTTPD_DIR}/install-config.yaml file]"

# Delete certificate
rm -rf ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak >/dev/null 2>&1
run_command "[delete ${REGISTRY_INSTALL_DIR}/quay-rootCA/rootCA.pem.bak file]"

# Add an empty line after the task
echo

# Step 12:
PRINT_TASK "TASK [Generate a manifests]"

# Create installation directory
rm -rf "${INSTALL_DIR}" >/dev/null 2>&1
mkdir -p "${INSTALL_DIR}" >/dev/null 2>&1
run_command "[create installation directory: ${INSTALL_DIR}]"

# Copy install-config.yaml to installation directory
cp "${HTTPD_DIR}/install-config.yaml" "${INSTALL_DIR}" >/dev/null 2>&1
run_command "[copy the install-config.yaml file to the installation directory]"

# Generate manifests
/usr/local/bin/openshift-install create manifests --dir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "[generate manifests]"

# Check if the file contains "mastersSchedulable: true"
if grep -q "mastersSchedulable: true" "${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml"; then
  # Replace "mastersSchedulable: true" with "mastersSchedulable: false"
  sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml"
  echo "ok: [disable the master node from scheduling custom pods]"
else
  echo "skipping: [scheduling of custom pods on master nodes is already disabled]"
fi

# Add an empty line after the task
echo

# Step 13:
PRINT_TASK "TASK [Generate default ignition file]"

# Generate and modify ignition configuration files
/usr/local/bin/openshift-install create ignition-configs --dir "${INSTALL_DIR}" >/dev/null 2>&1
run_command "[generate default ignition file]"

# Add an empty line after the task
echo

# Step 14:
PRINT_TASK "TASK [Generate an ignition file containing the node hostname]"

# Copy ignition files with appropriate hostnames
BOOTSTRAP_HOSTNAME="${BOOTSTRAP_HOSTNAME}"
MASTER_HOSTNAMES=("${MASTER01_HOSTNAME}" "${MASTER02_HOSTNAME}" "${MASTER03_HOSTNAME}")
WORKER_HOSTNAMES=("${WORKER01_HOSTNAME}" "${WORKER02_HOSTNAME}" "${WORKER03_HOSTNAME}")

cp "${INSTALL_DIR}/bootstrap.ign" "${INSTALL_DIR}/append-${BOOTSTRAP_HOSTNAME}.ign"
run_command "[copy and customize the bootstrap.ign file name: append-${BOOTSTRAP_HOSTNAME}.ign]"

for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    cp "${INSTALL_DIR}/master.ign" "${INSTALL_DIR}/append-${MASTER_HOSTNAME}.ign"
    run_command "[copy and customize the master.ign file name: append-${MASTER_HOSTNAME}.ign]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    cp "${INSTALL_DIR}/worker.ign" "${INSTALL_DIR}/append-${WORKER_HOSTNAME}.ign"
    run_command "[copy and customize the worker.ign file name: append-${WORKER_HOSTNAME}.ign]"
done

# Update hostname in ignition files
for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${MASTER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},"mode":420}]}}/' "${INSTALL_DIR}/append-${MASTER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the append-${MASTER_HOSTNAME}.ign file]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${WORKER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},"mode":420}]}}/' "${INSTALL_DIR}/append-${WORKER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the append-${WORKER_HOSTNAME}.ign file]"
done

# Set correct permissions
chmod a+r "${INSTALL_DIR}"/*.ign
run_command "[change ignition file permissions]"

# Add an empty line after the task
echo

# Step 15:
PRINT_TASK "TASK [Generate setup script file]"

rm -rf ${INSTALL_DIR}/*.sh

# Function to generate setup script for a node
generate_setup_script() {
    local HOSTNAME=$1
    local IP_ADDRESS=$2

# Generate a setup script for the node
cat << EOF > "${INSTALL_DIR}/set-${HOSTNAME}.sh"
#!/bin/bash
# Configure network settings
sudo nmcli con mod ${NET_IF_NAME} ipv4.addresses ${IP_ADDRESS}/${NETMASK} ipv4.gateway ${GATEWAY_IP} ipv4.dns ${DNS_SERVER_IP} ipv4.method manual connection.autoconnect yes
sudo nmcli con down ${NET_IF_NAME}
sudo nmcli con up ${NET_IF_NAME}

sudo sleep 10

# Install CoreOS using Ignition
sudo coreos-installer install ${COREOS_INSTALL_DEV} --insecure-ignition --ignition-url=http://${BASTION_IP}:8080/pre/append-${HOSTNAME}.ign --insecure-ignition --firstboot-args 'rd.neednet=1' --copy-network
EOF

    # Check if the setup script file was successfully generated
    if [ -f "${INSTALL_DIR}/set-${HOSTNAME}.sh" ]; then
        echo "ok: [generate setup script: ${INSTALL_DIR}/set-${HOSTNAME}.sh]"
    else
        echo "failed: [generate setup script for ${HOSTNAME}]"
    fi
}

# Generate setup scripts for each node
generate_setup_script "${BOOTSTRAP_HOSTNAME}" "${BOOTSTRAP_IP}"
generate_setup_script "${MASTER01_HOSTNAME}" "${MASTER01_IP}"
generate_setup_script "${MASTER02_HOSTNAME}" "${MASTER02_IP}"
generate_setup_script "${MASTER03_HOSTNAME}" "${MASTER03_IP}"
generate_setup_script "${WORKER01_HOSTNAME}" "${WORKER01_IP}"
generate_setup_script "${WORKER02_HOSTNAME}" "${WORKER02_IP}"
generate_setup_script "${WORKER03_HOSTNAME}" "${WORKER03_IP}"

# Make the script executable
chmod +x ${INSTALL_DIR}/*.sh
run_command "[change ignition file permissions]"

# Add an empty line after the task
echo

# Step 16:
PRINT_TASK "TASK [Generate approve csr script file]"

# If the file exists, delete it
rm -rf "${INSTALL_DIR}/approve-csr.sh"

# Generate approve csr script file]
cat << EOF > "${INSTALL_DIR}/ocp4cert_approver.sh"
#!/bin/bash

for i in {1..720}; do 
  oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
  sleep 10
done 
EOF
run_command "[Generate approve csr script file]"

# Add an empty line after the task
echo
