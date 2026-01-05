#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# [REQUIRED] Default StorageClass must exist
# NFS Storage Class: https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/nfs-sc/nfs-sc.sh

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

# Check if Default StorageClass exists
DEFAULT_STORAGE_CLASS=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    echo -e "\e[31mFAILED\e[0m No default StorageClass found!"
    exit 1
else
    echo -e "\e[96mINFO\e[0m Default StorageClass found: $DEFAULT_STORAGE_CLASS"
fi

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

# Automatically approve install plans in the $OPERATOR_NS namespace
# Stage 1: Wait for the first unapproved InstallPlan to appear and approve it
MAX_RETRIES=150               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
OPERATOR_NS=$OPERATOR_NS

MSG="Waiting for unapproved install plans in namespace $OPERATOR_NS"
while true; do
    # Get unapproved InstallPlans
    INSTALLPLAN=$(oc get installplan -n "$OPERATOR_NS" -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || true)

    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        oc patch installplan "$NAME" -n "$OPERATOR_NS" --type merge --patch '{"spec":{"approved":true}}' &> /dev/null || true

        # Overwrite previous INFO line with final approved message
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s%*s\n" \
               "$NAME" "$OPERATOR_NS" $((LINE_WIDTH - ${#NAME} - ${#OPERATOR_NS} - 34)) ""

        break
    fi

    # Spinner logic
    CHAR=${SPINNER[$((retry_count % ${#SPINNER[@]}))]}
    if ! $progress_started; then
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # Sleep and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace has no unapproved install plans%*s\n" \
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
        printf "\r\e[96mINFO\e[0m Approved install plan %s in namespace %s\n" "$NAME" "$OPERATOR_NS"
    done
    # Slight delay to avoid excessive polling
    sleep "$SLEEP_INTERVAL"
done

# Wait for $pod_name pods to be in Running state
MAX_RETRIES=500                # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
LINE_WIDTH=120                # Control line width
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started
project=$OPERATOR_NS
pod_name=rhsso-operator

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
            printf "\r\e[96mINFO\e[0m The %s pods are Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 20)) ""
        else
            echo -e "\e[96mINFO\e[0m The $pod_name pods are Running"
        fi
        break
    else
        # Still waiting or pod not found yet
        CHAR=${SPINNER[$((retry_count % 4))]}
        # Provide different messages if pods are missing vs. starting
        MSG="Waiting for $pod_name pods to be Running..."
        [[ -z "$RAW_STATUS" ]] && MSG="Waiting for $pod_name pods to be created..."

        if ! $progress_started; then
            printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
            progress_started=true
        else
            printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        fi

        # 4. Retry management
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m The %s pods are not Running%*s\n" \
                   "$pod_name" $((LINE_WIDTH - ${#pod_name} - 23)) ""
            exit 1
        fi
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

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=$OPERATOR_NS

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
                printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                       "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
            else
                echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
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
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # 4. Handle timeout and retry
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 45)) ""
        exit 1
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
MAX_RETRIES=180              # Maximum number of retries
SLEEP_INTERVAL=5             # Sleep interval in seconds
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
SECRET_NAME="keycloak-client-secret-example-client"
NAMESPACE=$OPERATOR_NS

# Loop to wait for the secret creation
while true; do
    # Check if the secret exists
    secret_exists=$(oc get secret -n "$NAMESPACE" "$SECRET_NAME" --no-headers 2>/dev/null || true)
    
    CHAR=${SPINNER[$((retry_count % 4))]}

    if [ -n "$secret_exists" ]; then
        # Overwrite the spinner line before printing the final message
        printf "\r"    # Move cursor to the beginning of the line
        tput el        # Clear the entire line
        echo -e "\e[96mINFO\e[0m The secret '$SECRET_NAME' has been created"
        break
    else
        # Print the waiting message only once
        if ! $progress_started; then
            progress_started=true
        fi

        # Display spinner on the same line
        printf "\r\e[96mINFO\e[0m Waiting for secret '%s' to be created %s" "$SECRET_NAME" "$CHAR"
        tput el  # Clear to the end of the line
    fi

    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Exit when max retries reached
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r"  # Move to the beginning of the line
        tput el      # Clear the entire line
        echo -e "\e[31mFAILED\e[0m Reached max retries, secret '$SECRET_NAME' was not created"
        exit 1
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

# Wait for $namespace namespace pods to be in 'Running' state
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started
namespace=$OPERATOR_NS

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
                printf "\r\e[96mINFO\e[0m All %s namespace pods are Running%*s\n" \
                       "$namespace" $((LINE_WIDTH - ${#namespace} - 28)) ""
            else
                echo -e "\e[96mINFO\e[0m All $namespace namespace pods are Running"
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
        printf "\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r\e[96mINFO\e[0m %s %s" "$MSG" "$CHAR"
    fi

    # 4. Handle timeout and retry
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r\e[31mFAILED\e[0m The %s namespace pods are not Running%*s\n" \
               "$namespace" $((LINE_WIDTH - ${#namespace} - 45)) ""
        exit 1
    fi
done

sleep 20

# Wait for all Cluster Operators (COs) to be Ready
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get Cluster Operator statuses: Available, Progressing, Degraded
    output=$(/usr/local/bin/oc get co --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    # If any CO is not Available/Progressing/Degraded as expected
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
        # Timeout handling
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r\e[31mFAILED\e[0m Cluster Operators not Ready%*s\n" $((LINE_WIDTH - 31)) ""
            exit 1
        fi
    else
        # All Cluster Operators are Ready
        if $progress_started; then
            printf "\r\e[96mINFO\e[0m All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        else
            printf "\e[96mINFO\e[0m All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        fi
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
