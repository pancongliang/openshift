#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: Command \`$BASH_COMMAND\`]"; exit 1' ERR

# Applying environment variables
export NAMESPACE="keycloak"
export CHANNEL="stable-v26.4"
export KEYCLOAK_REALM_USER=rhadmin
export KEYCLOAK_REALM_PASSWORD=redhat
export KEYCLOAK_HOST="keycloak.apps.ocp.example.com"
export STORAGE_CLASS_NAME="managed-nfs-storage"
export CATALOG_SOURCE_NAME=redhat-operators

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

# Step 0:
PRINT_TASK "TASK [Uninstall old rhsso resources...]"

# Uninstall first
echo "info: [Uninstall old rhbk resources...]"
oc adm policy remove-cluster-role-from-user cluster-admin $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
IDENTITY_NAME=$(oc get identities.user.openshift.io -o jsonpath="{.items[?(@.user.name=='${KEYCLOAK_REALM_USER}')].metadata.name}")
oc delete identity.user.openshift.io "${IDENTITY_NAME}" >/dev/null 2>&1 || true
oc delete secret openid-client-secret -n openshift-config >/dev/null 2>&1 || true
oc delete configmap openid-route-ca -n openshift-config >/dev/null 2>&1 || true
oc delete kkeycloakrealmimport example-realm-import  -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete keycloak example-kc -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete secret example-tls-secret -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete secret keycloak-db-secret -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete statefulsets.apps postgresql-db -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete svc postgres-db -n $NAMESPACE  >/dev/null 2>&1 || true
oc delete operatorgroup rhbk-operator-group $NAMESPACE >/dev/null 2>&1 || true
oc delete sub rhbk-operator -n $NAMESPACE >/dev/null 2>&1 || true
oc get csv -n $NAMESPACE -o name | grep rhbk-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n $NAMESPACE >/dev/null 2>&1 || true
oc delete ns $NAMESPACE >/dev/null 2>&1 || true

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
---
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
  channel: ${CHANNEL}
  installPlanApproval: Manual
  name: rhbk-operator
  source: ${CATALOG_SOURCE_NAME}
  sourceNamespace: openshift-marketplace
EOF
run_command "[Installing redhat build of keycloak operator...]"

# Approve install plan
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "[Approve the install plan]"

# Wait for operator pods to be Running
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=rhbk-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name pods to be in 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name pods are in 'Running' state]"
        break
    fi
done

sleep 10

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
      storageClassName: "$STORAGE_CLASS_NAME"
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
run_command "[Deploy the database instance]"


# Wait for PostgreSQL pod to be running
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=postgresql-db-0

while true; do
    # Get the status of all pods
    output=$(oc get po $pod_name -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name pods to be in 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name pods are in 'Running' state]"
        break
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
run_command "[Create a database secret]"

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Use the Router CA to generate a Keycloak SSL certificate]"

export OPENSSL_CNF="/etc/pki/tls/openssl.cnf"
export CERT_VALID_DAYS=36500

# Clean old files
rm -rf rootCA.key  rootCA.pem  rootCA.srl  ssl.crt  ssl.csr  ssl.key  tls.key  tls.crt

# Extract router CA certificate and key
oc extract secret/router-ca -n openshift-ingress-operator --keys=tls.crt,tls.key >/dev/null 2>&1
run_command "[Extract router CA certificate and key]"

sleep 1

# Rename files for later use
mv tls.key rootCA.key
mv tls.crt rootCA.pem

# Generate the SSL key
openssl genrsa -out ssl.key 2048 > /dev/null 2>&1
run_command "[Generate SSL private key]"

# Generate a certificate signing request (CSR) for the SSL
openssl req -new -sha256 \
    -key ssl.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${KEYCLOAK_HOST}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${KEYCLOAK_HOST}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out ssl.csr > /dev/null 2>&1
run_command "[Generate SSL certificate signing request]"

# Generate the SSL certificate (CRT)
openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${KEYCLOAK_HOST}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days ${CERT_VALID_DAYS} \
    -in ssl.csr \
    -CA rootCA.pem \
    -CAkey rootCA.key \
    -CAcreateserial -out ssl.crt  > /dev/null 2>&1
run_command "[Generate SSL certificate signed by root CA]"

# Create secret for Keycloak TLS certificate
oc create secret -n ${NAMESPACE} tls example-tls-secret --cert=ssl.crt --key=ssl.key >/dev/null 2>&1
run_command "[Create a secret containing the keycloak SSL certificate]"

# Clean temporary files
rm -rf rootCA.key  rootCA.pem  rootCA.srl  ssl.crt  ssl.csr  ssl.key

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
run_command "[Create the Keycloak CR]"

sleep 3

# Wait for Keycloak pod to be running
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=example-kc-0

while true; do
    # Get the status of all pods
    output=$(oc get po $pod_name -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name pods to be in 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name pods are in 'Running' state]"
        break
    fi
done


# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Creating a Realm Import Custom Resource]"

# Get OpenShift OAuth and Console route details
OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
run_command "[OpenShift OAuth host detected: ${OAUTH_HOST}]"

CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')
run_command "[OpenShift Console host detected: ${CONSOLE_HOST}]"

# Create Keycloak client secret
oc create secret generic keycloak-client-secret --from-literal=client-secret=$(openssl rand -base64 32) -n ${NAMESPACE}  >/dev/null 2>&1
run_command "[Create the Keycloak client secret]"

sleep 3

