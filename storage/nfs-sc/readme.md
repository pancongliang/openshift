## Deploy NFS StorageClass

### 1. Install and Configure the NFS Server

Set Necessary Parameters
```
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-sc/01-install-nfs-package.sh

vim 01-install-nfs-package.sh
```

Install and configure the NFS server. Skip this step if it is already installed
```
bash 01-install-nfs-package.sh
```

### 2. Deploy NFS StorageClass

Set Necessary Parameters
```
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-sc/02-deploy-nfs-storageclass.sh

vim 02-deploy-nfs-storageclass.sh
```

Use the script provided below to deploy the NFS StorageClass
```
bash 02-deploy-nfs-storageclass.sh
```

### 3. Check NFS Storage Class
Check the NFS Pod and test the mount
```
oc get po -n $NAMESPACE
oc get sc

oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

oc set volumes deployment/nginx \
   --add --name mysql-storage --type pvc --claim-class managed-nfs-storage \
   --claim-mode RWX --claim-size 5Gi --mount-path /usr/share/nginx/html \
   --claim-name test-volume
```
