#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Need a default storageclass

# Applying environment variables
export KEYCLOAK_REALM_USER=rhadmin
export KEYCLOAK_REALM_PASSWORD=redhat
export OPERATOR_NS="rhsso"
export SUB_CHANNEL="stable"
export CATALOG_SOURCE="redhat-operators"

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
PRINT_TASK "TASK [Delete old rhsso resources]"

# Uninstall first
if oc get ns $OPERATOR_NS >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting keycloak resources..."
else
    echo -e "\e[96mINFO\e[0m keycloak does not exist"
fi

oc delete configmap openid-route-ca -n openshift-config >/dev/null 2>&1 || true
oc delete secret openid-client-secret -n openshift-config >/dev/null 2>&1 || true
oc delete keycloakuser --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete keycloakclient --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete keycloakrealm --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete keycloak --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete operatorgroup rhsso-operator-group $OPERATOR_NS >/dev/null 2>&1 || true
oc delete sub rhsso-operator -n $OPERATOR_NS >/dev/null 2>&1 || true
oc get csv -n $OPERATOR_NS -o name | grep rhsso-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n $OPERATOR_NS >/dev/null 2>&1 || true
oc get ip -n $OPERATOR_NS --no-headers 2>/dev/null|grep rhsso-operator|awk '{print $1}'|xargs -r oc delete ip -n $OPERATOR_NS >/dev/null 2>&1 || true


if oc get ns $OPERATOR_NS >/dev/null 2>&1; then
    echo -e "\e[96mINFO\e[0m Deleting $OPERATOR_NS project..."
    oc delete ns $OPERATOR_NS >/dev/null 2>&1 || true
else
    echo -e "\e[96mINFO\e[0m $OPERATOR_NS project does not exist"
fi

# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Deploying Single Sign-On Operator]"

# Create a Namespace
cat << EOF | oc create -f - >/dev/null 2>&1
apiVersion: v1
kind: Namespace
metadata:
  name: ${OPERATOR_NS}
EOF
run_command "Create a ${OPERATOR_NS} namespace"

# Create a Subscription
cat << EOF | oc create -f - >/dev/null 2>&1
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhsso-operator-group
  namespace: ${OPERATOR_NS}
spec:
  targetNamespaces:
  - ${OPERATOR_NS} # change this to the namespace you will use for RH-SSO
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhsso-operator
  namespace: ${OPERATOR_NS}
spec:
  channel: ${SUB_CHANNEL}
  installPlanApproval: Manual
  name: rhsso-operator
  source: ${CATALOG_SOURCE}
  sourceNamespace: openshift-marketplace
EOF
run_command "Install the rhsso operator"

# Approve the install plan
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the rhsso operator install plan"


# Wait for rhsso-operator pods to be in 'Running' state
NAMESPACE=$OPERATOR_NS
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=rhsso-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers 2>/dev/null |grep $pod_name | awk '{print $2, $3}' || true)
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for $pod_name pods to be in Running state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries $pod_name pods may still be initializing"
            exit 1
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m The $pod_name pods are in Running state]"
        break
    fi
done

sleep 30

# Create the Keycloak resource
cat << EOF | oc create -f - >/dev/null 2>&1
apiVersion: keycloak.org/v1alpha1
kind: Keycloak
metadata:
  name: example-sso
  namespace: ${OPERATOR_NS}
  labels:
    app: sso
spec:
  instances: 1
  externalAccess:
    enabled: True
EOF
run_command "Create keycloak instance"

sleep 15

# Wait for Keycloak pods to be in 'Running' state
NAMESPACE=$OPERATOR_NS
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=keycloak

