#!/bin/bash
set -u
set -o pipefail

# Applying environment variables
# Need a default storageclass
export USER_NAME=rhadmin
export PASSWORD=redhat
export CHANNEL="stable"
export NAMESPACE="rhsso"
export CATALOG_SOURCE_NAME="redhat-operators"

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


# Print task title
PRINT_TASK "[TASK: Deploying Single Sign-On Operator]"

# Uninstall first
echo "info: [uninstall old rhsso resources...]"
oc delete configmap openid-route-ca -n openshift-config &>/dev/null
oc delete secret openid-client-secret -n openshift-config &>/dev/null
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/05-keycloak-user.yaml | envsubst | oc delete -f - &>/dev/null
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/04-keycloak-client.yaml | envsubst | oc delete -f - &>/dev/null
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/03-keycloak-realm.yaml | envsubst | oc delete -f - &>/dev/null
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/02-keycloak.yaml | envsubst | oc delete -f - &>/dev/null
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/01-operator.yaml | envsubst | oc delete -f - &>/dev/null

# Install the RHSSO operator
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/01-operator.yaml | envsubst | oc apply -f -  >/dev/null
run_command "[install rhsso operator]"

# Approve the install plan
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash  &>/dev/null
run_command "[approve the install plan]"

sleep 30

# Create the Keycloak resource
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/02-keycloak.yaml | envsubst | oc create -f - >/dev/null
run_command "[create keycloak Instance]"

sleep 15

# Wait for Keycloak pods to be in 'Running' state
# Initialize progress tracking
progress_started=false

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 1.5
    else
        # Close the progress indicator if it was started
        if $progress_started; then
            echo "]"
        fi

        echo "ok: [all keycloak pods are in 'running' state]"
        break
    fi
done


# Create the Keycloak realm resource
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/03-keycloak-realm.yaml | envsubst | oc create -f - >/dev/null
run_command "[create realm custom resource]"

# Get OpenShift OAuth and Console route details
export OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
export CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')

# Create the Keycloak client resource
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/04-keycloak-client.yaml | envsubst | oc create -f - >/dev/null
run_command "[create client custom resource]"

# Waiting for keycloak-client-secret-example-client secret to be created
sleep 10

# Initialize progress tracking
progress_started=false

while true; do
    # Check if the secret exists
    secret_exists=$(oc get secret -n "$NAMESPACE" keycloak-client-secret-example-client --no-headers 2>/dev/null)
    
    if [ -n "$secret_exists" ]; then
        # If progress was displayed, close it properly
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [keycloak-client-secret-example-client secret is created]"
        break
    else
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for keycloak-client-secret-example-client secret to be created"
            progress_started=true  # Mark progress as started
        fi
        
        # Print progress indicator
        echo -n '.'
        sleep 15
    fi
done


# Create a Keycloak user
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/05-keycloak-user.yaml | envsubst | oc apply -f - >/dev/null
run_command "[create a user named $USER_NAME]"

sleep 5

oc adm policy add-cluster-role-to-user cluster-admin $USER_NAME &>/dev/null     
run_command "[grant cluster-admin privileges to the $USER_NAME account]"

# Create client authenticator secret and ConfigMap containing router CA certificate
oc create secret generic openid-client-secret --from-literal=clientSecret=$(oc -n ${NAMESPACE} get secret keycloak-client-secret-example-client -o jsonpath='{.data.CLIENT_SECRET}' | base64 -d) -n openshift-config >/dev/null
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator >/dev/null

sleep 5

oc create configmap openid-route-ca --from-file=ca.crt=tls.crt -n openshift-config >/dev/null
run_command "[create client authenticator secret and configmap containing router-ca certificate]"
rm -rf tls.crt >/dev/null

# Apply Identity Provider configuration
export KEYCLOAK_HOST=$(oc get route keycloak -n ${NAMESPACE} --template='{{.spec.host}}')
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/06-patch-identity-provider.yaml | envsubst | oc replace -f - >/dev/null
# curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/06-identity-provider.yaml | envsubst | oc replace -f - >/dev/null
run_command "[apply identity provider configuration]"


# Wait for OpenShift authentication pods to be in 'Running' state
export AUTH_NAMESPACE="openshift-authentication"
progress_started=false

while true; do
    # Get the status of all pods
    output=$(oc get po -n "$AUTH_NAMESPACE" --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 10
    else
        # Close the progress indicator if it was started
        if $progress_started; then
            echo "]"
        fi

        echo "ok: [all oauth pods are in 'running' state]"
        break
    fi
done


# Configure OpenShift console logout redirection to Keycloak
KEYCLOAK_CLIENT_NAME='example-client'
KEYCLOAK_CLIENT_SECRET="keycloak-client-secret-${KEYCLOAK_CLIENT_NAME}"
OPENID_CLIENT_ID=$(oc get secret "$KEYCLOAK_CLIENT_SECRET" -n rhsso -o jsonpath='{.data.CLIENT_ID}' | base64 -d)
KEYCLOAK_HOST=$(oc get route keycloak -n $NAMESPACE -o=jsonpath='{.spec.host}')
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
)" >/dev/null
run_command "[configuring console logout redirection]"


# Retrieve Keycloak route
KEYCLOAK_HOST=$(oc get route keycloak -o jsonpath='{.spec.host}' -n ${NAMESPACE})

# Retrieve Keycloak admin credentials
KEYCLOAK_ADMIN_USER=$(oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_USERNAME}' -n ${NAMESPACE} | base64 -d)
KEYCLOAK_ADMIN_PASSWORD=$(oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_PASSWORD}' -n ${NAMESPACE} | base64 -d)

# Print variables for verification (optional)
echo "info: [keycloak host: $KEYCLOAK_HOST]"
echo "info: [keycloak console username: $KEYCLOAK_ADMIN_USER]"
echo "info: [keycloak console password: $KEYCLOAK_ADMIN_PASSWORD]"
echo "info: [user created by keycloak: $USER_NAME/$PASSWORD]"
