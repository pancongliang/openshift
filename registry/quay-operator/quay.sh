#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Default storage class name
# oc patch storageclass <SC_NAME> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
export DEFAULT_STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

# Set environment variables
export SUB_CHANNEL="stable-3.15"
export CATALOG_SOURCE="redhat-operators"
export NAMESPACE="quay-enterprise"
export REGISTRY_ID="quayadmin"
export REGISTRY_PW="password"
export OBJECTSTORAGE_MANAGED="false"     # If there is MCG/ODF object storage: true, otherwise false
export INTERNAL_POSTGRESQL="true"        # Set to true if PostgreSQL is provisioned by the operator, otherwise false
export OCP_TRUSTED_CA="fasle"            # OCP trust Quay: true, otherwise false

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
PRINT_TASK "TASK [Uninstall old quay resources]"

# Delete custom resources
if oc get quayregistry example-registry -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "$INFO_MSG Deleting QuayRegistry example-registry..."
    oc delete quayregistry example-registry -n "$NAMESPACE" >/dev/null 2>&1
else
    echo -e "$INFO_MSG QuayRegistry does not exist"
fi

oc delete secret quay-config -n $NAMESPACE >/dev/null 2>&1 || true
oc delete subscription quay-operator -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep quay-operator | awk -F/ '{print $2}'  | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true
oc get ip -n openshift-operators --no-headers 2>/dev/null|grep quay-operator|awk '{print $1}'|xargs -r oc delete ip -n openshift-operators >/dev/null 2>&1 || true
timeout 2s oc delete pod -n $NAMESPACE --all --force >/dev/null 2>&1 || true
timeout 2s oc delete pvc -n $NAMESPACE --all --force >/dev/null 2>&1 || true


if oc get ns $NAMESPACE >/dev/null 2>&1; then
   echo -e "$INFO_MSG Deleting quay operator..."
   echo -e "$INFO_MSG Deleting $NAMESPACE project..."
   oc delete ns $NAMESPACE >/dev/null 2>&1
else
   echo -e "$INFO_MSG The $NAMESPACE project does not exist"
fi

if oc get ns quay-postgresql >/dev/null 2>&1; then
   echo -e "$INFO_MSG Deleting quay-postgresql project..."
   oc delete ns quay-postgresql >/dev/null 2>&1 || true
fi

# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Check the default storage class]"

# Check if Default StorageClass exists
DEFAULT_STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    echo -e "$FAIL_MSG No default StorageClass found!"
    exit 1
else
    echo -e "$INFO_MSG Default StorageClass found: $DEFAULT_STORAGE_CLASS"
fi

# Add an empty line after the task
echo

# Step 2:
# Deploying Minio Object Storage

# Only run this block if OBJECTSTORAGE_MANAGED is false
if [[ "$OBJECTSTORAGE_MANAGED" == "false" ]]; then
    # Check if the Minio Pod exists and is running.
    MINIO_POD=$(oc get pod -n "minio" -l app=minio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -n "$MINIO_POD" ]]; then
        POD_STATUS=$(oc get pod "$MINIO_POD" -n "minio" -o jsonpath='{.status.phase}')
    else
        POD_STATUS=""
    fi

    # Check if the bucket exists
    BUCKET_NAME="quay-bucket"
    export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}' 2>/dev/null || true)

    BUCKET_EXISTS=false
    if [[ -n "$MINIO_POD" ]] && [[ "$POD_STATUS" == "Running" ]]; then
        oc exec -n "minio" "$MINIO_POD" -- mc alias set my-minio "${BUCKET_HOST}" minioadmin minioadmin >/dev/null 2>&1 || true
        if oc exec -n "minio" "$MINIO_POD" -- mc ls my-minio 2>/dev/null | grep -q "$BUCKET_NAME"; then
           BUCKET_EXISTS=true
        fi
    fi

    # Determine whether to perform deployment
    if [[ -n "$MINIO_POD" ]] && [[ "$POD_STATUS" == "Running" ]] && [[ "$BUCKET_EXISTS" == true ]]; then
        PRINT_TASK "TASK [Deploying Minio Object Storage]"
        echo -e "$INFO_MSG Minio already exists and bucket exists, skipping deployment"
        # Add an empty line after the task
        echo
    else
        curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/minio/minio.sh | sh
        # Add an empty line after the task
        echo
    fi