while true; do
    # Get the READY column of all pods that are not Completed
    output=$(oc get po -n $NAMESPACE --no-headers 2>/dev/null | grep -v Completed | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$output" | awk -F/ '$1 != $2')

    if [[ -n "$not_ready" ]]; then
        # Print info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for $NAMESPACE namespace pods to be in Running state"
            progress_started=true
        fi

        # Print a progress dot
        echo -n '.'

        # Sleep before the next check
        sleep "$SLEEP_INTERVAL"

        # Increment retry counter
        retry_count=$((retry_count + 1))

        # Exit if max retries are exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo
            echo -e "\e[31mFAILED\e[0m Reached max retries namespace pods may still be initializing"
            exit 1
        fi
    else
        # All pods are ready, print success message
        if $progress_started; then
            echo
        fi
        echo -e "\e[96mINFO\e[0m All $NAMESPACE namespace pods are in Running state"
        break
    fi
done


# Create the Keycloak realm resource
cat << EOF | oc create -f - >/dev/null 2>&1
apiVersion: keycloak.org/v1alpha1
kind: KeycloakRealm
metadata:
  name: example-keycloakrealm
  namespace: ${OPERATOR_NS}
  labels:
    app: sso
spec:
  realm:
    id: openshift-realm
    realm: "OpenShift"
    enabled: True
    displayName: "OpenShift Realm"
  instanceSelector:
    matchLabels:
      app: sso
EOF
run_command "Create realm custom resource"

# Get OpenShift OAuth and Console route details
export OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
export CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')

# Create the Keycloak client resource
cat << EOF | oc create -f - >/dev/null 2>&1
apiVersion: keycloak.org/v1alpha1
kind: KeycloakClient
metadata:
  name: example-client
  namespace: ${OPERATOR_NS}
  labels:
    app: sso
spec:
  client:
    clientId: openshift-demo
    clientAuthenticatorType: client-secret
    publicClient: false
    protocol: openid-connect
    standardFlowEnabled: true
    implicitFlowEnabled: false
    directAccessGrantsEnabled: true
    redirectUris:
      - https://${OAUTH_HOST}/*
      - https://${CONSOLE_HOST}/*
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
  realmSelector:
     matchLabels:
      app: sso
  scopeMappings: {}
EOF
run_command "Create client custom resource"

# Waiting for keycloak-client-secret-example-client secret to be created
sleep 10

# Initialize progress tracking
# Configuration
NAMESPACE=$OPERATOR_NS
SECRET_NAME="keycloak-client-secret-example-client"
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0

while true; do
    # Check if the secret exists
    secret_exists=$(oc get secret -n "$NAMESPACE" "$SECRET_NAME" --no-headers 2>/dev/null || true)
    
    if [ -n "$secret_exists" ]; then
        # If progress was displayed, close it properly
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m The secret $SECRET_NAME has been created"
        break
    else
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for $SECRET_NAME secret to be created"
            progress_started=true  # Mark progress as started
        fi
        
        # Print progress indicator
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries $SECRET_NAME secret was not created"
            exit 1 
        fi
    fi
done

# Create a Keycloak user
cat << EOF | oc create -f - >/dev/null 2>&1
apiVersion: keycloak.org/v1alpha1
kind: KeycloakUser
metadata:
  name: ${KEYCLOAK_REALM_USER}
  namespace: ${OPERATOR_NS}
spec:
  user:
    username: ${KEYCLOAK_REALM_USER}
    credentials:
      - type: "password"
        value: "${KEYCLOAK_REALM_PASSWORD}"
    enabled: true
    realmRoles:
      - "default-roles-openshift"
  realmSelector:
    matchLabels:
      app: sso
EOF
run_command "Create a user named $KEYCLOAK_REALM_USER"

sleep 5

oc adm policy add-cluster-role-to-user cluster-admin $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
run_command "Grant cluster-admin privileges to the $KEYCLOAK_REALM_USER account"

# Create client authenticator secret and ConfigMap containing router CA certificate
oc create secret generic openid-client-secret --from-literal=clientSecret=$(oc -n ${OPERATOR_NS} get secret keycloak-client-secret-example-client -o jsonpath='{.data.CLIENT_SECRET}' | base64 -d) -n openshift-config >/dev/null 2>&1
run_command "Create client authenticator secret"

sudo rm -rf tls.crt >/dev/null 2>&1
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator --confirm >/dev/null >/dev/null 2>&1

sleep 5

oc create configmap openid-route-ca --from-file=ca.crt=tls.crt -n openshift-config >/dev/null 2>&1
run_command "Create configmap containing router-ca certificate"

sudo rm -rf tls.crt >/dev/null 2>&1

# Apply Identity Provider configuration
export KEYCLOAK_HOST=$(oc get route keycloak -n ${OPERATOR_NS} --template='{{.spec.host}}')
cat << EOF | oc replace -f - >/dev/null 2>&1
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
      issuer: https://${KEYCLOAK_HOST}/auth/realms/OpenShift
    type: OpenID
    name: openid
EOF
run_command "Apply identity provider configuration"

# Configure OpenShift console logout redirection to Keycloak
OPERATOR_NS="rhsso"
KEYCLOAK_CLIENT_NAME='example-client'
KEYCLOAK_CLIENT_SECRET="keycloak-client-secret-${KEYCLOAK_CLIENT_NAME}"
OPENID_CLIENT_ID=$(oc get secret "$KEYCLOAK_CLIENT_SECRET" -n rhsso -o jsonpath='{.data.CLIENT_ID}' | base64 -d)
KEYCLOAK_HOST=$(oc get route keycloak -n $OPERATOR_NS -o=jsonpath='{.spec.host}')
CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')

oc patch console.config.openshift.io cluster --type merge --patch "$(cat <<EOF
{
  "spec": {
    "authentication": {
      "logoutRedirect": "https://${KEYCLOAK_HOST}/auth/realms/OpenShift/protocol/openid-connect/logout?post_logout_redirect_uri=https://${CONSOLE_HOST}&client_id=${OPENID_CLIENT_ID}"
    }
  }
}
EOF
)" >/dev/null 2>&1
run_command "Configuring console logout redirection"

