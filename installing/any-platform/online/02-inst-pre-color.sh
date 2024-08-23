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

GREEN='\033[0;32m'   # Green
RED='\033[0;31m'     # Red
BLUE='\033[0;34m'    # blue
NC='\033[0m'         # No Color (reset)

run_command() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}ok: $1${NC}"
    else
        echo -e "${RED}failed: $1${NC}"
    fi
}
# ====================================================


# === Task: Disable and stop firewalld service ===
PRINT_TASK "[TASK: Disable and stop firewalld service]"

# Stop and disable firewalld services
systemctl disable --now firewalld
run_command "[firewalld service stopped and disabled]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Change SELinux security policy ===
PRINT_TASK "[TASK: Change SELinux security policy]"

# Read the SELinux configuration
permanent_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
# Check if the permanent status is Enforcing
if [[ $permanent_status == "enforcing" ]]; then
    # Change SELinux to permissive
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    permanent_status="permissive"
    echo -e "${GREEN}ok: [selinux permanent security policy changed to $permanent_status]${NC}"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo -e "${GREEN}ok: [selinux permanent security policy is $permanent_status]${NC}"
else
    echo -e "${RED}failed: [selinux permanent security policy is $permanent_status (expected permissive or disabled)]${NC}"
fi


# Temporarily set SELinux security policy to permissive
setenforce 0 &>/dev/null
# Check temporary SELinux security policy
temporary_status=$(getenforce)
# Check if temporary SELinux security policy is permissive or disabled
if [[ $temporary_status == "Permissive" || $temporary_status == "Disabled" ]]; then
    echo -e "${GREEN}ok: [selinux temporary security policy is $temporary_status]${NC}"
else
    echo -e "${RED}failed: [selinux temporary security policy is $temporary_status (expected Permissive or Disabled)${NC}]"
fi

# Add an empty line after the task
echo
# ====================================================


# === Task: Install infrastructure rpm ===
PRINT_TASK "[TASK: Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "net-tools" "vim" "podman" "bind-utils" "bind" "haproxy" "git" "bash-completion" "jq" "nfs-utils" "httpd" "httpd-tools" "skopeo" "conmon" "httpd-manual")

# Install the RPM package and return the execution result
for package in "${packages[@]}"; do
    yum install -y "$package" &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}ok: [install $package package]${NC}"
    else
        echo -e "${RED}failed: [install $package package]${NC}"
    fi
done

# Add an empty line after the task
echo
# ====================================================



# === Task: Install openshift tool ===
PRINT_TASK "[TASK: Install openshift tool]"

# Step 1: Download the openshift-install
# ----------------------------------------------------
# Download the openshift-install
wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE_VERSION}/openshift-install-linux.tar.gz" &> /dev/null
run_command "[Download openshift-install tool]"

rm -f /usr/local/bin/openshift-install &> /dev/null
tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" &> /dev/null
run_command "[Install openshift-install tool]"

chmod +x /usr/local/bin/openshift-install &> /dev/null
run_command "[modify /usr/local/bin/openshift-install permissions]"

rm -rf openshift-install-linux.tar.gz &> /dev/null

# Step 2: Download the oc cli
# ----------------------------------------------------
# Delete the old version of oc cli
rm -f /usr/local/bin/oc &> /dev/null
rm -f /usr/local/bin/kubectl &> /dev/null
rm -f /usr/local/bin/README.md &> /dev/null

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

# Step 3: Download the oc mirror
# ----------------------------------------------------
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
run_command "[Download oc-mirror tool]"

# Remove the old oc-mirror binary and install the new one
rm -rf /usr/local/bin/oc-mirror &> /dev/null
tar -xzf "$oc_mirror" -C "/usr/local/bin/" &> /dev/null
run_command "[Install oc-mirror tool]"

chmod a+x /usr/local/bin/oc-mirror &> /dev/null
run_command "[modify /usr/local/bin/oc-mirror permissions]"

rm -rf $oc_mirror &> /dev/null


# Write LANG=en_US.UTF-8 to the ./bash_profile file]
echo 'export LANG=en_US.UTF-8' >> ~/.bash_profile
run_command "[Write LANG=en_US.UTF-8 to the ./bash_profile file]"

# Reload ~/.bash_profile
source ~/.bash_profile
run_command "[Reload ~/.bash_profile]"