CLIENT_SECRET=$(oc get -n ${NAMESPACE} secret keycloak-client-secret -o jsonpath='{.data.client-secret}' | base64 --decode)
run_command "[Keycloak client secret detected: ${CLIENT_SECRET}]"

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
run_command "[Create the KeycloakRealmImport]"


# Waiting for keycloakrealmimports to complete creation
REALM_IMPORT="example-realm-import"
SLEEP_INTERVAL=5
MAX_RETRIES=60
retry_count=0
progress_started=false

while true; do
    # Ignore errors if the resource is not yet created
    status=$(oc get keycloakrealmimports/${REALM_IMPORT} -n ${NAMESPACE} -o go-template='{{range .status.conditions}}{{.type}}={{.status}} {{end}}' 2>/dev/null || true)

    started=$(echo "$status" | grep -o "Started=True" || true)
    done=$(echo "$status" | grep -o "Done=True" || true)
    errors=$(echo "$status" | grep -o "HasErrors=True" || true)

    if [[ -n "$done" && -z "$errors" ]]; then
        [[ $progress_started == true ]] && echo "]"
        echo "ok: [Realm import '${REALM_IMPORT}' completed]"
        break
    elif [[ -n "$started" ]]; then
        if [[ $progress_started == false ]]; then
            echo -n "info: [Realm import '${REALM_IMPORT}' in progress"
            progress_started=true
        fi
        echo -n '.'
    else
        # Wait until Started=True
        if [[ $progress_started == false ]]; then
            echo -n "info: [Waiting for Realm import '${REALM_IMPORT}' to start"
            progress_started=true
        fi
        echo -n '.'
    fi

    sleep $SLEEP_INTERVAL
    retry_count=$((retry_count + 1))
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        [[ $progress_started == true ]] && echo "]"
        echo "failed: [Reached max retries, Realm import '${REALM_IMPORT}' not completed]"
        exit 1
    fi
done


# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Configure Identity Providers]"

# Create a generic secret in OpenShift config namespace using the existing Keycloak client secret
oc create secret generic openid-client-secret --from-literal=clientSecret=$(oc -n ${NAMESPACE} get secret keycloak-client-secret -o jsonpath='{.data.client-secret}' | base64 -d) -n openshift-config >/dev/null 2>&1
run_command "[Creates a secret that includes the Keycloak client key]"

# Extract the Router CA certificate to a local file
rm -rf tls.crt >/dev/null 2>&1
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator --confirm >/dev/null 2>&1
run_command "[Extract router CA certificate]"

sleep 1

# Create a ConfigMap containing the Router CA certificate in OpenShift config namespace
oc create configmap openid-route-ca --from-file=ca.crt=tls.crt -n openshift-config >/dev/null 2>&1
run_command "[Create a ConfigMap that contains the router's CA certificate]"

# Clean up temporary certificate file
rm -rf tls.crt >/dev/null 2>&1

# Apply Identity Provider configuration
export KEYCLOAK_HOST=$(oc get route -n ${NAMESPACE} -l app.kubernetes.io/instance=example-kc -o jsonpath='{.items[0].spec.host}')

# Configure Identity Providers
cat << EOF | oc apply -f - >/dev/null 2>&1
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
run_command "[Apply identity provider configuration]"

sleep 20

# Wait for OpenShift authentication pods to be in 'Running' state
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=oauth

while true; do
    # Get the status of all pods
    output=$(oc get po -n openshift-authentication --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $pod_name pods to be in 'Running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $pod_name pods may still be initializing]"
            exit
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All $pod_name pods are in 'Running' state]"
        break
    fi
done


# Configure OpenShift console logout redirection to Keycloak
CLIENT_ID=$(oc get keycloakrealmimport -n ${NAMESPACE} example-realm-import -o jsonpath='{.spec.realm.clients[0].clientId}')
KEYCLOAK_HOST=$(oc get route -n ${NAMESPACE} -l app.kubernetes.io/instance=example-kc -o jsonpath='{.items[0].spec.host}')
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
run_command "[Configuring console logout redirection]"


# Check cluster operator status
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0

while true; do
    # Get the status of all cluster operators
    output=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    
    # Check cluster operators status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for all cluster operators to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, cluster operator may still be initializing]"
            break
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [All cluster operators have reached the expected state]"
        break
    fi
done

# Grant cluster-admin privileges to the $KEYCLOAK_REALM_USER account
oc adm policy add-cluster-role-to-user cluster-admin $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
run_command "[Grant cluster-admin privileges to the $KEYCLOAK_REALM_USER account]"

# Retrieve Keycloak route
KEYCLOAK_HOST=$(oc get route -n ${NAMESPACE} -l app.kubernetes.io/instance=example-kc -o jsonpath='{.items[0].spec.host}')

# Retrieve Keycloak admin credentials
KEYCLOAK_INITIAL_ADMIN_USER=$(oc -n ${NAMESPACE} get secret example-kc-initial-admin -o jsonpath='{.data.username}' | base64 --decode)
KEYCLOAK_INITIAL_ADMIN_PASSWORD=$(oc -n ${NAMESPACE} get secret example-kc-initial-admin -o jsonpath='{.data.password}' | base64 --decode)

# Print variables for verification (optional)
echo "info: [Keycloak Host -> https://$KEYCLOAK_HOST]"
echo "info: [Keycloak Console -> Username: $KEYCLOAK_INITIAL_ADMIN_USER, Password: $KEYCLOAK_INITIAL_ADMIN_PASSWORD]"
echo "info: [Keycloak Realm User -> Username: $KEYCLOAK_REALM_USER, Password: $KEYCLOAK_REALM_PASSWORD]"
