#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Installing and configuring Red Hat build of Keycloak in OCP
export SUB_CHANNEL="stable-v26.4"
export NAMESPACE="keycloak"
export KEYCLOAK_HOST="keycloak.apps.ocp.example.com"
export KEYCLOAK_REALM_USER=rhadmin
export KEYCLOAK_REALM_PASSWORD=redhat
export STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[0].metadata.name}')

# Install Quay in standalone mode and use keycloak for authentication
# Quay version: registry.redhat.io/quay/quay-rhel9:v3.16.0  registry.redhat.io/quay/quay-rhel8:v3.15.2  registry.redhat.io/quay/quay-rhel8:v3.14.5
# Mirroring-Worker version: registry.redhat.io/quay/quay-rhel9:v3.16.0  registry.redhat.io/quay/quay-rhel8:v3.15.1  registry.redhat.io/quay/quay-rhel8:v3.14.5
# Postgresql version: registry.redhat.io/rhel9/postgresql-15(Quay v3.15~16)  registry.redhat.io/rhel8/postgresql-13 (Quay v3.14)
# Redis version: registry.redhat.io/rhel9/redis-6:latest(Quay v3.15~16) registry.redhat.io/rhel8/redis-6:1-110(Quay v3.14)
export QUAY_VERSION='registry.redhat.io/quay/quay-rhel8:v3.15.2'
export MIRRORING_WORKER='registry.redhat.io/quay/quay-rhel8:v3.15.1'
export POSTGRESQL='registry.redhat.io/rhel9/postgresql-15'
export REDIS='registry.redhat.io/rhel9/redis-6:latest'
export QUAY_HOST_NAME='quay-server.example.com'
export QUAY_HOST_IP="10.184.134.30"
export PULL_SECRET_FILE="$HOME/tools/pull-secret"
export QUAY_INST_DIR="/opt/quay-inst"
export QUAY_PORT="9443"
export REGISTRY_ID="quayadmin"
export REGISTRY_PW="password"

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
        echo -e "\e[36mINFO\e[0m $1"
    else
        echo -e "\e[31mFAIL\e[0m $1"
        exit 1
    fi
}

# Define color output variables
INFO_MSG="\e[36mINFO\e[0m"
FAIL_MSG="\e[31mFAIL\e[0m"
ACTION_MSG="\e[33mACTION\e[0m"

# Step 0:
PRINT_TASK "TASK [Delete old RHBK resources]"

# Uninstall first
if oc get keycloakrealmimport example-realm-import -n $NAMESPACE >/dev/null 2>&1; then
   echo -e "$INFO_MSG Deleting keycloakrealmimport resources..."
   oc delete keycloakrealmimport example-realm-import -n $NAMESPACE >/dev/null 2>&1 || true
else
   echo -e "$INFO_MSG The keycloakrealmimport does not exist"
fi

if oc get keycloak example-kc -n $NAMESPACE >/dev/null 2>&1; then
   echo -e "$INFO_MSG Deleting keycloak resources..."
   oc delete keycloak example-kc -n $NAMESPACE >/dev/null 2>&1 || true
   echo -e "$INFO_MSG Deleting rhbk operator..."
else
   echo -e "$INFO_MSG The keycloak resources does not exist"
fi

oc adm policy remove-cluster-role-from-user cluster-admin $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
oc delete user $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
oc delete identity "$(oc get identity -o jsonpath="{.items[?(@.user.name=='${KEYCLOAK_REALM_USER}')].metadata.name}")" >/dev/null 2>&1 || true
oc delete secret openid-client-secret -n openshift-config >/dev/null 2>&1 || true
oc delete configmap openid-route-ca -n openshift-config >/dev/null 2>&1 || true
oc delete secret example-tls-secret -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete secret keycloak-db-secret -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete statefulset postgresql-db -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete svc postgres-db -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete operatorgroup rhbk-operator-group $NAMESPACE >/dev/null 2>&1 || true
oc delete sub rhbk-operator -n $NAMESPACE >/dev/null 2>&1 || true
oc delete csv $(oc get csv -n "$NAMESPACE" -o name | grep rhbk-operator | awk -F/ '{print $2}') -n "$NAMESPACE" >/dev/null 2>&1 || true
oc get ip -n $NAMESPACE --no-headers 2>/dev/null|grep rhbk-operator|awk '{print $1}'|xargs -r oc delete ip -n $NAMESPACE >/dev/null 2>&1 || true

