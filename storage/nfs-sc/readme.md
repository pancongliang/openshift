## Deploy NFS StorageClass

### 1. Set Necessary Parameters
Set the required parameters for the NFS storage class.

```
export NAMESPACE="nfs-client-provisioner"
export NFS_SERVER_IP="10.184.134.128"
export NFS_DIR="/nfs"
```

### 2. Install and Configure the NFS Server
Install and configure the NFS server. Skip this step if it is already installed.

```
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-sc/01-install-nfs-package.sh

source 01-install-nfs-package.sh
```

### 3. Deploy NFS StorageClass
Use the script provided below to deploy the NFS StorageClass.

```
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-sc/02-deploy-nfs-storageclass.sh

source 02-deploy-nfs-storageclass.sh

oc get po -n $NAMESPACE
oc get sc
```

### 4. Test Mount
Deploy an application and test mounting the NFS StorageClass.

```
oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

oc set volumes deployment/nginx \
   --add --name mysql-storage --type pvc --claim-class managed-nfs-storage \
   --claim-mode RWX --claim-size 5Gi --mount-path /usr/share/nginx/html \
   --claim-name test-volume
```
