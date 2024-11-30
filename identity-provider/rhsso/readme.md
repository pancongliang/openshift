## Install and configure Red Hat Single Sign-On Operator


### Installing the Red Hat Single Sign-On Operator on a cluster

* Installing RHSSO Operator from the command line
  ```
  export NAMESPACE=rhsso
  export CHANNEL="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/identity-provider/rhsso/01-operator.yaml | envsubst | oc apply -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create Keycloak instance and view the console URL and username/password information

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md),If the current environment already exists, skip this step.
  
* Create Keycloak
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/identity-provider/rhsso/02-keycloak.yaml | envsubst | oc apply -f -
  oc get po -n ${NAMESPACE}
  ```
  
* Keycloak console URL and username/password information
  ```
  oc get route keycloak -o jsonpath='{.spec.host}' -n ${NAMESPACE}
  keycloak-rhsso.apps.ocp4.example.com

  oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_USERNAME}' -n ${NAMESPACE} | base64 -d && echo
  admin
  
  oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_PASSWORD}' -n ${NAMESPACE} | base64 -d && echo
  pARXgj7Nz7LwQw==
  ```
  
### Configuring the Red Hat Single Sign-On Operator

* Create realm custom resource
  > **Note**  
  > Can only create or delete realms by creating or deleting the YAML file, and changes appear in the Red Hat Single Sign-On admin console.
  > However changes to the admin console are not reflected back and updates of the CR after the realm is created are not supported.

  ```  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/identity-provider/rhsso/03-keycloak-realm.yaml | envsubst | oc apply -f -
  ```

* Create client custom resource
  > **Note**  
  > Can update the YAML file and changes appear in the Red Hat Single Sign-On admin console,
  > however changes to the admin console do not update the custom resource.
  ```
  export OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
  export CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/identity-provider/rhsso/04-keycloak-client.yaml | envsubst | oc apply -f -
  ```
  
* Create RH-SSO user, If need to create multiple users, repeat this step after changing the variable value
  > **Note**  
  > Can update properties in the YAML file and changes appear in the Red Hat Single Sign-On admin console,
  > however changes to the admin console do not update the custom resource.
  ```
  export USER_NAME=rhadmin
  export PASSWORD=redhat
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/identity-provider/rhsso/05-keycloak-user.yaml | envsubst | oc apply -f -
  ```

### Create and configure Identity Providers for OpenShift

* Create client authenticator secret and configmap containing router-ca certificate
  ```
  oc create secret generic openid-client-secret --from-literal=clientSecret=$(oc -n ${NAMESPACE} get secret keycloak-client-secret-example-client -o jsonpath='{.data.CLIENT_SECRET}' | base64 -d) -n openshift-config
  oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator
  oc create configmap openid-route-ca --from-file=ca.crt=tls.crt -n openshift-config && rm -rf tls.crt
  ```

* Configure Identity Providers
  ```
  export KEYCLOAK_HOST=$(oc get route keycloak -n ${NAMESPACE} --template='{{.spec.host}}')
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/identity-provider/rhsso/06-identity-provider.yaml | envsubst | oc apply -f -
  ```

* Wait for the pod restart to complete
  ```
  oc get po -n openshift-authentication
  ```

### Configure logout Redirect in OpenShift
* Set up RHSSO logout and redirection for OpenShift Console
  ```
  export NAMESPACE=rhsso
  export KEYCLOAK_HOST=$(oc get route keycloak -n $NAMESPACE -o=jsonpath='{.spec.host}')
  export CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')
  oc patch console.config.openshift.io cluster --type merge --patch "$(cat <<EOF
  {
    "spec": {
      "authentication": {
        "logoutRedirect": "https://${KEYCLOAK_HOST}/auth/realms/OpenShift/protocol/openid-connect/logout?post_logout_redirect_uri=https://${CONSOLE_HOST}&client_id=openshift-demo"
      }
    }
  }
  EOF
  )"
  ```

* Set up RHSSO logout and redirection for OpenShift GitOps
  ```
  NAMESPACE=rhsso
  GITOPS_HOST=$(oc get route openshift-gitops-server -o jsonpath='{.spec.host}' -n openshift-gitops)
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/identity-provider/rhsso/04-keycloak-gitops-client.yaml | envsubst | oc apply -f -
  
  # No changes required
  KEYCLOAK_NAMESPACE=$NAMESPACE
  KEYCLOAK_CLIENT_NAME='gitops-client'
  KEYCLOAK_HOST=$(oc get route keycloak -n ${KEYCLOAK_NAMESPACE} --template='{{.spec.host}}')
  KEYCLOAK_CLIENT_SECRET=$(oc get keycloakclients.keycloak.org -n $KEYCLOAK_NAMESPACE $KEYCLOAK_CLIENT_NAME -o jsonpath='{.status.secondaryResources.Secret[0]}')
  KEYCLOAK_REALM_NAME=$(oc get keycloakrealms -n "$KEYCLOAK_NAMESPACE" -o=jsonpath='{.items[0].metadata.name}')
  REALM=$(oc get keycloakrealms "$KEYCLOAK_REALM_NAME" -n "$KEYCLOAK_NAMESPACE" -o=jsonpath='{.spec.realm.realm}')
  OPENID_CLIENT_ID=$(oc get secret "$KEYCLOAK_CLIENT_SECRET" -n rhsso -o jsonpath='{.data.CLIENT_ID}' | base64 -d)
  OPENID_CLIENT_SECRET=$(oc get secret "$KEYCLOAK_CLIENT_SECRET" -n rhsso -o jsonpath='{.data.CLIENT_SECRET}')
  OPENID_ISSUER="$KEYCLOAK_HOST/auth/realms/$REALM"
  GITOPS_HOST=$(oc get route openshift-gitops-server -o jsonpath='{.spec.host}' -n openshift-gitops)
  ARGOCD_CR_NAME=$(oc get argocd -n openshift-gitops -o jsonpath='{.items[0].metadata.name}')
  oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator
  ROOT_CA=$(cat "tls.crt" | sed 's/^/      /')
  ```

  ```
  oc -n openshift-gitops patch $ARGOCD_CR_NAME openshift-gitops --type='json' -p='[{"op": "remove", "path": "/spec/sso"}]'
  oc patch secret argocd-secret -n openshift-gitops --type merge --patch "{\"data\":{\"oidc.keycloak.clientSecret\":\"$OPENID_CLIENT_SECRET\"}}"

  cat << EOF | oc apply -f -
  apiVersion: argoproj.io/v1beta1
  kind: ArgoCD
  metadata:
    name: $ARGOCD_CR_NAME
    namespace: openshift-gitops
  spec:
    oidcConfig: |
      name: openid
      issuer: https://$OPENID_ISSUER
      clientID: $OPENID_CLIENT_ID
      clientSecret: $OPENID_CLIENT_SECRET
      requestedScopes: ["openid", "profile", "email"]
      logoutURL: https://$OPENID_ISSUER/protocol/openid-connect/logout?post_logout_redirect_uri=https://$GITOPS_HOST&client_id=$OPENID_CLIENT_ID
      rootCA: |
  $(cat "tls.crt" | sed 's/^/      /')
  EOF

  oc -n openshift-gitops rollout restart deployment openshift-gitops-server
  rm -rf config.yaml tls.crt
  ```
  