if oc get ns $NAMESPACE >/dev/null 2>&1; then
   echo -e "$INFO_MSG Deleting $NAMESPACE project..."
   oc delete ns $NAMESPACE >/dev/null 2>&1 || true
else
   echo -e "$INFO_MSG The $NAMESPACE project does not exist"
fi


# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Deploying Red Hat build of Keycloak Operator]"

# Create namespace, operator group, subscription
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
run_command "Create a ${NAMESPACE} namespace"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhbk-operator-group
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
  - ${NAMESPACE}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhbk-operator
  namespace: ${NAMESPACE}
spec:
  channel: ${SUB_CHANNEL}
  installPlanApproval: Automatic
  name: rhbk-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the redhat build of keycloak operator"

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=900                # Maximum number of retries
SLEEP_INTERVAL=2               # Sleep interval in seconds
LINE_WIDTH=120                 # Control line width
SPINNER=('/' '-' '\' '|')      # Spinner animation characters
retry_count=0                  # Number of status check attempts
progress_started=false         # Tracks whether the spinner/progress line has been started
project=$NAMESPACE
pod_name=rhbk-operator

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

# Add an empty line after the task
echo

# Step 2:
PRINT_TASK "TASK [Install a PostgreSQL DB]"

# StatefulSet for PostgreSQL database
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-db
  namespace: ${NAMESPACE}
spec:
  serviceName: postgresql-db-service
  selector:
    matchLabels:
      app: postgresql-db
  replicas: 1
  template:
    metadata:
      labels:
        app: postgresql-db
    spec:
      containers:
        - name: postgresql-db
          image: postgres:15
          volumeMounts:
            - mountPath: /data
              name: psql
          env:
            - name: POSTGRES_USER
              value: testuser
            - name: POSTGRES_PASSWORD
              value: testpassword
            - name: PGDATA
              value: /data/pgdata
            - name: POSTGRES_DB
              value: keycloak
  volumeClaimTemplates: 
  - metadata:
      name: psql
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "$STORAGE_CLASS"
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
spec:
  selector:
    app: postgresql-db
  type: LoadBalancer
  ports:
  - port: 5432
    targetPort: 5432
EOF
run_command "Deploy the database instance"

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=500               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=$NAMESPACE
pod_name=postgresql-db-0

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

# Create secret for database credentials
cat << EOF | oc apply -f - >/dev/null 2>&1
kind: Secret
apiVersion: v1
metadata:
  name: keycloak-db-secret
  namespace: ${NAMESPACE}
stringData:
  password: testpassword
  username: testuser
type: Opaque
EOF
run_command "Create a database secret"

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Use the Router CA to generate a Keycloak TLS certificate]"

export OPENSSL_CNF="/etc/pki/tls/openssl.cnf"
export CERT_VALID_DAYS=36500

# Clean old files
rm -rf rootCA.key  rootCA.pem  rootCA.srl  tls.crt  tls.csr  tls.key

# Extract router CA certificate and key
oc extract secret/router-ca -n openshift-ingress-operator --keys=tls.crt,tls.key >/dev/null 2>&1
run_command "Extract router CA certificate and key"

sleep 1

# Rename files for later use
mv tls.key rootCA.key
mv tls.crt rootCA.pem

# Generate the TLS key
openssl genrsa -out tls.key 2048 > /dev/null 2>&1
run_command "Generate TLS private key"

