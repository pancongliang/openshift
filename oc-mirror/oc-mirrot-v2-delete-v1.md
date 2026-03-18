### Mirroring Operators using oc-mirror v1
~~~
export LOCAL_REGISTRY=mirror.registry.example.com:8443
cat > imageset-config.yaml << EOF
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
 registry:
   imageURL: $LOCAL_REGISTRY/mirror/metadata
   skipTLS: false
mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.20
    packages:
      - name: loki-operator
        channels:
          - name: stable-6.4
            minVersion: '6.4.3'
            maxVersion: '6.4.3'
EOF

oc-mirror --config=./imageset-config.yaml docker://${LOCAL_REGISTRY} --dest-skip-tls --v1
~~~

### Mirroring an Operator to a Local Directory using oc-mirror v2
~~~
cat > isc.yaml << EOF
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.20
    packages:
      - name: loki-operator
        channels:
          - name: stable-6.4
            minVersion: '6.4.3'
            maxVersion: '6.4.3'
EOF

mkdir olm
oc-mirror -c isc.yaml file://olm --v2
~~~

### Disable Internet Access(Only mirror.registry.example.com is allowed to be resolved.)
~~~
$ nslookup mirror.registry.example.com
Server:         10.184.134.30
Address:        10.184.134.30#53

Name:   mirror.registry.example.com
Address: 10.184.134.108

$ ping baidu.com
ping: baidu.com: Name or service not known

$ nslookup baidu.com
Server:         10.184.134.30
Address:        10.184.134.30#53

** server can't find baidu.com: REFUSED
~~~

### Remove Operators installed via v1 images using oc-mirror v2
~~~
cat > delete-isc.yaml << EOF
apiVersion: mirror.openshift.io/v2alpha1
kind: DeleteImageSetConfiguration
delete:
  operators:
    - catalog: $LOCAL_REGISTRY/redhat/redhat-operator-index:v4.20
      packages:
      - name: loki-operator
        minVersion: '6.4.3'
        maxVersion: '6.4.3'
EOF

oc-mirror delete --config=delete-isc.yaml --generate --delete-v1-images --workspace file://olm docker://$LOCAL_REGISTRY  --v2

oc-mirror delete --delete-yaml-file olm/working-dir/delete/delete-images.yaml docker://$LOCAL_REGISTRY --v2
~~~