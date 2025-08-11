
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
PRINT_TASK "TASK [Kubeconfig login and oc completion]"

# kubeconfig login:
rm -rf ${INSTALL_DIR}/auth/kubeconfigbk >/dev/null 2>&1
cp ${INSTALL_DIR}/auth/kubeconfig ${INSTALL_DIR}/auth/kubeconfigbk >/dev/null 2>&1
grep -q "^export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" ~/.bash_profile || echo "export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig" >> ~/.bash_profile
run_command "[Add kubeconfig to ~/.bash_profile]"

# completion command:
bash -c '/usr/local/bin/oc completion bash >> /etc/bash_completion.d/oc_completion' || true
run_command "[Enable oc bash completion]"

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Configure data persistence for the image-registry operator]"

rm -rf ${NFS_DIR}/${IMAGE_REGISTRY_PV} >/dev/null 2>&1
mkdir -p ${NFS_DIR}/${IMAGE_REGISTRY_PV} >/dev/null 2>&1
run_command "[Create ${NFS_DIR}/${IMAGE_REGISTRY_PV} director]"

chmod 777 ${NFS_DIR}/${IMAGE_REGISTRY_PV} >/dev/null 2>&1
run_command "[Set permissions on ${NFS_DIR}/${IMAGE_REGISTRY_PV}]"

/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig delete -f ${IMAGE_REGISTRY_PV} >/dev/null 2>&1 || true

cat << EOF > /tmp/${IMAGE_REGISTRY_PV}.yaml
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
run_command "[Generate ${IMAGE_REGISTRY_PV}.yaml configuration file]"

/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig apply -f /tmp/${IMAGE_REGISTRY_PV}.yaml >/dev/null 2>&1
run_command "[Apply ${IMAGE_REGISTRY_PV} persistent volume]"

rm -f /tmp/${IMAGE_REGISTRY_PV}.yaml
run_command "[Remove temporary ${IMAGE_REGISTRY_PV}.yaml file]"

# Change the Image registry operator configuration’s managementState from Removed to Managed
/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}' >/dev/null 2>&1
run_command "[Set Image Registry operator management state to Managed]"

# Leave the claim field blank to allow the automatic creation of an image-registry-storage PVC.
/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}' >/dev/null 2>&1
run_command "[Clear PVC claim field to enable automatic storage provisioning]"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Disable default OperatorHub sources]"

# Disabling the default OperatorHub sources
/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]' >/dev/null 2>&1
run_command "[Disable default OperatorHub sources]"

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Create htpasswd User]"

rm -rf $INSTALL_DIR/users.htpasswd
htpasswd -c -B -b $INSTALL_DIR/users.htpasswd admin redhat >/dev/null 2>&1
run_command "[Create user with htpasswd tool]"

/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig delete secret htpasswd-secret -n openshift-config >/dev/null 2>&1 || true
/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig create secret generic htpasswd-secret --from-file=htpasswd=$INSTALL_DIR/users.htpasswd -n openshift-config >/dev/null 2>&1
run_command "[Create secret from users.htpasswd file]"

rm -rf $INSTALL_DIR/users.htpasswd

# Use a here document to apply OAuth configuration to the OpenShift cluster
cat  <<EOF | /usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig apply -f - >/dev/null 2>&1
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
run_command "[Configure htpasswd authentication]"

# Grant the 'cluster-admin' cluster role to the user 'admin'
/usr/local/bin/oc --kubeconfig=${INSTALL_DIR}/auth/kubeconfig adm policy add-cluster-role-to-user cluster-admin admin >/dev/null 2>&1 || true
run_command "[Grant cluster-admin role to admin user]"

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
            echo -n "info: [Waiting for pods to reach 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Max retries reached; oauth pods may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All oauth pods are in 'Running' state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Check cluster status]"

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
            echo -n "info: [Waiting for all cluster operators to reach desired state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Max retries reached; cluster operators may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All cluster operators have reached desired state]"
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
            echo -n "info: [Waiting for all MCPs to reach desired state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Max retries reached; MCPs may still be initializing]"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All MCPs have reached desired state]"
        break
    fi
done

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Login cluster information]"

# Change the root password to 'redhat' on each node
nodes=$(oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')
for node in $nodes; do
  ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@"$node" \
    "echo 'root:redhat' | sudo chpasswd || true" >/dev/null 2>&1
done
echo "ok: [Changed root password to 'redhat' on all nodes]"

echo "info: [Default login uses kubeconfig]"
echo "info: [Login using htpasswd user: uset KUBECONFIG && oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]"
echo