fi

# Step 3:
PRINT_TASK "TASK [Deploying Quay Operator]"

# Create a Subscription
export OPERATOR_NS=openshift-operators
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/quay-operator.openshift-operators: ""
  name: quay-operator
  namespace: openshift-operators
spec:
  channel: ${SUB_CHANNEL}
  installPlanApproval: "Manual"
  name: quay-operator
  source: $CATALOG_SOURCE
  sourceNamespace: openshift-marketplace
EOF
run_command "Installing quay operator..."

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=openshift-operators

MSG="Waiting for unapproved install plans in namespace $OPERATOR_NS"
while true; do
    # Get unapproved InstallPlans
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)

    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true

        # Overwrite previous INFO line with final approved message
        printf "\r$INFO_MSG Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r$FAIL_MSG The %s namespace has no unapproved install plans%*s\n" \
               "$OPERATOR_NS" $((LINE_WIDTH - ${#OPERATOR_NS} - 45)) ""
        break
    fi
done

sleep 5

# Stage 2: Quickly approve all remaining unapproved InstallPlans
while true; do
    # Get all unapproved InstallPlans; if none exist, exit the loop
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)
    if [[ -z "$INSTALLPLAN" ]]; then
        break
    fi
    # Loop through and approve each InstallPlan
    for NAME in $INSTALLPLAN; do
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true
        printf "\r$INFO_MSG Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
    done
    # Slight delay to avoid excessive polling
    sleep "$SLEEP_INTERVAL"
done

sleep 10

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=90                # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=$OPERATOR_NS
pod_name=quay-operator

while true; do
    # 1. Capture the Ready status column (e.g., "1/1", "0/2") for pods matching the name
    RAW_STATUS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # 2. Logic to determine if pods are ready
    if [[ -z "$RAW_STATUS" ]]; then
        # If RAW_STATUS is empty, it means no pods were found
        is_ready=false
    else
        # Check if any pod has 'ready' count not equal to 'total' count
        not_ready_count=$(echo "$RAW_STATUS" | awk -F/ '$1 != $2' | wc -l)
        if [[ $not_ready_count -eq 0 ]]; then
            is_ready=true
        else
            is_ready=false
        fi
    fi

    # 3. Handle UI output and loop control
    if $is_ready; then
        # Successfully running
        if $progress_started; then
            printf "\r$INFO_MSG The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "$INFO_MSG The $pod_name pods are Running"
        fi
        break
    else
        # Still waiting or pod not found yet
        CHAR=${SPINNER[$((retry_count % 4))]}
        # Provide different messages if pods are missing vs. starting
        MSG="Waiting for $pod_name pods to be Running..."
        [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."

        if ! $progress_started; then
            printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
        fi

        # 4. Retry management
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG The %s pods are not Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
            exit 1
        fi
    fi
done

# If INTERNAL_POSTGRESQL == "false", create external PostgreSQL
if [[ "$INTERNAL_POSTGRESQL" == "false" ]]; then
    # Create namespace for external PostgreSQL
    oc new-project quay-postgresql >/dev/null 2>&1
    run_command "Create quay-postgresql namespace"

    # Deploy PostgreSQL
    oc -n quay-postgresql new-app registry.redhat.io/rhel8/postgresql-13 \
      --name=quay-postgresql \
      -e POSTGRESQL_USER=quayuser \
      -e POSTGRESQL_PASSWORD=quaypass \
      -e POSTGRESQL_DATABASE=quay \
      -e POSTGRESQL_ADMIN_PASSWORD=adminpass >/dev/null 2>&1
    run_command "Create Postgres pod"

    # Add persistent volume
    oc -n quay-postgresql set volumes deployment/quay-postgresql \
      --add --name postgresql-data \
      --type pvc \
      --claim-mode RWO \
      --claim-size 5Gi \
      --mount-path /var/lib/pgsql/data \
      --claim-name postgresql-pvc >/dev/null 2>&1
    run_command "Create persistent volume for Postgres pod"

    # Wait for $pod_name pods to be in Running state
    MAX_RETRIES=90                # Maximum number of retries
    SLEEP_INTERVAL=2              # Sleep interval in seconds
    LINE_WIDTH=120                # Control line width
    SPINNER=('/' '-' '\' '|')     # Spinner animation characters
    retry_count=0                 # Number of status check attempts
    progress_started=false        # Tracks whether the spinner/progress line has been started
    project=quay-postgresql
    pod_name=quay-postgresql
    
    while true; do
        # 1. Capture the Ready status column (e.g., "1/1", "0/2") for pods matching the name
        RAW_STATUS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)
    
        # 2. Logic to determine if pods are ready
        if [[ -z "$RAW_STATUS" ]]; then
            # If RAW_STATUS is empty, it means no pods were found
            is_ready=false
        else
            # Check if any pod has 'ready' count not equal to 'total' count
            not_ready_count=$(echo "$RAW_STATUS" | awk -F/ '$1 != $2' | wc -l)
            if [[ $not_ready_count -eq 0 ]]; then
                is_ready=true
            else
                is_ready=false
            fi
        fi
    
        # 3. Handle UI output and loop control
        if $is_ready; then
            # Successfully running
            if $progress_started; then
                printf "\r$INFO_MSG The %s pods are Running%*s\n" \
                       "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
            else
                echo -e "$INFO_MSG The $pod_name pods are Running"
            fi
            break
        else
            # Still waiting or pod not found yet
            CHAR=${SPINNER[$((retry_count % 4))]}
            # Provide different messages if pods are missing vs. starting
            MSG="Waiting for $pod_name pods to be Running..."
            [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."
    
            if ! $progress_started; then
                printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
                progress_started=true
            else
                printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
            fi
    
            # 4. Retry management
            sleep "$SLEEP_INTERVAL"
            retry_count=$((retry_count + 1))
    
            if [[ $retry_count -ge $MAX_RETRIES ]]; then
                printf "\r$FAIL_MSG The %s pods are not Running%*s\n" \
                       "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
                exit 1
            fi
        fi
    done

    # Get PostgreSQL host
    #oc -n quay-postgresql expose svc quay-postgresql 
    #PG_HOST=$(oc get route quay-postgresql -n quay-postgresql -o jsonpath='{.spec.host}' 2>/dev/null)

    sleep 30

    # Enable pg_trgm extension
    oc exec -n quay-postgresql deployment/quay-postgresql -- bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U postgres' >/dev/null 2>&1
    run_command "Enable pg_trgm module in quay-postgresql"
fi

## Backup postgresql
## oc exec -n quay-postgresql deployment/quay-postgresql -- /usr/bin/pg_dump -C quay  > backup.sql
# 
# or
#export QUAY_INST_DIR="/opt/quay-inst"
#mkdir -p $QUAY_INST_DIR/postgres-quay
#setfacl -mu:26:-wx $QUAY_INST_DIR/postgres-quay 
#podman run -d --name quay-postgresql \
#  --restart=always \
#  -e POSTGRESQL_USER=quayuser \
#  -e POSTGRESQL_PASSWORD=quaypass \
#  -e POSTGRESQL_DATABASE=quay \
#  -e POSTGRESQL_ADMIN_PASSWORD=adminpass \
#  -p 5432:5432 \
#  -v $QUAY_INST_DIR/postgres-quay:/var/lib/pgsql/data:Z \
#  registry.redhat.io/rhel8/postgresql-13 
#sleep 15
#podman exec -it quay-postgresql /bin/bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U postgres' 
#podman generate systemd --name quay-postgresql --files --restart-policy=always
#mv container-*.service /etc/systemd/system/
#systemctl enable --now container-quay-postgresql.service
#HOST_IP=xxx

# Create a namespace
oc new-project $NAMESPACE >/dev/null 2>&1
run_command "Create a $NAMESPACE namespace"

# Create a quay config
rm -rf config.yaml

# Using managed object storage
if [ "$OBJECTSTORAGE_MANAGED" == "true" ]; then
    cat > config.yaml <<EOF
FEATURE_USER_INITIALIZE: true
SUPER_USERS:
    - $REGISTRY_ID
DEFAULT_TAG_EXPIRATION: 1m
TAG_EXPIRATION_OPTIONS:
    - 1m
EOF
run_command "Create a quay config file"

    # Add DB_URI if insternal_postgresql is false
    if [ "$INTERNAL_POSTGRESQL" == "false" ]; then
        echo "DB_URI: postgresql://quayuser:quaypass@quay-postgresql.quay-postgresql.svc:5432/quay" >> config.yaml
    fi

# Using MinIO
elif [ "$OBJECTSTORAGE_MANAGED" == "false" ]; then
    export ACCESS_KEY_ID="minioadmin"
    export ACCESS_KEY_SECRET="minioadmin"
    export BUCKET_NAME="quay-bucket"
    export MINIO_HOST=$(oc get route minio -n minio -o jsonpath='{.spec.host}')
    
    cat > config.yaml <<EOF
DISTRIBUTED_STORAGE_CONFIG:
  default:
    - RadosGWStorage
    - access_key: ${ACCESS_KEY_ID}
      secret_key: ${ACCESS_KEY_SECRET}
      bucket_name: ${BUCKET_NAME}
      hostname: ${MINIO_HOST}
      is_secure: false
      port: 80
      storage_path: /
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
    - default
FEATURE_USER_INITIALIZE: true
SUPER_USERS:
    - $REGISTRY_ID
DEFAULT_TAG_EXPIRATION: 1m
TAG_EXPIRATION_OPTIONS:
    - 1m
EOF
run_command "Create a quay config file"
    # Add DB_URI if insternal_postgresql is false
    if [ "$INTERNAL_POSTGRESQL" == "false" ]; then
        echo "DB_URI: postgresql://quayuser:quaypass@quay-postgresql.quay-postgresql.svc:5432/quay" >> config.yaml
    fi
fi

# If using an external PostgreSQL instance, add the DB_URI to the config.yaml file in the following format.
#DB_URI: postgresql://quayuser:quaypass@${PG_HOST}:5432/quay
#DB_URI: postgresql://quayuser:quaypass@${HOST_IP}:5432/quay


sleep 10

# Create a secret containing the quay config
oc create secret generic quay-config --from-file=config.yaml -n $NAMESPACE >/dev/null 2>&1
run_command "Create a secret containing quay-config"

rm -rf config.yaml >/dev/null 2>&1

# Create a Quay Registry
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: quay.redhat.com/v1
kind: QuayRegistry
metadata:
  name: example-registry
  namespace: $NAMESPACE
spec:
  configBundleSecret: quay-config
  components:
    - kind: objectstorage
      managed: $OBJECTSTORAGE_MANAGED
    - kind: horizontalpodautoscaler
      managed: false
    - kind: quay
      managed: true
      overrides:
        replicas: 1
    - kind: clair
      managed: true
      overrides:
        replicas: 1
    - kind: mirror
      managed: true
      overrides:
        replicas: 1
    - kind: postgres
      managed: ${INTERNAL_POSTGRESQL}
EOF
run_command "Creating a quay registry..."

sleep 30

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=300              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=$NAMESPACE

while true; do
    # 1. Get the READY column for all pods, excluding Completed ones
    POD_STATUS_LIST=$(oc -n "$namespace" get po --no-headers 2>/dev/null | grep -v "Completed" | awk '{print $2}' || true)

    # 2. Check if any pods exist and if they are all ready
    if [[ -n "$POD_STATUS_LIST" ]]; then
        # Check for pods where Ready count (left) is not equal to Total count (right)
        not_ready_exists=$(echo "$POD_STATUS_LIST" | awk -F/ '$1 != $2')
        
        if [[ -z "$not_ready_exists" ]]; then
            # SUCCESS: Pods exist AND all of them are ready
            if $progress_started; then
                printf "\r$INFO_MSG All %s namespace pods are Running%*s\n" \
                       "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
            else
                echo -e "$INFO_MSG All $namespace namespace pods are Running"
            fi
            break
        fi
    fi

    # 3. If we reach here, either no pods exist yet or some are not ready
    CHAR=${SPINNER[$((retry_count % 4))]}
    
    # Define feedback message based on whether pods are missing or starting
    MSG="Waiting for $namespace namespace pods to be Running..."
    [[ -z "$POD_STATUS_LIST" ]] && MSG="Waiting for $namespace pods to be created..."

    if ! $progress_started; then
        printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
    fi

    # 4. Handle timeout and retry
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r$FAIL_MSG The %s namespace pods are not Running%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 45)) ""
        exit 1
    fi
done

# Get the Quay route host for the given namespace and store in QUAY_HOST
export QUAY_HOST=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}') >/dev/null 2>&1

# Maximum number of retries and sleep interval
MAX_RETRIES=60
SLEEP_INTERVAL=2
LINE_WIDTH=120                 # Width for progress line formatting
SPINNER=('/' '-' '\' '|')      # Spinner animation characters
retry_count=0
progress_started=false

while true; do
    # Attempt to access the Quay user initialize API
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" \
                "https://$QUAY_HOST/api/v1/user/initialize" || true)

    # If HTTP code is 2xx/3xx/4xx, the API is considered available
    if [[ "$HTTP_CODE" =~ ^2|3|4$ ]]; then
        if $progress_started; then
            printf "\r$INFO_MSG Quay API is available%*s\n" $((LINE_WIDTH - 22)) ""
        else
            echo -e "$INFO_MSG Quay API is available"
        fi
        break
    fi

    # Display progress spinner while waiting
    CHAR=${SPINNER[$((retry_count % 4))]}
    MSG="Waiting for Quay API to be available..."
    if ! $progress_started; then
        printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
    fi

    # Sleep for the defined interval and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r$FAIL_MSG Quay API did not become available%*s\n" $((LINE_WIDTH - 36)) ""
        exit 1
    fi
done

# Using the API to create the first user
curl -X POST -k "https://$QUAY_HOST/api/v1/user/initialize" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"$REGISTRY_ID"'","password":"'"$REGISTRY_PW"'","email":"test@example.com","access_token":true}' >/dev/null 2>&1
run_command "Using the API to create the first user"

# Check the environment variable OCP_TRUSTED_CA: continue if "true", exit if otherwise
if [[ "$OCP_TRUSTED_CA" != "true" ]]; then
    echo 
    PRINT_TASK "TASK [Quay login information]"
    echo -e "$INFO_MSG Quay Console: https://$QUAY_HOST"
    echo -e "$INFO_MSG Quay superuser credentials — ID: $REGISTRY_ID, PW: $REGISTRY_PW"
    exit 0
fi

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Configuring additional trust stores for image registry access]"

# Export the router-ca certificate
rm -rf tls.crt >/dev/null
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator >/dev/null 2>&1
run_command "Export the router-ca certificate"

sleep 2

sudo rm -rf /etc/pki/ca-trust/source/anchors/ingress-ca.crt >/dev/null 2>&1
sudo cp tls.crt /etc/pki/ca-trust/source/anchors/ingress-ca.crt >/dev/null 2>&1
run_command "Copy rootCA certificate to trusted anchors"

rm -rf tls.crt >/dev/null

# Trust the rootCA certificate
sudo update-ca-trust
run_command "Trust the rootCA certificate"

sleep 10

# Create a configmap containing the CA certificate
export QUAY_HOST=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}') >/dev/null 2>&1

