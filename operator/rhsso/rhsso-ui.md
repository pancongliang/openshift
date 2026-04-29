#### Installation and configuration the Red Hat Single Sign-On Operator
1. Install the Red Hat Single Sign-On Operator.  
```
# step 1
oc new-project rhsso

# step 2
Console -> OperatorHub -> Red Hat Single Sign-On Operator.
```

2. Create a Keycloak object in the rhsso project.
```
cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: rhsso-pv
  labels:
    app: keycloak
spec:
  capacity:
    storage: 1Gi
  accessModes:      
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /nfs/pv001
    server: 10.74.251.171
EOF

cat << EOF | oc apply -f -
apiVersion: keycloak.org/v1alpha1
kind: Keycloak
metadata:
  name: example-sso
  labels:
    app: sso
spec:
  instances: 1
  externalAccess:
    enabled: True
EOF
```

3. Check that the Keycloak object was created successfully.
```
oc get po -n rhsso
---
NAME                                   READY   STATUS    RESTARTS   AGE
keycloak-0                             1/1     Running   0          70s
keycloak-postgresql-64f4c9c68c-6ckfk   1/1     Running   0          19m
rhsso-operator-578c76f745-pmfxz        1/1     Running   0          20m
---
```

4. Find the Secret named "credential-example-sso" in the rhsso project, 
   which contains the login password of the RHSSO admin.
```
oc get secret credential-example-sso -o yaml -n rhsso | grep ADMIN
---
  ADMIN_PASSWORD: MkdCU0hjazVYQy1JQ3c9PQ==
  ADMIN_USERNAME: YWRtaW4=
---

echo LUFERjNSVVBSSHg5ekE9PQ== | base64 -d
---
2GBSHck5XC-ICw==
---

echo YWRtaW4= | base64 -d
---
admin
---
```

#### Configure Red Hat Single Sign-On
1. Login to the console of rhsso.
```
oc get route -n rhsso
---
NAME                       HOST/PORT                              PATH                          SERVICES   PORT       TERMINATION   WILDCARD
keycloak                   keycloak-rhsso.apps.ocp4.example.com                                 keycloak   keycloak   reencrypt     None
keycloak-metrics-rewrite   keycloak-rhsso.apps.ocp4.example.com   /auth/realms/master/metrics   keycloak   keycloak   reencrypt     None
---
```
2. Click Administration Console to login with "admin/2GBSHck5XC-ICw==".

3. Click "Master", then click "Add realm".

4. Set the "Name" to "OpenShift" in the "Add realm" page, and click the "Create" button.

5. At this point, the page will display the General information of the newly created OpenShift Realm, 
   and then click the "OpenID Endpoint Configuration" link in the box behind Endpoints.

6. Find the string "https://keycloak-rhsso.<base_domain>/auth/realms/OpenShift" behind the issuer in the newly popped-up page.
   This is the Issuer URL that will be used later in configuring Identity Providers.
```
{"issuer":"https://keycloak-rhsso.apps.ocp4.example.com/auth/realms/OpenShift"
```

#### Create Red Hat Single Sign-On User
1. Click the "Users" link in the left menu, then click "Add user".
2. On the "Add user" page set the Username to "test-user" and click "Save".
3. Click the "Credentials" button, set the password for the "test-user" user and click "Temporary/Set Password".


#### Create Red Hat Single Sign-On Client
1. Click the menu on the left to enter the configuration page of "Clients", 
   and then click the "Create" button on the right in the "Clients" page.
2. Set the Client ID to "openshift-demo" on the "Add Client" page, and click "Save".
3. On the Settings page of "openshift-demo", first change the Access Type to "confendial", 
   and then set the Valid Redirect URIs to "https://oauth-openshift.<base_domain>/*",
   For example "https://oauth-openshift.apps.ocp4.example.com/*", finally the Save button.
```
oc get route -n openshift-authentication
NAME              HOST/PORT                               PATH   SERVICES          PORT   TERMINATION            WILDCARD
oauth-openshift   oauth-openshift.apps.ocp4.example.com          oauth-openshift   6443   passthrough/Redirect   None
```

4. A new "Credentials" button will appear in the "openshift-demo" configuration page.
   Click the "Credentials" button and copy the Secret "CT4C1rCOmKh90r94uTglSUilVq5kUBYN" string.

#### Create and configure an Identity Provider for OpenShifts
* export router-ca certificate
```
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator
mv tls.crt route.ca.crt
```

* Create a Red Hat SSO-based Identity Provider

```
oc create secret generic openid-client-secret --from-literal=clientSecret=CT4C1rCOmKh90r94uTglSUilVq5kUBYN -n openshift-config
oc create configmap openid-route-ca --from-file=ca.crt=./route.ca.crt -n openshift-config

oc edit oauth/cluster
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
      issuer: https://keycloak-rhsso.apps.ocp4.example.com/auth/realms/OpenShift
    type: OpenID
    name: openid
```

5. Wait for the oauth pod restart to complete.
```
oc get po -n openshift-authentication
---
NAME                               READY   STATUS        RESTARTS   AGE
oauth-openshift-5745d4d7d9-92zhp   0/1     Pending       0          9s
oauth-openshift-686bdd4f8-2cwgv    1/1     Running       0          30h
oauth-openshift-686bdd4f8-g25gz    1/1     Running       0          30h
oauth-openshift-686bdd4f8-hzm45    1/1     Terminating   0          30h
---
```

#### Enable Red Hat Single Sign-On logout feature
```
# step 1
rhsso console -> Clients -> openshift-demo -> Settings -> Valid Redirect URIs -> Add "https://console-openshift-console.apps.ocp4.example.com/*"

# step 2
oc edit console.config.openshift.io cluster
spec:
  authentication:
    logoutRedirect: https://<KEYCLOAK_URL>/auth/realms/${MY_REALM_NAME}/protocol/openid-connect/logout?post_logout_redirect_uri=${CONSOLE_URL}&client_id=${USE_THE_CLIENTID_VALUE_FROM_OAUTH_CONFIG}

# e.g.
    logoutRedirect: https://keycloak-rhsso.apps.ocp4.example.com/auth/realms/OpenShift/protocol/openid-connect/logout?post_logout_redirect_uri=https://console-openshift-console.apps.ocp4.example.com&client_id=openshift-demo
```

