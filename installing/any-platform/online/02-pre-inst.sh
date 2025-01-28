#!/bin/bash
set -u

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

# Applying environment variables
source 01-set-params.sh


# === Task: Changing the hostname and time zone ===
PRINT_TASK "[TASK: Changing the hostname and time zone]"

# Change hostname
sudo hostnamectl set-hostname ${BASTION_HOSTNAME}
run_command "[change hostname to ${BASTION_HOSTNAME}]"

# Change time zone to UTC
sudo timedatectl set-timezone UTC
run_command "[change time zone to UTC]"

# Write LANG=en_US.UTF-8 to the ./bash_profile file]
echo 'export LANG=en_US.UTF-8' >> ~/.bash_profile
run_command "[write LANG=en_US.UTF-8 to the ./bash_profile file]"

# Reload ~/.bash_profile
source ~/.bash_profile
run_command "[reload ~/.bash_profile]"

# Add an empty line after the task
echo

# === Task: Disable and stop firewalld service ===
PRINT_TASK "[TASK: Disable and stop firewalld service]"

# Stop and disable firewalld services
sudo systemctl disable --now firewalld &> /dev/null
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
    echo "ok: [selinux permanent security policy changed to $permanent_status]"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo "ok: [selinux permanent security policy is $permanent_status]"
else
    echo "failed: [selinux permanent security policy is $permanent_status]"
fi


# Temporarily set SELinux security policy to permissive
sudo setenforce 0 &>/dev/null
# Check temporary SELinux security policy
temporary_status=$(getenforce)
# Check if temporary SELinux security policy is permissive or disabled
if [[ $temporary_status == "Permissive" || $temporary_status == "Disabled" ]]; then
    echo "ok: [selinux temporary security policy is $temporary_status]"
else
    echo "failed: [selinux temporary security policy is $temporary_status (expected Permissive or Disabled)]"
fi

# Add an empty line after the task
echo
# ====================================================


# === Task: Install the necessary rpm packages ===
PRINT_TASK "[TASK: Install the necessary rpm packages]"

# List of RPM packages to install
packages=("wget" "net-tools" "vim-enhanced" "podman" "bind-utils" "bind" "haproxy" "git" "bash-completion" "jq" "nfs-utils" "httpd" "httpd-tools" "skopeo" "conmon" "httpd-manual")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
sudo dnf install -y $package_list &>/dev/null

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [installed $package package]"
    else
        echo "failed: [installed $package package]"
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
run_command "[download openshift-install tool]"

rm -f /usr/local/bin/openshift-install &> /dev/null
tar -xzf "openshift-install-linux.tar.gz" -C "/usr/local/bin/" &> /dev/null
run_command "[install openshift-install tool]"

chmod +x /usr/local/bin/openshift-install &> /dev/null
run_command "[modify /usr/local/bin/openshift-install permissions]"

rm -rf openshift-install-linux.tar.gz &> /dev/null

# Step 2: Download the oc cli
# ----------------------------------------------------
# Delete the old version of oc cli
sudo rm -f /usr/local/bin/oc &> /dev/null
sudo rm -f /usr/local/bin/kubectl &> /dev/null
sudo rm -f /usr/local/bin/README.md &> /dev/null
sudo rm -f /usr/local/bin/kubectx &> /dev/null
sudo rm -f /usr/local/bin/kubens &> /dev/null

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
run_command "[download OpenShift client tool]"

# Extract the downloaded tarball to /usr/local/bin/
sudo tar -xzf "$openshift_client" -C "/usr/local/bin/" &> /dev/null
run_command "[install openshift client tool]"

sudo chmod +x /usr/local/bin/oc &> /dev/null
run_command "[modify /usr/local/bin/oc permissions]"

sudo chmod +x /usr/local/bin/kubectl &> /dev/null
run_command "[modify /usr/local/bin/kubectl permissions]"

sudo rm -f /usr/local/bin/README.md &> /dev/null
sudo rm -rf $openshift_client &> /dev/null

sudo curl -sLo /usr/local/bin/kubectx https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx &> /dev/null
run_command "[install kubectx tool]"

sudo curl -sLo /usr/local/bin/kubens https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens &> /dev/null
run_command "[install kubens tool]"

