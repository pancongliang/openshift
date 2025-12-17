#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Applying environment variables
export OPERATOR_NS="keycloak"
export SUB_CHANNEL="stable-v26.4"
export CATALOG_SOURCE=redhat-operators
export KEYCLOAK_HOST="keycloak.apps.ocp.example.com"
export KEYCLOAK_REALM_USER=rhadmin
export KEYCLOAK_REALM_PASSWORD=redhat
export STORAGE_CLASS="managed-nfs-storage"

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
        echo -e "\e[31mFAILED\e[0m $1"
        exit 1
    fi
}

# Step 0:
PRINT_TASK "TASK [Delete old RHBK resources]"

# Uninstall first
if oc get keycloakrealmimport example-realm-import -n $OPERATOR_NS >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting keycloakrealmimport resources..."
   oc delete keycloakrealmimport example-realm-import -n $OPERATOR_NS >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The keycloakrealmimport does not exist"
fi

if oc get keycloak example-kc -n $OPERATOR_NS >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting keycloak resources..."
   oc delete keycloak example-kc -n $OPERATOR_NS >/dev/null 2>&1 || true
   echo -e "\e[96mINFO\e[0m Deleting rhbk operator..."
else
   echo -e "\e[96mINFO\e[0m The keycloak resources does not exist"
fi

oc adm policy remove-cluster-role-from-user cluster-admin $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
oc delete user $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
oc delete identity "$(oc get identity -o jsonpath="{.items[?(@.user.name=='${KEYCLOAK_REALM_USER}')].metadata.name}")" >/dev/null 2>&1 || true
oc delete secret openid-client-secret -n openshift-config >/dev/null 2>&1 || true
oc delete configmap openid-route-ca -n openshift-config >/dev/null 2>&1 || true
oc delete secret example-tls-secret -n $OPERATOR_NS  >/dev/null 2>&1 || true
oc delete secret keycloak-db-secret -n $OPERATOR_NS  >/dev/null 2>&1 || true
oc delete statefulset postgresql-db -n $OPERATOR_NS  >/dev/null 2>&1 || true
oc delete svc postgres-db -n $OPERATOR_NS  >/dev/null 2>&1 || true
oc delete operatorgroup rhbk-operator-group $OPERATOR_NS >/dev/null 2>&1 || true
oc delete sub rhbk-operator -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete csv $(oc get csv -n "$OPERATOR_NS" -o name | grep rhbk-operator | awk -F/ '{print $2}') -n "$OPERATOR_NS" >/dev/null 2>&1 || true
oc get ip -n $OPERATOR_NS --no-headers 2>/dev/null|grep rhbk-operator|awk '{print $1}'|xargs -r oc delete ip -n $OPERATOR_NS >/dev/null 2>&1 || true


if oc get ns $OPERATOR_NS >/dev/null 2>&1; then
   echo -e "\e[96mINFO\e[0m Deleting $OPERATOR_NS project..."
   oc delete ns $OPERATOR_NS >/dev/null 2>&1 || true
else
   echo -e "\e[96mINFO\e[0m The $OPERATOR_NS project does not exist"
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
  name: ${OPERATOR_NS}
EOF
run_command "Create a ${OPERATOR_NS} namespace"

cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhbk-operator-group
  namespace: ${OPERATOR_NS}
spec:
  targetNamespaces:
  - ${OPERATOR_NS}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhbk-operator
  namespace: ${OPERATOR_NS}
spec:
  channel: ${SUB_CHANNEL}
  installPlanApproval: Manual
  name: rhbk-operator
  source: ${CATALOG_SOURCE}
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the redhat build of keycloak operator"

# Approve install plan
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the rhbk-operator install plan"

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=900   # Maximum number of retries
SLEEP_INTERVAL=2  # Sleep interval in seconds
LINE_WIDTH=120    # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
project=$OPERATOR_NS
pod_name=rhbk-operator

while true; do
    # Get the status of all pods in the pod_name project
    PODS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$PODS" | awk -F/ '$1 != $2')

    if [[ -z "$not_ready" ]]; then
        # All pods are ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
        fi
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit if maximum retries reached
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
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
  namespace: ${OPERATOR_NS}
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
  namespace: ${OPERATOR_NS}
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
MAX_RETRIES=500    # Maximum number of retries
SLEEP_INTERVAL=2  # Sleep interval in seconds
LINE_WIDTH=120    # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
project=$OPERATOR_NS
pod_name=postgresql-db-0

while true; do
    # Get the status of all pods in the pod_name project
    PODS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$PODS" | awk -F/ '$1 != $2')

    if [[ -z "$not_ready" ]]; then
        # All pods are ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
        fi
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit if maximum retries reached
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
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
  namespace: ${OPERATOR_NS}
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
oc create secret -n ${OPERATOR_NS} tls example-tls-secret --cert=tls.crt --key=tls.key >/dev/null 2>&1
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
  namespace: ${OPERATOR_NS}
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
MAX_RETRIES=500   # Maximum number of retries
SLEEP_INTERVAL=2  # Sleep interval in seconds
LINE_WIDTH=120    # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
project=$OPERATOR_NS
pod_name=example-kc-0

