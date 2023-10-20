# Configuring an htpasswd identity provider

### Configuring an htpasswd identity provider

* Install httpd-tools
  ```
  yum install httpd-tools
  ```

### Creating an htpasswd file using httpd-tools
* Create or update flat file with a user name and hashed password
  ```
  htpasswd -c -B -b <htpasswd_file> <user_name> <password>
  htpasswd -c -B -b users.htpasswd admin redhat
  ```
* Continue to add or update credentials to the file:  
  ```
  htpasswd -c -B -b users.htpasswd admin01 redhat
  ```

### Creating the htpasswd secret
* Create a Secret object that contains the htpasswd users file
  ```
  oc create secret generic htpasswd-secret --from-file=users.htpasswd -n openshift-config
  ```

### Sample htpasswd CR
* The following custom resource (CR) shows the parameters and acceptable values for an htpasswd identity provider
  ```
  cat <<EOF | oc apply -f -
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
  EOF
  ```
