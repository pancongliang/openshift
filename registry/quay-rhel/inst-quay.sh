#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export QUAY_DOMAIN='quay-server.example.com'
export QUAY_HOST_IP="10.184.134.128"
export QUAY_SUPER_USERS="quayadmin"
export QUAY_INST_DIR="/opt/quay-inst"

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
PRINT_TASK "TASK [Install infrastructure rpm]"

# List of RPM packages to install
packages=("podman")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
sudo dnf install -y $package_list >/dev/null 2>&1

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "ok: [Installed $package package]"
    else
        echo "failed: [Installed $package package]"
    fi
done

# Add an empty line after the task
echo


# Step 2:
PRINT_TASK "TASK [Delete existing duplicate data]"

# Function to remove a container with formatted output
remove_container() {
    local container_name="$1"
    if sudo podman container exists "$container_name"; then
        if sudo podman rm -f "$container_name" >/dev/null 2>&1; then
            echo "ok: [Container '$container_name' removed]"
        else
            echo "failed: [Container '$container_name' removed]"
        fi
    else
        echo "skipping: [Container '$container_name' removed]"
    fi
}

# Function to remove a directory with formatted output
remove_directory() {
    local dir_path="$1"
    if [ -d "$dir_path" ]; then
        if sudo rm -rf "$dir_path" >/dev/null 2>&1; then
            echo "ok: [Quay install directory '$dir_path' removed]"
        else
            echo "failed: [Quay install directory '$dir_path' removed]"
        fi
    else
        echo "skipping: [Quay install directory '$dir_path' removed]"
    fi
}

# Begin cleanup
remove_container "postgresql-quay"
remove_container "quay"
remove_container "redis"
remove_directory "$QUAY_INST_DIR"

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Install quay registry]"

# Add registry entry to /etc/hosts
if ! grep -q "$REGISTRY_DOMAIN_NAME" /etc/hosts; then
  echo "# Add registry entry to /etc/hosts" | sudo tee -a /etc/hosts > /dev/null
  echo "$QUAY_HOST_IP $QUAY_DOMAIN" | sudo tee -a /etc/hosts > /dev/null
  echo "ok: [Add registry entry to /etc/hosts]"
else
  echo "skipping: [Registry entry already exists in /etc/hosts]"
fi

# Create a database data directory
mkdir -p $QUAY_INST_DIR/postgres-quay
run_command "[Create a database data directory]"


# Set the appropriate permissions
setfacl -mu:26:-wx $QUAY_INST_DIR/postgres-quay
run_command "[Set the appropriate permissions]"

Create a database data directory
# Start the Postgres container
sudo podman run -d --rm --name postgresql-quay \
  -e POSTGRESQL_USER=quayuser \
  -e POSTGRESQL_PASSWORD=quaypass \
  -e POSTGRESQL_DATABASE=quay \
  -e POSTGRESQL_ADMIN_PASSWORD=adminpass \
  -p 5432:5432 \
  -v $QUAY_INST_DIR/postgres-quay:/var/lib/pgsql/data:Z \
  registry.redhat.io/rhel8/postgresql-13
run_command "[Create a database data directory]"


# Ensure that the Postgres pg_trgm module is installed
sudo podman exec -it postgresql-quay /bin/bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U postgres'
run_command "[Ensure that the Postgres pg_trgm module is installed]"

# Start the Redis container
sudo podman run -d --rm --name redis -p 6379:6379 -e REDIS_PASSWORD=strongpassword registry.redhat.io/rhel8/redis-6:1-110
run_command "[Start the Redis container]"

# Create a local directory to store the Quay configuration .yaml
mkdir $QUAY_INST_DIR/config
run_command "[Create a local directory to store the Quay configuration .yaml]"

# Create a minimal config.yaml file that is used to deploy the Red Hat Quay container
cat > $QUAY_INST_DIR/config/config.yaml << EOF
BUILDLOGS_REDIS:
    host: $QUAY_DOMAIN
    password: strongpassword
    port: 6379
CREATE_NAMESPACE_ON_PUSH: true
DATABASE_SECRET_KEY: a8c2744b-7004-4af2-bcee-e417e7bdd235
DB_URI: postgresql://quayuser:quaypass@$QUAY_DOMAIN:5432/quay
DISTRIBUTED_STORAGE_CONFIG:
    default:
        - LocalStorage
        - storage_path: /datastorage/registry
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
    - default
FEATURE_MAILING: false
SECRET_KEY: e9bd34f4-900c-436a-979e-7530e5d74ac8
SERVER_HOSTNAME: $QUAY_DOMAIN
SETUP_COMPLETE: true
SUPER_USERS:
  - $QUAY_SUPER_USERS
USER_EVENTS_REDIS:
    host: $QUAY_DOMAIN
    password: strongpassword
    port: 6379
EOF
run_command "[Create a minimal config.yaml file that is used to deploy the Red Hat Quay container]"


# Create a local directory that will store registry images
mkdir $QUAY_INST_DIR/storage
run_command "[Create a local directory that will store registry images]"

# Set the directory to store registry images
setfacl -m u:1001:-wx $QUAY_INST_DIR/storage
run_command "[Set the directory to store registry images]"

# Deploy the Red Hat Quay registry 
sudo podman run -d --rm -p 80:8080 -p 443:8443 --name=quay \
   -v $QUAY_INST_DIR/config:/conf/stack:Z \
   -v $QUAY_INST_DIR/storage:/datastorage:Z \
   registry.redhat.io/quay/quay-rhel8:v3.15.0
run_command "[Deploy the Red Hat Quay registry ]"