# Change time zone to UTC
timedatectl set-timezone UTC
run_command "[Change time zone to UTC]"

# Change hostname
hostnamectl set-hostname ${BASTION_HOSTNAME}
run_command "[Change hostname to ${BASTION_HOSTNAME}]"
# Add an empty line after the task
echo


# === Task: Setup and check httpd services ===
PRINT_TASK "[TASK: Setup and check httpd services]"
# Step 1: Update httpd listen port
# ----------------------------------------------------
# Update httpd listen port
update_httpd_listen_port() {
    # Get the current listen port from httpd.conf
    listen_port=$(grep -v "#" /etc/httpd/conf/httpd.conf | grep -i 'Listen' | awk '{print $2}')
    
    # Check if listen port is not 8080
    if [ "$listen_port" != "8080" ]; then
        # Change listen port to 8080
        sed -i 's/^Listen .*/Listen 8080/' /etc/httpd/conf/httpd.conf
        echo -e "${GREEN}ok: [change http listening port to 8080]${NC}"
    else
        echo -e "${BLUE}skipping: [http listen port is already 8080]${NC}"
    fi
}

# Call the function to update listen port
update_httpd_listen_port


# Step 2: Create virtual host configuration and http dir
# ----------------------------------------------------
# Create virtual host configuration
create_virtual_host_config() {
    # Create a virtual host configuration file
    cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName ${BASTION_HOSTNAME}
   DocumentRoot ${HTTPD_PATH}
</VirtualHost>
EOF
}

# Create virtual host configuration
create_virtual_host_config

# Check if virtual host configuration is valid
check_virtual_host_configuration() {
    # Define expected values for server name and document root
    expected_server_name="${BASTION_HOSTNAME}"
    expected_document_root="${HTTPD_PATH}"
    
    # Path to virtual host configuration file
    virtual_host_config="/etc/httpd/conf.d/base.conf"
    
    # Check if expected values are present in the config
    if grep -q "ServerName $expected_server_name" "$virtual_host_config" && \
       grep -q "DocumentRoot $expected_document_root" "$virtual_host_config"; then
        echo -e "${GREEN}ok: [create virtual host configuration]${NC}"
    else
        echo -e "${RED}failed: [create virtual host configuration]${NC}"
    fi
}

# Check virtual host configuration
check_virtual_host_configuration

# Create http dir
mkdir -p ${HTTPD_PATH}
run_command "[create http: ${HTTPD_PATH} director]"


# Step 3: Enable and Restart httpd service
# ----------------------------------------------------

# Enable and start service
systemctl enable --now httpd
run_command "[restart and enable httpd service]"

# Wait for the service to restart
sleep 3


# Step 4: Test
# ----------------------------------------------------
# Test httpd configuration
touch ${HTTPD_PATH}/httpd-test
run_command "[create httpd test file]"

wget -q http://${BASTION_IP}:8080/httpd-test
run_command "[test httpd download function]"

rm -rf httpd-test ${HTTPD_PATH}/httpd-test
run_command "[delete the httpd test file]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Setup nfs services ===
PRINT_TASK "[TASK: Setup nfs services]"

# Step 1: Create directory /user and change permissions and add NFS export
# ----------------------------------------------------
# Create NFS directories
rm -rf ${NFS_PATH}
mkdir -p ${NFS_PATH}/${IMAGE_REGISTRY_PV}
run_command "[create nfs director: ${NFS_PATH}]"


# Add nfsnobody user if not exists
if id "nfsnobody" &>/dev/null; then
    echo -e "${BLUE}skipping: [nfsnobody user exists]${NC}"
else
    useradd nfsnobody
    echo -e "${GREEN}ok: [add nfsnobody user]${NC}"
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_PATH}
run_command "[changing ownership of an NFS directory]"

chmod -R 777 ${NFS_PATH}
run_command "[change NFS directory permissions]"


# Add NFS export configuration
export_config_line="${NFS_PATH}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo -e "${BLUE}skipping: [nfs export configuration already exists]${NC}"
else
    echo "$export_config_line" >> "/etc/exports"
    echo -e "${GREEN}ok: [add nfs export configuration]${NC}"
fi


# Step 2: Enable and Restart nfs-server service
# ----------------------------------------------------
# Enable and start service
systemctl enable --now nfs-server
run_command "[restart and enable nfs-server service]"