# Generate a certificate signing request (CSR) for the TLS
openssl req -new -sha256 \
    -key tls.key \
    -subj "/O=Local Test Private Root CA/CN=${KEYCLOAK_HOST}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${KEYCLOAK_HOST}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out tls.csr > /dev/null 2>&1
run_command "Generate TLS certificate signing request"

# Generate the TLS certificate (CRT)
openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${KEYCLOAK_HOST}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days ${CERT_VALID_DAYS} \
    -in tls.csr \
    -CA rootCA.pem \
    -CAkey rootCA.key \
    -CAcreateserial -out tls.crt  > /dev/null 2>&1
run_command "Generate TLS certificate signed by root CA"

# Create secret for Keycloak TLS certificate
oc create secret -n ${NAMESPACE} tls example-tls-secret --cert=tls.crt --key=tls.key >/dev/null 2>&1
run_command "Create a secret containing the keycloak TLS certificate"

# Clean temporary files
rm -rf rootCA.key  rootCA.pem  rootCA.srl  tls.crt  tls.csr  tls.key

# Add an empty line after the task
echo

sleep 3

# Step 4:
PRINT_TASK "TASK [Deploy the Red Hat Build of Keycloak Instance]"

# Deploy Keycloak instance
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: example-kc
  namespace: ${NAMESPACE}
spec:
  instances: 1
  db:
    vendor: postgres
    host: postgres-db
    usernameSecret:
      name: keycloak-db-secret
      key: username
    passwordSecret:
      name: keycloak-db-secret
      key: password
  http:
    tlsSecret: example-tls-secret
  hostname:
    hostname: $KEYCLOAK_HOST
EOF
run_command "Create the Keycloak CR"

sleep 3

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=500               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=$NAMESPACE
pod_name=example-kc-0

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

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Creating a Realm Import Custom Resource]"

# Get OpenShift OAuth and Console route details
OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
run_command "OpenShift OAuth host detected: ${OAUTH_HOST}"

CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')
run_command "OpenShift Console host detected: ${CONSOLE_HOST}"

# Create Keycloak client secret
oc create secret generic keycloak-client-secret --from-literal=client-secret=$(openssl rand -base64 32) -n ${NAMESPACE}  >/dev/null 2>&1
run_command "Create the Keycloak client secret"

sleep 3

CLIENT_SECRET=$(oc get -n ${NAMESPACE} secret keycloak-client-secret -o jsonpath='{.data.client-secret}' | base64 --decode)
run_command "Keycloak client secret detected: ${CLIENT_SECRET}"

sleep 1

# Apply KeycloakRealmImport for realm, client, and user
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: example-realm-import
  namespace: ${NAMESPACE}
spec:
  keycloakCRName: example-kc
  realm:
    id: openshift-realm
    realm: "quay"
    displayName: "Quay Realm"
    enabled: true
    clients:
      - clientId: quay-enterprise
        enabled: true
        protocol: openid-connect
        publicClient: false
        standardFlowEnabled: true
        implicitFlowEnabled: false
        directAccessGrantsEnabled: false
        rootUrl: "https://quay-server.example.com:9443/"
        redirectUris:
          - "https://quay-server.example.com:9443/oauth2/rhsso/callback"
          - "https://quay-server.example.com:9443/oauth2/rhsso/callback/cli"
          - "https://quay-server.example.com:9443/oauth2/rhsso/callback/attach"
        defaultClientScopes:
          - acr
          - email
          - profile
          - roles
          - web-origins
        optionalClientScopes:
          - address
          - microprofile-jwt
          - offline_access
          - phone
        clientAuthenticatorType: client-secret
        secret: "${CLIENT_SECRET}"
    users:
      - username: "${KEYCLOAK_REALM_USER}"
        enabled: true
        email: rhadmin@example.com
        firstName: admin
        lastName: rh
        credentials:
          - type: password
            value: "${KEYCLOAK_REALM_PASSWORD}"
            temporary: false
        realmRoles:
          - "default-roles-quay"
