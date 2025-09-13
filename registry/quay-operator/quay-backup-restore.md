
### Download and install necessary tools
~~~
wget https://github.com/mikefarah/yq/releases/download/v4.47.2/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

sudo curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
sudo rm -rf aws awscliv2.zip
~~~


### Verify that Quay superuser and robot accounts are logged in properly before restoring
~~~
QUAY_HOST=$(oc get route -n $QUAY_NAMESPACE --no-headers | awk '{print $1}' | grep '\-quay$')

podman login -u='quayadmin+admin' -p='N06EBN5D3RO4KL8FKEZI51T5IAVX7SN1CILWCAU1GYOP9POO7KYX8Q2QA707L46U' $QUAY_HOST --tls-verify=false
podman login -u quayadmin -p password $QUAY_HOST --tls-verify=false

podman pull quay.io/redhattraining/hello-world-nginx:v1.0
podman tag quay.io/redhattraining/hello-world-nginx:v1.0 $QUAY_HOST/quayadmin//hello-world-nginx:v1.0 --tls-verify=false
~~~

### Backing up Red Hat Quay 

#### Red Hat Quay configuration backup 
~~~
QUAY_NAMESPACE=quay-enterprise
QUAY_REGISTRY=$(oc get quayregistry -n $QUAY_NAMESPACE -o jsonpath='{.items[0].metadata.name}')

oc get quayregistry $QUAY_REGISTRY -n $QUAY_NAMESPACE -o json \
| jq 'del(.metadata.creationTimestamp, .metadata.finalizers, .metadata.generation, .metadata.resourceVersion, .metadata.uid, .status)' \
| yq e -P - > $HOME/quay-backup/quay-registry.yaml

oc get secret -n $QUAY_NAMESPACE $QUAY_REGISTRY-quay-registry-managed-secret-keys -o json \
| jq '{apiVersion, kind, metadata: {name: .metadata.name, namespace: .metadata.namespace}, type, data}' \
| yq e -P - > $HOME/quay-backup/managed-secret-keys.yaml

oc get secret -n $QUAY_NAMESPACE $(oc get quayregistry $QUAY_REGISTRY -n $QUAY_NAMESPACE  -o jsonpath='{.spec.configBundleSecret}') -o yaml > $HOME/quay-backup/config-bundle.yaml

oc exec -n $QUAY_NAMESPACE -it $(oc get pod -n $QUAY_NAMESPACE -l app=quay -o jsonpath='{.items[0].metadata.name}') -- cat /conf/stack/config.yaml > $HOME/quay-backup/quay_config.yaml

QUAY_DB_NAME=$(oc -n $QUAY_NAMESPACE rsh $(oc get pod -l app=quay -o name -n $QUAY_NAMESPACE | head -n 1) cat /conf/stack/config.yaml | awk -F"/" '/^DB_URI/ {print $4}')
~~~


#### Scaling down Red Hat Quay deployment
~~~
oc patch quayregistry $QUAY_REGISTRY -n $QUAY_NAMESPACE \
--type='json' -p='[
  {"op": "replace", "path": "/spec/components/2/overrides/replicas", "value": 0},
  {"op": "replace", "path": "/spec/components/3/overrides/replicas", "value": 0},
  {"op": "replace", "path": "/spec/components/4/overrides/replicas", "value": 0}
]'
# If the above command fails to reduce the size of the replica, use the following command to forcefully reduce the size of the replica
oc scale --replicas=0 deployment $(oc get deployment -n $QUAY_NAMESPACE |awk '/quay-app/ {print $1}') -n $QUAY_NAMESPACE 
oc scale --replicas=0 deployment $(oc get deployment -n $QUAY_NAMESPACE |awk '/quay-mirror/ {print $1}') -n $QUAY_NAMESPACE
oc scale --replicas=0 deployment $(oc get deployment -n $QUAY_NAMESPACE |awk '/clair-app/ {print $1}') -n $QUAY_NAMESPACE
~~~

#### Backing up the Red Hat Quay managed database 
~~~~
POSTGRES_POD=$(oc get pod -n $QUAY_NAMESPACE -l quay-component=postgres -o jsonpath='{.items[0].metadata.name}')
oc -n $QUAY_NAMESPACE exec $POSTGRES_POD -- /usr/bin/pg_dump -C $QUAY_DB_NAME  > backup.sql
~~~

#### Backing up the object storage
~~~
QUAY_CONFIG_SECRET=quay-config
mkdir $HOME/quay-backup/blobs
export AWS_ACCESS_KEY_ID=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("access_key")) | .access_key')
export AWS_SECRET_ACCESS_KEY=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("secret_key")) | .secret_key')
export AWS_S3_ENDPOINT=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("hostname")) | .hostname')
export AWS_S3_BUCKET=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("bucket_name")) | .bucket_name')

aws s3 sync --no-verify-ssl --endpoint http://$AWS_S3_ENDPOINT s3://$AWS_S3_BUCKET $HOME/quay-backup/blobs
~~~