sudo chmod +x /usr/local/bin/kubectx &> /dev/null
run_command "[modify /usr/local/bin/kubectx permissions]"

sudo chmod +x /usr/local/bin/kubens &> /dev/null
run_command "[modify /usr/local/bin/kubens permissions]"

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
        echo "ok: [change http listening port to 8080]"
    else
        echo "skipping: [http listen port is already 8080]"
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
mkdir -p ${HTTPD_DIR} &> /dev/null
run_command "[create http: ${HTTPD_DIR} director]"


# Step 3: Enable and Restart httpd service
# ----------------------------------------------------
# Enable and start service
systemctl enable --now httpd &> /dev/null
run_command "[restart and enable httpd service]"

# Wait for the service to restart
sleep 3


# Step 4: Test
# ----------------------------------------------------
# Test httpd configuration
touch ${HTTPD_DIR}/httpd-test  &> /dev/null
run_command "[create httpd test file]"

wget -q http://${BASTION_IP}:8080/httpd-test
run_command "[test httpd download function]"

rm -rf httpd-test ${HTTPD_DIR}/httpd-test  &> /dev/null
run_command "[delete the httpd test file]"

# Add an empty line after the task
echo
# ====================================================



# === Task: Setup nfs services ===
PRINT_TASK "[TASK: Setup nfs services]"

# Step 1: Create directory /user and change permissions and add NFS export
# ----------------------------------------------------
# Create NFS directories
rm -rf ${NFS_DIR} &> /dev/null
mkdir -p ${NFS_DIR}/${IMAGE_REGISTRY_PV} &> /dev/null
run_command "[create nfs director: ${NFS_DIR}]"


# Add nfsnobody user if not exists
if id "nfsnobody" &>/dev/null; then
    echo "skipping: [nfsnobody user exists]"
else
    useradd nfsnobody
    echo "ok: [add nfsnobody user]"
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_DIR} &> /dev/null
run_command "[changing ownership of an NFS directory]"

chmod -R 777 ${NFS_DIR} &> /dev/null
run_command "[change NFS directory permissions]"


# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "skipping: [nfs export configuration already exists]"
else
    echo "$export_config_line" >> "/etc/exports"
    echo "ok: [add nfs export configuration]"
fi


# Step 2: Enable and Restart nfs-server service
# ----------------------------------------------------
# Enable and start service
sudo systemctl enable --now nfs-server &> /dev/null
run_command "[restart and enable nfs-server service]"

# Wait for the service to restart
sleep 3

# Step 3: Test
# ----------------------------------------------------
# Function to check if NFS share is accessible

# Create the mount point
sudo mkdir -p /tmp/nfs-test &> /dev/null
run_command "[create an nfs mount directory for testing: /tmp/nfs-test]"

# Attempt to mount the NFS share
sudo mount -t nfs ${NFS_SERVER_IP}:${NFS_DIR} /tmp/nfs-test &> /dev/null
run_command "[test mounts the nfs shared directory: /tmp/nfs-test]"

# Unmount the NFS share
sudo fuser -km /tmp/nfs-test &> /dev/null
sudo umount /tmp/nfs-test &> /dev/null
run_command "[unmount the nfs shared directory: /tmp/nfs-test]"

# Delete /tmp/nfs-test
sudo rm -rf /tmp/nfs-test &> /dev/null
run_command "[delete the test mounted nfs directory: /tmp/nfs-test]"

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
    echo "ok: [generate named configuration file]"
else
    echo "failed: [generate named configuration file]"
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
    echo "ok: [generate forward DNS zone file: /var/named/${FORWARD_ZONE_FILE}]"
else
    echo "failed: [generate forward DNS zone file]"
fi


# Step 4: Create reverse zone file
# ----------------------------------------------------
#!/bin/bash
# Clean up: Delete duplicate file
rm -f /var/named/${REVERSE_ZONE_FILE} &> /dev/null

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


# Step 5: Check named configuration/Dns file 
# ----------------------------------------------------
# Check named configuration file
if named-checkconf &>/dev/null; then
    echo "ok: [named configuration is valid]"