EOF
run_command "Create the KeycloakRealmImport"


# Waiting for keycloakrealmimports to complete creation
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=$(tput cols)      # Terminal line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
done_printed="no"            # Ensure the completion message is printed only once
REALM_IMPORT="example-realm-import"

# Loop to wait for Realm Import completion
while true; do
    # Get the current status of the KeycloakRealmImport
    status=$(oc get keycloakrealmimports/${REALM_IMPORT} -n ${NAMESPACE} \
        -o go-template='{{range .status.conditions}}{{.type}}={{.status}} {{end}}' 2>/dev/null || true)
    
    started=$(echo "$status" | grep -o "Started=True" || true)
    done_status=$(echo "$status" | grep -o "Done=True" || true)
    errors=$(echo "$status" | grep -o "HasErrors=True" || true)
    CHAR=${SPINNER[$((retry_count % 4))]}

    if [[ -n "$done_status" && -z "$errors" ]]; then
        # Realm Import completed without errors
        if [[ "$done_printed" == "no" ]]; then
            MSG="Realm import '$REALM_IMPORT' completed"
            printf "\r$INFO_MSG %s" "$MSG"
            tput el
            printf "\n"
            done_printed="yes"
        fi
        break
    elif [[ -n "$started" ]]; then
        # Realm Import in progress
        MSG="Realm import '$REALM_IMPORT' in progress... $CHAR"
        printf "\r$INFO_MSG %s" "$MSG"
        tput el
    else
        # Realm Import not started yet
        MSG="Waiting for Realm import '$REALM_IMPORT' to start... $CHAR"
        printf "\r$INFO_MSG %s" "$MSG"
        tput el
    fi

    sleep $SLEEP_INTERVAL
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        MSG="Reached max retries, Realm import '$REALM_IMPORT' not completed"
        printf "\r$FAIL_MSG %s" "$MSG"
        tput el
        printf "\n"
        exit 1
    fi
done

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150              # Maximum number of retries
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

# Add an empty line after the task
echo

# Retrieve Keycloak route
KEYCLOAK_HOST=$(oc get route -n ${NAMESPACE} -l app.kubernetes.io/instance=example-kc -o jsonpath='{.items[0].spec.host}')

# Retrieve Keycloak admin credentials
KEYCLOAK_INITIAL_ADMIN_USER=$(oc -n ${NAMESPACE} get secret example-kc-initial-admin -o jsonpath='{.data.username}' | base64 --decode)
KEYCLOAK_INITIAL_ADMIN_PASSWORD=$(oc -n ${NAMESPACE} get secret example-kc-initial-admin -o jsonpath='{.data.password}' | base64 --decode)
CLIENT_SECRET=$(oc get -n ${NAMESPACE} secret keycloak-client-secret -o jsonpath='{.data.client-secret}' | base64 --decode)

# Add an empty line after the task
echo

### Standalone Quay
# Step 1:
PRINT_TASK "TASK [Delete existing duplicate data]"

# Function to remove a container with formatted output
remove_container() {
    local container_name="$1"
    if podman container exists "$container_name"; then
        if podman rm -f "$container_name" >/dev/null 2>&1; then
            echo -e "$INFO_MSG Container $container_name removed"
        else
            echo -e "$FAIL_MSG Container $container_name removed"
        fi
    else
        echo -e "$INFO_MSG No such container: $container_name"
    fi
}

# Function to remove a directory with formatted output
remove_directory() {
    local dir_path="$1"
    if [ -d "$dir_path" ]; then
        if sudo rm -rf "$dir_path" >/dev/null 2>&1; then
            echo -e "$INFO_MSG Quay install directory $dir_path removed"
        else
            echo -e "$FAIL_MSG Quay install directory $dir_path removed"
        fi
    else
        echo -e "$INFO_MSG No such install directory: $dir_path"
    fi
}