# Get the Quay route host for the given namespace and store in QUAY_HOST
REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if [[ -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-config --from-file=${QUAY_HOST}=/etc/pki/ca-trust/source/anchors/ingress-ca.crt -n openshift-config >/dev/null 2>&1
  run_command "Create a configmap containing the registry CA certificate: registry-config"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null 2>&1
  run_command "Trust the registry-config configmap"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-cas --from-file=${QUAY_HOST}=/etc/pki/ca-trust/source/anchors/ingress-ca.crt -n openshift-config >/dev/null 2>&1
  run_command "Create a configmap containing the registry CA certificate: registry-cas"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge >/dev/null 2>&1
  run_command "Trust the registry-cas configmap"
fi

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Update pull-secret]"

# Export pull-secret
rm -rf tmp-pull-secret
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > tmp-pull-secret
run_command "Export pull-secret"

sleep 5

# Update pull-secret file
export AUTHFILE="tmp-pull-secret"

# Base64 encode the username:password
AUTH=cXVheWFkbWluOnBhc3N3b3Jk
export REGISTRY=$(oc get route example-registry-quay -n $NAMESPACE --template='{{.spec.host}}')

if [ -f "$AUTHFILE" ]; then
  jq --arg registry "$REGISTRY" \
     --arg auth "$AUTH" \
     '.auths[$registry] = {auth: $auth}' \
     "$AUTHFILE" > tmp-authfile && mv -f tmp-authfile "$AUTHFILE"
else
cat <<EOF > $AUTHFILE
{
    "auths": {
        "$REGISTRY": {
            "auth": "$AUTH"
        }
    }
}
EOF
fi
echo -e "$INFO_MSG Authentication information for quay registry added to $AUTHFILE"

# Update pull-secret 
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=tmp-pull-secret >/dev/null 2>&1
run_command "Update pull-secret for the cluster"

rm -rf tmp-authfile >/dev/null 2>&1
rm -rf tmp-pull-secret >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Checking the cluster status]"