# Wait for the service to restart
sleep 3


# Step 3: Test
# ----------------------------------------------------
# Function to check if NFS share is accessible
check_nfs_access() {
    mount_point="/mnt/nfs_test"
    
    # Create the mount point if it doesn't exist
    mkdir -p $mount_point
    
    # Attempt to mount the NFS share
    mount -t nfs ${NFS_SERVER_IP}:${NFS_PATH} $mount_point

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}ok: [test mounts the nfs shared directory]${NC}"
        # Unmount the NFS share
        umount $mount_point
        rmdir $mount_point
        return 0
    else
        echo -e "${RED}failed: [test mount nfs shared directory]${NC}"
        rmdir $mount_point
        return 1
    fi
}

# Call the function to check NFS access
check_nfs_access

# Add an empty line after the task
echo
# ====================================================



# === Task: Setup named services ===
PRINT_TASK "[TASK: Setup named services]"
# Step 1: Generate DNS zone name/zone file name
# ----------------------------------------------------
# Generate reverse DNS zone name and reverse zone file name
# Construct forward DNS zone name and zone file name
FORWARD_ZONE_NAME="${BASE_DOMAIN}"
FORWARD_ZONE_FILE="${BASE_DOMAIN}.zone"

# Check if the forward DNS zone name and zone file name are generated successfully
if [ -n "$FORWARD_ZONE_NAME" ] && [ -n "$FORWARD_ZONE_FILE" ]; then
    echo -e "${GREEN}ok: [generate forward DNS zone name $FORWARD_ZONE_NAME]${NC}"
    echo -e "${GREEN}ok: [generate forward zone file name $FORWARD_ZONE_FILE]${NC}"
else
    echo -e "${RED}failed: [generate forward DNS zone name or forward zone file name]${NC}"
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
    echo -e "${GREEN}ok: [generate reverse DNS zone name $REVERSE_ZONE_NAME]${NC}"
    echo -e "${GREEN}ok: [generate reverse zone file name $REVERSE_ZONE_FILE]"
else
    echo -e "${RED}failed: [generate reverse DNS zone name or reverse zone file name]${NC}"
fi


# Step 2: Generate named service configuration file
# ----------------------------------------------------
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
    dnssec-enable yes;
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

# Check if the named configuration file was generated successfully
if [ -f "/etc/named.conf" ]; then
    echo -e "${GREEN}ok: [generate named configuration file]${NC}"
else
    echo -e "${RED}failed: [generate named configuration file]${NC}"
fi


# Step 3: Generate forward zone file
# ----------------------------------------------------
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
EOF

# Verify if the output file was generated successfully
if [ -f "/var/named/${FORWARD_ZONE_FILE}" ]; then
    echo -e "${GREEN}ok: [generate forward DNS zone file: /var/named/${FORWARD_ZONE_FILE}"
else
    echo -e "${RED}failed: [generate forward DNS zone file]"
fi


# Step 4: Create reverse zone file
# ----------------------------------------------------
#!/bin/bash
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
    echo -e "${GREEN}ok: [generate reverse DNS zone file: $reverse_zone_output_file]${NC}"
else
    echo -e "${RED}failed: [generate reverse DNS zone file]${NC}"
fi


# Step 5: Check named configuration/Dns file 
# ----------------------------------------------------
# Check named configuration file
if named-checkconf &>/dev/null; then
    echo -e "${GREEN}ok: [named configuration is valid]${NC}"
else
    echo -e "${RED}failed: [Named configuration is invalid]${NC}"
fi

# Check forward zone file
if named-checkzone ${FORWARD_ZONE_FILE} /var/named/${FORWARD_ZONE_FILE} &>/dev/null; then
    echo -e "${GREEN}ok: [forward zone file is valid]${NC}"
else
    echo -e "${RED}failed: [forward zone file is invalid]${NC}"
fi

# Check reverse zone file
if named-checkzone ${REVERSE_ZONE_FILE} /var/named/${REVERSE_ZONE_FILE} &>/dev/null; then
    echo -e "${GREEN}ok: [reverse zone file is valid]${NC}"
else
    echo -e "${RED}failed: [reverse zone file is invalid]${NC}"
fi