# Begin cleanup
remove_container "postgresql-quay"
remove_container "quay"
remove_container "redis"
remove_container "mirroring-worker"
remove_directory "$QUAY_INST_DIR"

# Remove CA certificate if it exists
CA_CERT="/etc/pki/ca-trust/source/anchors/${QUAY_HOST_NAME}.ca.pem"
if [ -f "$CA_CERT" ]; then
    if sudo rm -rf "$CA_CERT"; then
        echo -e "$INFO_MSG CA cert $CA_CERT removed"
    else
        echo -e "$FAIL_MSG CA cert $CA_CERT removed"
    fi
else
    echo -e "$INFO_MSG No such file: $CA_CERT"
fi

# Remove systemd service files if they exist
for service in postgresql-quay redis quay mirroring-worker; do
    SERVICE_FILE="/etc/systemd/system/container-${service}.service"

    if [ -f "$SERVICE_FILE" ]; then
        if sudo rm -rf "$SERVICE_FILE"; then
            echo -e "$INFO_MSG Systemd service $SERVICE_FILE removed"
        else
            echo -e "$FAIL_MSG Systemd service $SERVICE_FILE removed"
        fi
    else
        echo -e "$INFO_MSG No such file: $SERVICE_FILE"
    fi
done

# Add an empty line after the task
echo

# Step 2: 
PRINT_TASK "TASK [Install infrastructure RPM]"

# List of RPM packages to install
packages=("podman")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
echo -e "$INFO_MSG Installing RPM package..."
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

# Add an empty line after the task
echo

# Step 3: 
# Task: Generate a self-signed certificate
PRINT_TASK "TASK [Generate a self-signed certificate]"

# Default variable
export DOMAIN="$QUAY_HOST_NAME"
export CERTS_DIR="$QUAY_INST_DIR/config"
export CA_CN="Test Workspace Signer"
export OPENSSL_CNF="/etc/pki/tls/openssl.cnf"

# Create a local directory to store the quay config.yaml and certificates
rm -rf $QUAY_INST_DIR > /dev/null 2>&1
mkdir -p $QUAY_INST_DIR/config >/dev/null 2>&1
run_command "Create a local directory to store the quay config.yaml and certificates"

# Generate the root Certificate Authority (CA) key
openssl genrsa -out ${CERTS_DIR}/rootCA.key 4096 > /dev/null 2>&1
run_command "Generate root CA private key"

# Generate the root CA certificate
openssl req -x509 \
  -new -nodes \
  -key ${CERTS_DIR}/rootCA.key \
  -sha256 \
  -days 1024 \
  -out ${CERTS_DIR}/rootCA.pem \
  -subj /CN="${CA_CN}" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat ${OPENSSL_CNF} \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) > /dev/null 2>&1
run_command "Generate root CA self-signed certificate"

# Generate the SSL key
openssl genrsa -out ${CERTS_DIR}/ssl.key 2048 > /dev/null 2>&1
run_command "Generate SSL private key"

# Generate a certificate signing request (CSR) for the SSL
openssl req -new -sha256 \
    -key ${CERTS_DIR}/ssl.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${DOMAIN}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out ${CERTS_DIR}/ssl.csr > /dev/null 2>&1
run_command "Generate SSL certificate signing request"

# Generate the SSL certificate (CRT)
openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 365 \
    -in ${CERTS_DIR}/ssl.csr \
    -CA ${CERTS_DIR}/rootCA.pem \
    -CAkey ${CERTS_DIR}/rootCA.key \
    -CAcreateserial -out ${CERTS_DIR}/ssl.cert > /dev/null 2>&1
run_command "Generate SSL certificate signed by root CA"

oc extract secret/router-ca -n openshift-ingress-operator --keys=tls.crt > /dev/null 2>&1
run_command "Extract router CA certificate"