while true; do
    # Get the status of all pods in the pod_name project
    PODS=$(oc -n "$project" get po --no-headers 2>/dev/null | grep "$pod_name" | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$PODS" | awk -F/ '$1 != $2')

    if [[ -z "$not_ready" ]]; then
        # All pods are ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for %s pods to be Running... %s" "$pod_name" "$CHAR"
        fi
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit if maximum retries reached
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
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
oc create secret generic keycloak-client-secret --from-literal=client-secret=$(openssl rand -base64 32) -n ${OPERATOR_NS}  >/dev/null 2>&1
run_command "Create the Keycloak client secret"

sleep 3

CLIENT_SECRET=$(oc get -n ${OPERATOR_NS} secret keycloak-client-secret -o jsonpath='{.data.client-secret}' | base64 --decode)
run_command "Keycloak client secret detected: ${CLIENT_SECRET}"

sleep 1

# Apply KeycloakRealmImport for realm, client, and user
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: example-realm-import
  namespace: ${OPERATOR_NS}
spec:
  keycloakCRName: example-kc
  realm:
    id: openshift-realm
    realm: "openshift"
    displayName: "OpenShift Realm"
    enabled: true
    clients:
      - clientId: openshift-demo
        enabled: true
        protocol: openid-connect
        publicClient: false
        standardFlowEnabled: true
        implicitFlowEnabled: false
        directAccessGrantsEnabled: true
        redirectUris:
          - "https://${OAUTH_HOST}/*"
          - "https://${CONSOLE_HOST}/*"
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
          - "default-roles-openshift"
EOF
run_command "Create the KeycloakRealmImport"


# Waiting for keycloakrealmimports to complete creation
MAX_RETRIES=150      # Maximum number of retries
SLEEP_INTERVAL=2     # Sleep interval in seconds
LINE_WIDTH=$(tput cols)  # Terminal line width
done_printed="no"        # Ensure the completion message is printed only once
retry_count=0
SPINNER=('/' '-' '\' '|')
REALM_IMPORT="example-realm-import"

# Loop to wait for Realm Import completion
while true; do
    # Get the current status of the KeycloakRealmImport
    status=$(oc get keycloakrealmimports/${REALM_IMPORT} -n ${OPERATOR_NS} \
        -o go-template='{{range .status.conditions}}{{.type}}={{.status}} {{end}}' 2>/dev/null || true)
    
    started=$(echo "$status" | grep -o "Started=True" || true)
    done_status=$(echo "$status" | grep -o "Done=True" || true)
    errors=$(echo "$status" | grep -o "HasErrors=True" || true)
    CHAR=${SPINNER[$((retry_count % 4))]}

    if [[ -n "$done_status" && -z "$errors" ]]; then
        # Realm Import completed without errors
        if [[ "$done_printed" == "no" ]]; then
            MSG="Realm import '$REALM_IMPORT' completed"
            printf "\r\e[96mINFO\e[0m %s" "$MSG"
            tput el
            printf "\n"
            done_printed="yes"
        fi
        break
    elif [[ -n "$started" ]]; then
        # Realm Import in progress
        MSG="Realm import '$REALM_IMPORT' in progress... $CHAR"
        printf "\r\e[96mINFO\e[0m %s" "$MSG"
        tput el
    else
        # Realm Import not started yet
        MSG="Waiting for Realm import '$REALM_IMPORT' to start... $CHAR"
        printf "\r\e[96mINFO\e[0m %s" "$MSG"
        tput el
    fi

    sleep $SLEEP_INTERVAL
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        MSG="Reached max retries, Realm import '$REALM_IMPORT' not completed"
        printf "\r\e[31mFAILED\e[0m %s" "$MSG"
        tput el
        printf "\n"
        exit 1
    fi
done

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150    # Maximum number of retries
SLEEP_INTERVAL=2   # Sleep interval in seconds
LINE_WIDTH=120     # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false
namespace=$OPERATOR_NS

while true; do
    # Get READY column of all pods that are not Completed
    PODS=$(oc -n "$namespace" get po --no-headers 2>/dev/null | grep -v Completed | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$PODS" | awk -F/ '$1 != $2')

    if [[ -z "$not_ready" ]]; then
        # All pods are ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                   "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
        else
            echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
        fi
        break
    else
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for %s namespace pods to be Running... %s" "$namespace" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for %s namespace pods to be Running... %s" "$namespace" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit if maximum retries reached
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
                   "$namespace" $((LINE_WIDTH - ${#namespace} - 31)) ""
            exit 1
        fi
    fi
done

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Configure Identity Providers]"

# Create a generic secret in OpenShift config namespace using the existing Keycloak client secret
oc create secret generic openid-client-secret --from-literal=clientSecret=$(oc -n ${OPERATOR_NS} get secret keycloak-client-secret -o jsonpath='{.data.client-secret}' | base64 -d) -n openshift-config >/dev/null 2>&1
run_command "Creates a secret that includes the Keycloak client key"

# Extract the Router CA certificate to a local file
rm -rf tls.crt >/dev/null 2>&1
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator --confirm >/dev/null 2>&1
run_command "Extract router CA certificate"

sleep 1

# Create a ConfigMap containing the Router CA certificate in OpenShift config namespace
oc create configmap openid-route-ca --from-file=ca.crt=tls.crt -n openshift-config >/dev/null 2>&1
run_command "Create a ConfigMap that contains the router's CA certificate"

# Clean up temporary certificate file
rm -rf tls.crt >/dev/null 2>&1

# Apply Identity Provider configuration
export KEYCLOAK_HOST=$(oc get route -n ${OPERATOR_NS} -l app.kubernetes.io/instance=example-kc -o jsonpath='{.items[0].spec.host}')

# Configure Identity Providers
cat << EOF | oc apply -f - >/dev/null 2>&1
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - mappingMethod: claim
    openID:
      ca:
        name: openid-route-ca
      claims:
        email:
        - email
        name:
        - name
        preferredUsername:
        - preferred_username
      clientID: openshift-demo
      clientSecret:
        name: openid-client-secret
      issuer: https://${KEYCLOAK_HOST}/realms/openshift
    type: OpenID
    name: openid
EOF
run_command "Apply identity provider configuration"

# Configure OpenShift console logout redirection to Keycloak
CLIENT_ID=$(oc get keycloakrealmimport -n ${OPERATOR_NS} example-realm-import -o jsonpath='{.spec.realm.clients[0].clientId}')
KEYCLOAK_HOST=$(oc get route -n ${OPERATOR_NS} -l app.kubernetes.io/instance=example-kc -o jsonpath='{.items[0].spec.host}')
CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')

oc patch console.config.openshift.io cluster --type merge --patch "$(cat <<EOF
{
  "spec": {
    "authentication": {
      "logoutRedirect": "https://${KEYCLOAK_HOST}/realms/openshift/protocol/openid-connect/logout?client_id=${CLIENT_ID}&post_logout_redirect_uri=https://${CONSOLE_HOST}"
    }
  }
}
EOF
)" >/dev/null 2>&1
run_command "Configuring console logout redirection"

echo -e "\e[96mINFO\e[0m Waiting for all cluster operators to reach the expected state..."
sleep 60

# Wait for all cluster operators
MAX_RETRIES=150   # Maximum number of retries
SLEEP_INTERVAL=2  # Sleep interval in seconds
LINE_WIDTH=120    # Control line width
SPINNER=('/' '-' '\' '|')
retry_count=0
progress_started=false

while true; do
    output=$(/usr/local/bin/oc get co --no-headers 2>/dev/null | awk '{print $3, $4, $5}')

    if echo "$output" | grep -q -v "True False False"; then
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "\e[96mINFO\e[0m Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m Cluster Operators not Ready%*s\n" $((LINE_WIDTH - 31)) ""
            exit 1
        fi
    else
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        else
            printf "\e[96mINFO\e[0m All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        fi
        break
    fi
done

# Grant cluster-admin privileges to the $KEYCLOAK_REALM_USER account
oc adm policy add-cluster-role-to-user cluster-admin $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
run_command "Grant cluster-admin privileges to the $KEYCLOAK_REALM_USER account"

# Retrieve Keycloak route
KEYCLOAK_HOST=$(oc get route -n ${OPERATOR_NS} -l app.kubernetes.io/instance=example-kc -o jsonpath='{.items[0].spec.host}')

# Retrieve Keycloak admin credentials
KEYCLOAK_INITIAL_ADMIN_USER=$(oc -n ${OPERATOR_NS} get secret example-kc-initial-admin -o jsonpath='{.data.username}' | base64 --decode)
KEYCLOAK_INITIAL_ADMIN_PASSWORD=$(oc -n ${OPERATOR_NS} get secret example-kc-initial-admin -o jsonpath='{.data.password}' | base64 --decode)

# Print variables for verification (optional)
echo -e "\e[96mINFO\e[0m Keycloak Host -> https://$KEYCLOAK_HOST"
echo -e "\e[96mINFO\e[0m Keycloak Console -> Username: $KEYCLOAK_INITIAL_ADMIN_USER, Password: $KEYCLOAK_INITIAL_ADMIN_PASSWORD"
echo -e "\e[96mINFO\e[0m Keycloak Realm User -> Username: $KEYCLOAK_REALM_USER, Password: $KEYCLOAK_REALM_PASSWORD"

# Add an empty line after the task
echo