else
    echo "failed: [Named configuration is invalid]"
fi

# Check forward zone file
if named-checkzone ${FORWARD_ZONE_FILE} /var/named/${FORWARD_ZONE_FILE} &>/dev/null; then
    echo "ok: [forward zone file is valid]"
else
    echo "failed: [forward zone file is invalid]"
fi

# Check reverse zone file
if named-checkzone ${REVERSE_ZONE_FILE} /var/named/${REVERSE_ZONE_FILE} &>/dev/null; then
    echo "ok: [reverse zone file is valid]"
else
    echo "failed: [reverse zone file is invalid]"
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
systemctl enable --now named  &> /dev/null
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
    echo "ok: [generate haproxy configuration file]"
else
    echo "failed: [generate haproxy configuration file]"
fi


# Step 2: Check haproxy configuration
# ----------------------------------------------------
# Path to HAProxy configuration file
CONFIG_FILE="/etc/haproxy/haproxy.cfg"

# Check HAProxy configuration syntax
check_haproxy_config() {
    haproxy -c -f "$CONFIG_FILE" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [haproxy configuration is valid]"
    else
        echo "failed: [haproxy configuration is invalid]"
    fi
}

# Call the function to check HAProxy configuration
check_haproxy_config


# Step 3: Enable and Restart haproxy service
# ----------------------------------------------------
# List of services to handle
# Enable and start service
systemctl enable --now haproxy &> /dev/null
run_command "[restart and enable haproxy service]"

# Add an empty line after the task
echo
# ====================================================


# Task: Generate a defined install-config file
PRINT_TASK "[TASK: Generate a defined install-config file]"

# Create ssh-key for accessing CoreOS
rm -rf ${SSH_KEY_PATH} &> /dev/null
ssh-keygen -N '' -f ${SSH_KEY_PATH}/id_rsa &> /dev/null
run_command "[create ssh-key for accessing coreos]"

# Define variables
export SSH_PUB_STR="$(cat ${SSH_KEY_PATH}/id_rsa.pub)"

# Generate a defined install-config file
rm -rf ${HTTPD_DIR}/install-config.yaml &> /dev/null

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
# ====================================================


# Task:  Generate a manifests
PRINT_TASK "[TASK: Generate a manifests]"

# Create installation directory
rm -rf "${INSTALL_DIR}" &> /dev/null
mkdir -p "${INSTALL_DIR}" &> /dev/null
run_command "[create installation directory: ${INSTALL_DIR}]"

# Copy install-config.yaml to installation directory
cp "${HTTPD_DIR}/install-config.yaml" "${INSTALL_DIR}"
run_command "[copy the install-config.yaml file to the installation directory]"

# Generate manifests
/usr/local/bin/openshift-install create manifests --dir "${INSTALL_DIR}" &> /dev/null
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
# ====================================================


# Task: Generate default ignition file
PRINT_TASK "[TASK: Generate default ignition file]"

# Generate and modify ignition configuration files
/usr/local/bin/openshift-install create ignition-configs --dir "${INSTALL_DIR}" &> /dev/null
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
# ====================================================


# Task: Generate setup script file
PRINT_TASK "[TASK: Generate setup script file]"

rm -rf ${INSTALL_DIR}/*.sh

# Function to generate setup script for a node
generate_setup_script() {
    local HOSTNAME=$1
    local IP_ADDRESS=$2

# Generate a setup script for the node
cat << EOF > "${INSTALL_DIR}/inst-${HOSTNAME}.sh"
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
    if [ -f "${INSTALL_DIR}/inst-${HOSTNAME}.sh" ]; then
        echo "ok: [generate setup script: ${INSTALL_DIR}/inst-${HOSTNAME}.sh]"
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
# ====================================================

# Task: Generate approve csr script file
PRINT_TASK "[TASK: Generate approve csr script file]"

rm -rf "${INSTALL_DIR}/approve-csr.sh"
cat << EOF > "${INSTALL_DIR}/ocp4cert_approver.sh"
#!/bin/bash
export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig

for i in {1..720}; do 
  oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
  sleep 10
done 
EOF
run_command "[Generate approve csr script file]"

# Add an empty line after the task
echo
# ====================================================
