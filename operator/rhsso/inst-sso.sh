#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [Line $LINENO: Command \`$BASH_COMMAND\`]"; exit 1' ERR

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
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}


# Step 0:
PRINT_TASK "TASK [Uninstall old rhsso resources]"

# Uninstall first
echo "info: [Uninstall old rhsso resources...]"
oc delete configmap openid-route-ca -n openshift-config >/dev/null 2>&1 || true
oc delete secret openid-client-secret -n openshift-config >/dev/null 2>&1 || true
oc delete keycloakuser --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete keycloakclient --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete keycloakrealm --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete keycloak --all -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete operatorgroup rhsso-operator-group $OPERATOR_NS >/dev/null 2>&1 || true
oc delete sub rhsso-operator -n $OPERATOR_NS >/dev/null 2>&1 || true
oc get csv -n $OPERATOR_NS -o name | grep rhsso-operator | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n $OPERATOR_NS >/dev/null 2>&1 || true
oc delete ns $OPERATOR_NS >/dev/null 2>&1 || true

# Add an empty line after the task
echo

# Step 1:
PRINT_TASK "TASK [Deploying Single Sign-On Operator]"

# Install the RHSSO operator
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/01-operator.yaml | envsubst | oc apply -f - >/dev/null 2>&1
run_command "[Install rhsso operator]"

# Approve the install plan
echo -e "\e[96mINFO\e[0m The CSR approval is in progress..."
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash >/dev/null 2>&1
run_command "Approved the rhsso operator install plan]"


# Wait for rhsso-operator pods to be in 'Running' state
OPERATOR_NS="rhsso"
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=rhsso-operator

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$OPERATOR_NS" --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
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

sleep 30

# Create the Keycloak resource
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/02-keycloak.yaml | envsubst | oc create -f - >/dev/null 2>&1
run_command "[Create keycloak instance]"

sleep 15

# Wait for Keycloak pods to be in 'Running' state
OPERATOR_NS="rhsso"
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=keycloak

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$OPERATOR_NS" --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
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

# Create the Keycloak realm resource
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/03-keycloak-realm.yaml | envsubst | oc create -f - >/dev/null 2>&1
run_command "[Create realm custom resource]"

# Get OpenShift OAuth and Console route details
export OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
export CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')

# Create the Keycloak client resource
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/04-keycloak-client.yaml | envsubst | oc create -f - >/dev/null 2>&1
run_command "[Create client custom resource]"

# Waiting for keycloak-client-secret-example-client secret to be created
sleep 10

# Initialize progress tracking
# Configuration
OPERATOR_NS="rhsso" 
SECRET_NAME="keycloak-client-secret-example-client"
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0

while true; do
    # Check if the secret exists
    secret_exists=$(oc get secret -n "$OPERATOR_NS" "$SECRET_NAME" --no-headers 2>/dev/null || true)
    
    if [ -n "$secret_exists" ]; then
        # If progress was displayed, close it properly
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [The secret $SECRET_NAME has been created]"
        break
    else
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for $SECRET_NAME secret to be created"
            progress_started=true  # Mark progress as started
        fi
        
        # Print progress indicator
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [Reached max retries, $SECRET_NAME secret was not created]"
            exit 1 
        fi
    fi
done

# Create a Keycloak user
oc delete user $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/05-keycloak-user.yaml | envsubst | oc apply -f - >/dev/null 2>&1
run_command "[Create a user named $KEYCLOAK_REALM_USER]"

sleep 5

oc adm policy add-cluster-role-to-user cluster-admin $KEYCLOAK_REALM_USER >/dev/null 2>&1 || true
run_command "[Grant cluster-admin privileges to the $KEYCLOAK_REALM_USER account]"

# Create client authenticator secret and ConfigMap containing router CA certificate
oc create secret generic openid-client-secret --from-literal=clientSecret=$(oc -n ${OPERATOR_NS} get secret keycloak-client-secret-example-client -o jsonpath='{.data.CLIENT_SECRET}' | base64 -d) -n openshift-config >/dev/null 2>&1

sudo rm -rf tls.crt >/dev/null 2>&1
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator --confirm >/dev/null >/dev/null 2>&1

sleep 5

oc create configmap openid-route-ca --from-file=ca.crt=tls.crt -n openshift-config >/dev/null 2>&1
run_command "[Create client authenticator secret and configmap containing router-ca certificate]"
sudo rm -rf tls.crt >/dev/null 2>&1

# Apply Identity Provider configuration
export KEYCLOAK_HOST=$(oc get route keycloak -n ${OPERATOR_NS} --template='{{.spec.host}}')
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/06-patch-identity-provider.yaml | envsubst | oc replace -f - >/dev/null 2>&1
# curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/06-identity-provider.yaml | envsubst | oc apply -f - >/dev/null 2>&1
run_command "[Apply identity provider configuration]"


# Wait for OpenShift authentication pods to be in 'Running' state
NAMESPACE="openshift-authentication"
MAX_RETRIES=180
SLEEP_INTERVAL=5
progress_started=false
retry_count=0
pod_name=oauth

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

# Retrieve Keycloak route
KEYCLOAK_HOST=$(oc get route keycloak -o jsonpath='{.spec.host}' -n ${OPERATOR_NS})

# Retrieve Keycloak admin credentials
KEYCLOAK_ADMIN_USER=$(oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_USERNAME}' -n ${OPERATOR_NS} | base64 -d)
KEYCLOAK_ADMIN_PASSWORD=$(oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_PASSWORD}' -n ${OPERATOR_NS} | base64 -d)

# Print variables for verification (optional)
echo "info: [Keycloak host: $KEYCLOAK_HOST]"
echo "info: [Keycloak console username: $KEYCLOAK_ADMIN_USER]"
echo "info: [Keycloak console password: $KEYCLOAK_ADMIN_PASSWORD]"
echo "info: [User created by keycloak: $KEYCLOAK_REALM_USER/$KEYCLOAK_REALM_PASSWORD]"

# Add an empty line after the task
echo