# Wait for all MachineConfigPools (MCPs) to be Ready
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get MCP statuses: Ready, Updated, Degraded
    output=$(oc get mcp --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    # If any MCP is not Ready/Updated/Degraded as expected
    if echo "$output" | grep -q -v "True False False"; then
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "$INFO_MSG Waiting for all MachineConfigPools to be Ready... %s" "$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG Waiting for all MachineConfigPools to be Ready... %s" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))
        # Timeout handling
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG MachineConfigPools not Ready%*s\n" $((LINE_WIDTH - 20)) ""
            exit 1
        fi
    else
        # All MCPs are Ready
        if $progress_started; then
            printf "\r$INFO_MSG All MachineConfigPools are Ready%*s\n" $((LINE_WIDTH - 18)) ""
        else
            printf "$INFO_MSG All MachineConfigPools are Ready%*s\n" $((LINE_WIDTH - 18)) ""
        fi
        break
    fi
done

# Wait for all Cluster Operators (COs) to be Ready
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get Cluster Operator statuses: Available, Progressing, Degraded
    output=$(oc get co --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    # If any CO is not Available/Progressing/Degraded as expected
    if echo "$output" | grep -q -v "True False False"; then
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "$INFO_MSG Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))
        # Timeout handling
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG Cluster Operators not Ready%*s\n" $((LINE_WIDTH - 31)) ""
            exit 1
        fi
    else
        # All Cluster Operators are Ready
        if $progress_started; then
            printf "\r$INFO_MSG All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        else
            printf "$INFO_MSG All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        fi
        break
    fi
done

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Quay login information]"
echo -e "$INFO_MSG Quay console: https://$QUAY_HOST"
echo -e "$INFO_MSG Quay superuser credentials — ID: $REGISTRY_ID, PW: $REGISTRY_PW"

# Add an empty line after the task
echo