# Add an empty line after the task
echo

# Step 3:
# Check cluster operator status
PRINT_TASK "TASK [Checking the status]"

NAMESPACE="$OPERATOR_NS"
MAX_RETRIES=60
SLEEP_INTERVAL=5
progress_started=false
retry_count=0

while true; do
    # Get the READY column of all pods that are not Completed
    output=$(oc get po -n $NAMESPACE --no-headers 2>/dev/null | grep -v Completed | awk '{print $2}' || true)

    # Find pods where the number of ready containers is not equal to total containers
    not_ready=$(echo "$output" | awk -F/ '$1 != $2')

    if [[ -n "$not_ready" ]]; then
        # Print info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for $NAMESPACE namespace pods to be in Running state"
            progress_started=true
        fi

        # Print a progress dot
        echo -n '.'

        # Sleep before the next check
        sleep "$SLEEP_INTERVAL"

        # Increment retry counter
        retry_count=$((retry_count + 1))

        # Exit if max retries are exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo
            echo -e "\e[31mFAILED\e[0m Reached max retries namespace pods may still be initializing"
            exit 1
        fi
    else
        # All pods are ready, print success message
        if $progress_started; then
            echo
        fi
        echo -e "\e[96mINFO\e[0m All $NAMESPACE namespace pods are in Running state"
        break
    fi
done

# Check cluster operator status
MAX_RETRIES=30
SLEEP_INTERVAL=20
progress_started=false
retry_count=0

while true; do
    # Get the status of all cluster operators
    output=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    
    # Check cluster operators status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n -e "\e[96mINFO\e[0m Waiting for all cluster operators to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo # Add this to force a newline after the message
            echo -e "\e[31mFAILED\e[0m Reached max retries cluster operator may still be initializing"
            break
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo # Add this to force a newline after the message
        fi
        echo -e "\e[96mINFO\e[0m All cluster operators have reached the expected state"
        break
    fi
done

# Retrieve Keycloak route
KEYCLOAK_HOST=$(oc get route keycloak -o jsonpath='{.spec.host}' -n ${OPERATOR_NS})

# Retrieve Keycloak admin credentials
KEYCLOAK_ADMIN_USER=$(oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_USERNAME}' -n ${OPERATOR_NS} | base64 -d)
KEYCLOAK_ADMIN_PASSWORD=$(oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_PASSWORD}' -n ${OPERATOR_NS} | base64 -d)

# Print variables for verification (optional)
echo -e "\e[96mINFO\e[0m Keycloak host: $KEYCLOAK_HOST"
echo -e "\e[96mINFO\e[0m Keycloak console ID/PWD: $KEYCLOAK_ADMIN_USER/$KEYCLOAK_ADMIN_PASSWORD"
echo -e "\e[96mINFO\e[0m User created by keycloak: $KEYCLOAK_REALM_USER/$KEYCLOAK_REALM_PASSWORD"

# Add an empty line after the task
echo
