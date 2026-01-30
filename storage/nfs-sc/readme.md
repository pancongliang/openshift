### Deploy NFS StorageClass

```
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-sc/nfs-sc.sh

$ vim nfs-sc.sh
export NFS_SERVER_IP="10.184.134.128"
export NFS_DIR="/nfs"

bash inst-nfs-sc.sh
```