sudo mkdir ${CERTS_DIR}/extra_ca_certs > /dev/null 2>&1
run_command "Create the directory ${CERTS_DIR}/extra_ca_certs"

sudo mv tls.crt ${CERTS_DIR}/extra_ca_certs/keycloak.crt > /dev/null 2>&1
run_command "Transfer the router CA certificate to the ${CERTS_DIR}/extra_ca_certs directory"

chmod 755 ${CERTS_DIR}/extra_ca_certs > /dev/null 2>&1
run_command "Change the permissions of ${CERTS_DIR}/extra_ca_certs"

chmod 644 ${CERTS_DIR}/extra_ca_certs/*.crt > /dev/null 2>&1
run_command "Change the permissions of ${CERTS_DIR}/extra_ca_certs/keycloak.crt"

sudo chmod 777 -R $QUAY_INST_DIR/config > /dev/null 2>&1
run_command "Change the permissions of $QUAY_INST_DIR/config"


# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Install Quay Registry]"

cat $PULL_SECRET_FILE >/dev/null 2>&1
run_command "Verify existence of $PULL_SECRET_FILE file"

# Add registry entry to /etc/hosts
if ! grep -q "$QUAY_HOST_NAME" /etc/hosts; then
  echo "# Add registry entry to /etc/hosts" | sudo tee -a /etc/hosts > /dev/null
  echo "$QUAY_HOST_IP $QUAY_HOST_NAME" | sudo tee -a /etc/hosts > /dev/null
  echo -e "$INFO_MSG Add registry entry to /etc/hosts"
else
  echo -e "$INFO_MSG Registry entry already exists in /etc/hosts"
fi

# Create a database data directory
mkdir -p $QUAY_INST_DIR/postgres-quay >/dev/null 2>&1
run_command "Create a database data directory"

sleep 5

# Set the appropriate permissions
setfacl -mu:26:-wx $QUAY_INST_DIR/postgres-quay >/dev/null 2>&1
run_command "Set the appropriate permissions"

sleep 5

# Start the Postgres container
podman run -d --quiet --name postgresql-quay \
  --restart=always \
  -e POSTGRESQL_USER=quayuser \
  -e POSTGRESQL_PASSWORD=quaypass \
  -e POSTGRESQL_DATABASE=quay \
  -e POSTGRESQL_ADMIN_PASSWORD=adminpass \
  -p 5432:5432 \
  --authfile $PULL_SECRET_FILE \
  -v $QUAY_INST_DIR/postgres-quay:/var/lib/pgsql/data:Z \
  $POSTGRESQL >/dev/null 2>&1
run_command "Start the Postgres Container"

# Wait for container to be in Running state
containers=("postgresql-quay")   # container name
MAX_RETRIES=100               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started

while true; do
    all_running=true
    for c in "${containers[@]}"; do
        if ! podman ps --format "{{.Names}}" | grep -qw "$c"; then
            all_running=false
            break
        fi
    done

    CHAR=${SPINNER[$((retry_count % 4))]}

    if $all_running; then
        # Overwrite spinner line and print final message
        printf "\r"
        tput el
        echo -e "$INFO_MSG All containers are running"
        break
    else
        # Spinner display
        if ! $progress_started; then
            progress_started=true
        fi
        printf "\r$INFO_MSG Waiting for all containers to be running %s" "$CHAR"
        tput el

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r"
            tput el
            echo -e "$FAIL_MSG Some containers are not running"
            exit 1
        fi
    fi
done

sleep 10

# Ensure that the Postgres pg_trgm module is installed
podman exec -it postgresql-quay /bin/bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U postgres' >/dev/null 2>&1
run_command "Enable pg_trgm module in quay postgres"

# Start the Redis container
podman run -d --quiet --name redis --restart=always \
  -p 6379:6379 \
  -e REDIS_PASSWORD=strongpassword \
  --authfile $PULL_SECRET_FILE \
  $REDIS >/dev/null 2>&1
run_command "Start the Redis container"

# Create a minimal config.yaml file for deploying Quay
cat > $QUAY_INST_DIR/config/config.yaml << EOF
BUILDLOGS_REDIS:
    host: $QUAY_HOST_NAME
    password: strongpassword
    port: 6379
CREATE_NAMESPACE_ON_PUSH: true
DATABASE_SECRET_KEY: a8c2744b-7004-4af2-bcee-e417e7bdd235
DB_URI: postgresql://quayuser:quaypass@$QUAY_HOST_NAME:5432/quay
DISTRIBUTED_STORAGE_CONFIG:
    default:
        - LocalStorage
        - storage_path: /datastorage/registry
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
    - default
FEATURE_REPO_MIRROR: true
FEATURE_MAILING: false
SECRET_KEY: e9bd34f4-900c-436a-979e-7530e5d74ac8
DEFAULT_TAG_EXPIRATION: 1s
TAG_EXPIRATION_OPTIONS:
    - 1s
TESTING: false
SERVER_HOSTNAME: $QUAY_HOST_NAME:$QUAY_PORT
PREFERRED_URL_SCHEME: https
SETUP_COMPLETE: true
FEATURE_USER_INITIALIZE: true
SUPER_USERS:
  - $REGISTRY_ID
USER_EVENTS_REDIS:
    host: $QUAY_HOST_NAME
    password: strongpassword
    port: 6379
AUTHENTICATION_TYPE: OIDC
RHSSO_LOGIN_CONFIG:
  CLIENT_ID: quay-enterprise
  CLIENT_SECRET: $CLIENT_SECRET
  OIDC_SERVER: https://$KEYCLOAK_HOST/realms/quay/
  SERVICE_NAME: Keycloak
  VERIFIED_EMAIL_CLAIM_NAME: email
  PREFERRED_USERNAME_CLAIM_NAME: preferred_username
  LOGIN_SCOPES: ['openid']
EOF
run_command "Create a minimal config.yaml file for deploying Quay"

# Create a local directory that will store registry images
mkdir $QUAY_INST_DIR/storage >/dev/null 2>&1
run_command "Create a local directory that will store registry images"

sleep 5

# Set the directory to store registry images
setfacl -m u:1001:-wx $QUAY_INST_DIR/storage >/dev/null 2>&1
run_command "Set the directory to store registry images"

sleep 5

# Deploy the quay registry 
RUN_CONTAINER=$(podman run -d --quiet -p 8090:8080 -p $QUAY_PORT:8443 --name=quay \
   --restart=always \
   -v $QUAY_INST_DIR/config:/conf/stack:Z \
   -v $QUAY_INST_DIR/storage:/datastorage:Z \
   --authfile $PULL_SECRET_FILE \
   $QUAY_VERSION 2>/dev/null)
run_command "Deploy the Quay registry container"

sleep 5

# Deploy the mirroring-worker
RUN_CONTAINER=$(podman run -d --quiet --name mirroring-worker \
  -v $QUAY_INST_DIR/config:/conf/stack:Z \
  -v ${QUAY_INST_DIR}/config/rootCA.pem:/etc/pki/ca-trust/source/anchors/ca.crt:Z \
  --authfile $PULL_SECRET_FILE \
  $MIRRORING_WORKER repomirror 2>/dev/null)
run_command "Deploy the Mirroring Worker container"


# Wait for container to be in Running state
containers=("postgresql-quay" "redis" "quay" "mirroring-worker")   # container name
MAX_RETRIES=100               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started

while true; do
    all_running=true
    for c in "${containers[@]}"; do
        if ! podman ps --format "{{.Names}}" | grep -qw "$c"; then
            all_running=false
            break
        fi
    done

    CHAR=${SPINNER[$((retry_count % 4))]}

    if $all_running; then
        # Overwrite spinner line and print final message
        printf "\r"
        tput el
        echo -e "$INFO_MSG All containers are running"
        break
    else
        # Spinner display
        if ! $progress_started; then
            progress_started=true
        fi
        printf "\r$INFO_MSG Waiting for all containers to be running %s" "$CHAR"
        tput el

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r"
            tput el
            echo -e "$FAIL_MSG Some containers are not running"
            exit 1
        fi
    fi
done

# Generate systemd service file for PostgreSQL
sudo rm -rf container-*.service
CREATE_SYSTEMD_FILES=$(podman generate systemd --name postgresql-quay --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for PostgreSQL"

# Generate systemd service file for Redis
CREATE_SYSTEMD_FILES=$(podman generate systemd --name redis --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for Redis"

# Generate systemd service file for Quay
CREATE_SYSTEMD_FILES=$(podman generate systemd --name quay --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for Quay"

# Generate systemd service file for Mirroring-Worker
CREATE_SYSTEMD_FILES=$(podman generate systemd --name mirroring-worker --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for Mirroring-Worker"

# Move generated files to systemd directory
sudo mv container-*.service /etc/systemd/system/ >/dev/null 2>&1
run_command "Move generated files to systemd directory"

# Reload systemd to pick up new services
sudo systemctl daemon-reload >/dev/null 2>&1
run_command "Reload systemd to pick up new services"

# Enable and start each service
sudo systemctl enable --now container-postgresql-quay.service >/dev/null 2>&1
run_command "Enable and start postgresql service"

sudo systemctl enable --now container-redis.service >/dev/null 2>&1
run_command "Enable and start redis service"

sudo systemctl enable --now container-quay.service >/dev/null 2>&1
run_command "Enable and start quay service"

sudo systemctl enable --now container-mirroring-worker.service >/dev/null 2>&1
run_command "Enable and start mirroring-worker service"

# Copy the rootCA certificate to the trusted source
sudo cp ${QUAY_INST_DIR}/config/rootCA.pem /etc/pki/ca-trust/source/anchors/$QUAY_HOST_NAME.ca.pem
run_command "Copy rootCA certificate to trusted anchors"

# Trust the rootCA certificate
sudo update-ca-trust
run_command "Trust the rootCA certificate"

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
                "https://$QUAY_HOST_NAME:$QUAY_PORT/api/v1/user/initialize" || true)

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
curl -X POST -k "https://$QUAY_HOST_NAME:$QUAY_PORT/api/v1/user/initialize" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"$REGISTRY_ID"'","password":"'"$REGISTRY_PW"'","email":"test@example.com","access_token":true}' >/dev/null 2>&1
run_command "Using the API to create the first user"

echo -e "$INFO_MSG Installation complete"

# Add an empty line after the task
echo

PRINT_TASK "TASK [Keycloak login information]"
# Print variables for verification

echo -e "$INFO_MSG Keycloak Host -> https://$KEYCLOAK_HOST"
echo -e "$INFO_MSG Keycloak Console -> Username: $KEYCLOAK_INITIAL_ADMIN_USER, Password: $KEYCLOAK_INITIAL_ADMIN_PASSWORD"
echo -e "$INFO_MSG Keycloak Realm User -> Username: $KEYCLOAK_REALM_USER, Password: $KEYCLOAK_REALM_PASSWORD"
echo -e "$INFO_MSG Keycloak Client Secret: $CLIENT_SECRET"

# Add an empty line after the task
echo

PRINT_TASK "TASK [Quay login information]"

echo -e "$INFO_MSG Quay Console: https://$QUAY_HOST_NAME:$QUAY_PORT"
echo -e "$INFO_MSG Quay superuser credentials — ID: $REGISTRY_ID, PW: $REGISTRY_PW"
echo -e "$ACTION_MSG Add DNS Records for Mirror Registry to Allow OCP Access"

# Add an empty line after the task
echo
