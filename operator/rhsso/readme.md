### Installing the Red Hat Single Sign-On Operator on a cluster

* Installing RHSSO Operator from the command line
  ```
  export NAMESPACE=rhsso
  export CHANNEL="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/01-deploy-operator.yaml | envsubst | oc apply -f -
  oc patch installplan $(oc get ip -n ${NAMESPACE} -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n ${NAMESPACE} --type merge --patch '{"spec":{"approved":true}}'
  ```

### Create Keycloak instance and view the console URL and username/password information

* Create pv with size 1GB or deploy [NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md),The following is an example of nfs pv
  
  ```
  export NFS_PATH="/nfs/pv005"
  export NFS_IP="10.74.251.171"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/02-create-keycloak-pv.yaml | envsubst | oc apply -f -
  ```
  
* Create Keycloak
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/02-create-keycloak.yaml | envsubst | oc apply -f -
  oc get po -n ${NAMESPACE}
  ```
  
* Keycloak console URL and username/password information
  ```
  oc get route keycloak -n ${NAMESPACE}
  NAME       HOST/PORT                              PATH   SERVICES   PORT       TERMINATION   WILDCARD
  keycloak   keycloak-rhsso.apps.ocp4.example.com          keycloak   keycloak   reencrypt     None

  oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_USERNAME}' -n ${NAMESPACE} | base64 -d && echo
  admin
  
  oc get secret credential-example-sso -o=jsonpath='{.data.ADMIN_PASSWORD}' -n ${NAMESPACE} | base64 -d && echo
  pARXgj7Nz7LwQw==
  ```
  
### Configuring the Red Hat Single Sign-On Operator

* Create realm custom resource
    > [!NOTE]  
    > Can only create or delete realms by creating or deleting the YAML file, and changes appear in the Red Hat Single Sign-On admin console.
    > However changes to the admin console are not reflected back and updates of the CR after the realm is created are not supported.
  ```  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/03-create-keycloak-realm.yaml | envsubst | oc apply -f -
  ```

* Create client custom resource
    > [!NOTE]  
    > Can update the YAML file and changes appear in the Red Hat Single Sign-On admin console,
    > however changes to the admin console do not update the custom resource.
  ```
  export OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
  export CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/04-create-keycloak-client.yaml | envsubst | oc apply -f -
  ```
  
* Create RH-SSO user, If need to create multiple users, repeat this step after changing the variable value
    > [!NOTE]  
    > Can update properties in the YAML file and changes appear in the Red Hat Single Sign-On admin console,
    > however changes to the admin console do not update the custom resource.
  ```
  export USER_NAME=rhadmin
  export PASSWORD=redhat
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/05-create-keycloak-user.yaml | envsubst | oc apply -f -
  ```

### Create and configure Identity Providers for OpenShift

* Create client authenticator secret and configmap containing router-ca certificate
  ```
  oc create secret generic openid-client-secret --from-literal=clientSecret=$(oc -n ${NAMESPACE} get secret keycloak-client-secret-example-client -o jsonpath='{.data.CLIENT_SECRET}' | base64 -d) -n openshift-config
  oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator
  oc create configmap openid-route-ca --from-file=ca.crt=tls.crt -n openshift-config
  ```

* Configure Identity Providers
  ```
  export KEYCLOAK_HOST=$(oc get route keycloak -n ${NAMESPACE} --template='{{.spec.host}}')
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/06-configure-identity-provider.yaml | envsubst | oc apply -f -
  ```

* Wait for the pod restart to complete
  ```
  oc get po -n openshift-authentication
  ```

### Configure logout Redirect in OpenShift
* Specify the URL of the page to load when a user logs out of the web console.
  If do not specify a value, the user returns to the login page for the web console.
  Specifying a logoutRedirect URL allows your users to perform single logout (SLO) through the identity provider to destroy their single sign-on session.

  ```
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

* Test whether login and logout are normal
  