#### Scale the Red Hat Quay deployment back up
~~~
oc patch quayregistry $QUAY_REGISTRY -n $QUAY_NAMESPACE \
--type='json' -p='[
  {"op": "replace", "path": "/spec/components/2/overrides/replicas", "value": 1},
  {"op": "replace", "path": "/spec/components/3/overrides/replicas", "value": 1},
  {"op": "replace", "path": "/spec/components/4/overrides/replicas", "value": 1}
]'

oc wait quayregistry $QUAY_REGISTRY --for=condition=Available=true -n $QUAY_NAMESPACE --timeout=10m
~~~

### Restoring Red Hat Quay

#### Restoring Red Hat Quay and its configuration from a backup
~~~
oc delete ns $OLD_QUAY_NAMESPACE

QUAY_NAMESPACE=quay-enterprise-test
oc new-project $QUAY_NAMESPACE

sed -i "s/namespace: quay-enterprise/namespace: $QUAY_NAMESPACE/" $HOME/quay-backup/config-bundle.yaml
sed -i "s/namespace: quay-enterprise/namespace: $QUAY_NAMESPACE/" $HOME/quay-backup/managed-secret-keys.yaml
sed -i "s/namespace: quay-enterprise/namespace: $QUAY_NAMESPACE/" $HOME/quay-backup/quay-registry.yaml

oc create -f $HOME/quay-backup/config-bundle.yaml
oc create -f $HOME/quay-backup/managed-secret-keys.yaml
oc create -f $HOME/quay-backup/quay-registry.yaml

QUAY_REGISTRY=$(oc get quayregistry -n $QUAY_NAMESPACE -o jsonpath='{.items[0].metadata.name}')
oc wait quayregistry $QUAY_REGISTRY --for=condition=Available=true -n $QUAY_NAMESPACE --timeout=10m
~~~

#### Scaling down Red Hat Quay deployment 
~~~
oc patch quayregistry $QUAY_REGISTRY -n $QUAY_NAMESPACE \
--type='json' -p='[
  {"op": "replace", "path": "/spec/components/2/overrides/replicas", "value": 0},
  {"op": "replace", "path": "/spec/components/3/overrides/replicas", "value": 0},
  {"op": "replace", "path": "/spec/components/4/overrides/replicas", "value": 0}
]'

oc get po -n $QUAY_NAMESPACE
~~~

#### Restoring Red Hat Quay database
~~~
POSTGRES_POD=$(oc get pod -n $QUAY_NAMESPACE -l quay-component=postgres -o jsonpath='{.items[0].metadata.name}')
oc cp $HOME/quay-backup/backup.sql -n $QUAY_NAMESPACE $POSTGRES_POD:/tmp/backup.sql
QUAY_DB_NAME=$(oc rsh -n $QUAY_NAMESPACE $POSTGRES_POD psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" | tr -d '[:space:]')

oc rsh -n $QUAY_NAMESPACE $POSTGRES_POD psql -U postgres -c "DROP DATABASE \"$QUAY_DB_NAME\";"
oc rsh -n $QUAY_NAMESPACE $POSTGRES_POD bash -c "psql -U postgres < /tmp/backup.sql"
~~~

#### Restore Quay object storage data
~~~
export AWS_ACCESS_KEY_ID=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("access_key")) | .access_key')
export AWS_SECRET_ACCESS_KEY=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("secret_key")) | .secret_key')
export AWS_S3_ENDPOINT=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("hostname")) | .hostname')
export AWS_S3_BUCKET=$(oc get secret quay-config -n $QUAY_NAMESPACE -o jsonpath="{.data.config\.yaml}" | base64 --decode | yq -r '.. | select(has("bucket_name")) | .bucket_name')

aws s3 sync --no-verify-ssl --endpoint http://$AWS_S3_ENDPOINT blobs  s3://$AWS_S3_BUCKET
~~~

#### Scaling up Red Hat Quay deployment
~~~
oc patch quayregistry $QUAY_REGISTRY -n $QUAY_NAMESPACE \
--type='json' -p='[
  {"op": "replace", "path": "/spec/components/2/overrides/replicas", "value": 1},
  {"op": "replace", "path": "/spec/components/3/overrides/replicas", "value": 1},
  {"op": "replace", "path": "/spec/components/4/overrides/replicas", "value": 1}
]'

oc wait quayregistry $QUAY_REGISTRY --for=condition=Available=true -n $QUAY_NAMESPACE --timeout=10m

oc get po -n $QUAY_NAMESPACE
~~~

### Verify that the Quay superuser and robot accounts are normal after restoration
~~~
QUAY_HOST=$(oc get route -n $QUAY_NAMESPACE --no-headers | awk '{print $1}' | grep '\-quay$')

podman login -u='quayadmin+admin' -p='N06EBN5D3RO4KL8FKEZI51T5IAVX7SN1CILWCAU1GYOP9POO7KYX8Q2QA707L46U' $QUAY_HOST --tls-verify=false
podman login -u quayadmin -p password $QUAY_HOST --tls-verify=false

podman pull $QUAY_HOST/quayadmin//hello-world-nginx:v1.0 --tls-verify=false
~~~