# Step 6: Add dns ip to resolv.conf and change zone permissions
# ----------------------------------------------------
# Add dns ip to resolv.conf
sed -i "/${DNS_SERVER_IP}/d" /etc/resolv.conf
sed -i "1s/^/nameserver ${DNS_SERVER_IP}\n/" /etc/resolv.conf
run_command "[add DNS_SERVER_IP to /etc/resolv.conf]"

# Change ownership
chown named. /var/named/*.zone
run_command "[change ownership /var/named/*.zone]"

# Step 7: Enable and Restart named service
# ----------------------------------------------------
# Enable and start service
systemctl enable --now named
run_command "[restart and enable named service]"

# Wait for the service to restart
sleep 3


# Step 8: Test nslookup
# ----------------------------------------------------
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
    "${NSLOOKUP_PUBLIC}"
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
    echo -e "${GREEN}ok: [nslookup all domain names/IP addresses]${NC}"
else
    echo -e "${RED}failed: [dns resolve failed for the following domain/IP:]${NC}"
    for failed_hostname in "${failed_hostnames[@]}"; do
        echo -e "${RED}$failed_hostname${NC}"
    done
fi

# Add an empty line after the task
echo
# ====================================================



# === Task: Setup HAproxy services ===
PRINT_TASK "[TASK: Setup HAproxy services]"
# Step 1: Generate haproxy service configuration file
# ----------------------------------------------------
# Specify the path and filename for the haproxy configuration file
haproxy_config_file="/etc/haproxy/haproxy.cfg"

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

# Verify if the haproxy configuration file was generated successfully
if [ -f "$haproxy_config_file" ]; then
    echo -e "${GREEN}ok: [generate haproxy configuration file${NC}"
else
    echo -e "${RED}failed: [generate haproxy configuration file${NC}"
fi


# Step 2: Check haproxy configuration
# ----------------------------------------------------
# Path to HAProxy configuration file
CONFIG_FILE="/etc/haproxy/haproxy.cfg"

# Check HAProxy configuration syntax
check_haproxy_config() {
    haproxy -c -f "$CONFIG_FILE" &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}ok: [haproxy configuration is valid]${NC}"
    else
        echo -e "${RED}failed: [haproxy configuration is invalid]${NC}"
    fi
}

# Call the function to check HAProxy configuration
check_haproxy_config


# Step 3: Enable and Restart haproxy service
# ----------------------------------------------------
# Enable and start service
systemctl enable --now haproxy
run_command "[restart and enable haproxy service]"


# Add an empty line after the task
echo
# ====================================================


# Task: Generate a defined install-config file
PRINT_TASK "[TASK: Generate a defined install-config file]"

# Create ssh-key for accessing CoreOS
rm -rf ${SSH_KEY_PATH}
ssh-keygen -N '' -f ${SSH_KEY_PATH}/id_rsa &> /dev/null
run_command "[create ssh-key for accessing coreos]"

# Define variables
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Generate a defined install-config file
rm -rf ${HTTPD_PATH}/install-config.yaml

cat << EOF > ${HTTPD_PATH}/install-config.yaml 
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
run_command "[create ${HTTPD_PATH}/install-config.yaml file]"

# Remove the temporary file
rm -f "${PULL_SECRET}"

# Add an empty line after the task
echo
# ====================================================


# Task:  Generate a manifests
PRINT_TASK "[TASK: Generate a manifests]"

# Create installation directory
rm -rf "${IGNITION_PATH}"
mkdir -p "${IGNITION_PATH}"
run_command "[create installation directory: ${IGNITION_PATH}]"

# Copy install-config.yaml to installation directory
cp "${HTTPD_PATH}/install-config.yaml" "${IGNITION_PATH}"
run_command "[copy the install-config.yaml file to the installation directory]"

# Generate manifests
/usr/local/bin/openshift-install create manifests --dir "${IGNITION_PATH}" &> /dev/null
run_command "[generate manifests]"

# Check if the file contains "mastersSchedulable: true"
if grep -q "mastersSchedulable: true" "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml"; then
  # Replace "mastersSchedulable: true" with "mastersSchedulable: false"
  sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' "${IGNITION_PATH}/manifests/cluster-scheduler-02-config.yml"
  echo -e "${GREEN}ok: [disable the master node from scheduling custom pods]${NC}"
else
  echo -e "${BLUE}skipping: [scheduling of custom pods on master nodes is already disabled]${NC}"
fi

# Add an empty line after the task
echo
# ====================================================


# Task: Generate default ignition file
PRINT_TASK "[TASK: Generate default ignition file]"

# Generate and modify ignition configuration files
/usr/local/bin/openshift-install create ignition-configs --dir "${IGNITION_PATH}" &> /dev/null
run_command "[generate default ignition file]"

# Add an empty line after the task
echo
# ====================================================


# Task: Generate an ignition file containing the node hostname
PRINT_TASK "[TASK: Generate an ignition file containing the node hostname]"

# Copy ignition files with appropriate hostnames
BOOTSTRAP_HOSTNAME="${BOOTSTRAP_HOSTNAME}"
MASTER_HOSTNAMES=("${MASTER01_HOSTNAME}" "${MASTER02_HOSTNAME}" "${MASTER03_HOSTNAME}")
WORKER_HOSTNAMES=("${WORKER01_HOSTNAME}" "${WORKER02_HOSTNAME}" "${WORKER03_HOSTNAME}")

cp "${IGNITION_PATH}/bootstrap.ign" "${IGNITION_PATH}/append-${BOOTSTRAP_HOSTNAME}.ign"
run_command "[copy and customize the bootstrap.ign file name: append-${BOOTSTRAP_HOSTNAME}.ign]"

for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/master.ign" "${IGNITION_PATH}/append-${MASTER_HOSTNAME}.ign"
    run_command "[copy and customize the master.ign file name: append-${MASTER_HOSTNAME}.ign]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    cp "${IGNITION_PATH}/worker.ign" "${IGNITION_PATH}/append-${WORKER_HOSTNAME}.ign"
    run_command "[copy and customize the worker.ign file name: append-${WORKER_HOSTNAME}.ign]"
done

# Update hostname in ignition files
for MASTER_HOSTNAME in "${MASTER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${MASTER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},"mode":420}]}}/' "${IGNITION_PATH}/append-${MASTER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the append-${MASTER_HOSTNAME}.ign file]"
done

for WORKER_HOSTNAME in "${WORKER_HOSTNAMES[@]}"; do
    sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,'"${WORKER_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"'"},"mode":420}]}}/' "${IGNITION_PATH}/append-${WORKER_HOSTNAME}.ign"
    run_command "[add the appropriate hostname field to the append-${WORKER_HOSTNAME}.ign file]"
done

# Set correct permissions
chmod a+r "${IGNITION_PATH}"/*.ign
run_command "[change ignition file permissions]"

# Add an empty line after the task
echo
# ====================================================


# Task: Generate setup script file
PRINT_TASK "[TASK: Generate setup script file]"

rm -rf ${IGNITION_PATH}/*.sh

# Function to generate setup script for a node
generate_setup_script() {
    local HOSTNAME=$1
    local IP_ADDRESS=$2

# Generate a setup script for the node
cat << EOF > "${IGNITION_PATH}/set-${HOSTNAME}.sh"
#!/bin/bash
# Configure network settings
nmcli con mod ${NET_IF_NAME} ipv4.addresses ${IP_ADDRESS}/${NETMASK} ipv4.gateway ${GATEWAY_IP} ipv4.dns ${DNS_SERVER_IP} ipv4.method manual connection.autoconnect yes
nmcli con down ${NET_IF_NAME}
nmcli con up ${NET_IF_NAME}

sudo sleep 10

# Install CoreOS using Ignition
sudo coreos-installer install ${COREOS_INSTALL_DEV} --insecure-ignition --ignition-url=http://${BASTION_IP}:8080/pre/append-${HOSTNAME}.ign --insecure-ignition --firstboot-args 'rd.neednet=1' --copy-network
EOF

    # Check if the setup script file was successfully generated
    if [ -f "${IGNITION_PATH}/set-${HOSTNAME}.sh" ]; then
        echo -e "${GREEN}ok: [generate setup script: ${IGNITION_PATH}/set-${HOSTNAME}.sh]"
    else
        echo -e "${RED}failed: [generate setup script for ${HOSTNAME}"
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
chmod +x ${IGNITION_PATH}/*.sh
run_command "[change ignition file permissions]"

# Add an empty line after the task
echo
# ====================================================
