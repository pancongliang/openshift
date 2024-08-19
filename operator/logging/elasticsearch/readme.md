## Install and configure Red Hat Openshift Logging and elasticsearch operator

### Install Red Hat Openshift Logging and elasticsearch operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/01-deploy-operator.yaml | envsubst | oc apply -f -

  sleep 6
  
  oc patch installplan $(oc get ip -n openshift-operators-redhat  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators-redhat --type merge --patch '{"spec":{"approved":true}}'
  oc patch installplan $(oc get ip -n openshift-logging  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-logging --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-operators-redhat
  oc get ip -n openshift-logging
  ```
  

### Deploy ClusterLogging instance

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md)
  ```
  export STORAGE_CLASS_NAME="managed-nfs-storage"
  ```

* Create ClusterLogging instance
  ```
  # fluentd:
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-deploy-instance-fluentd.yaml | envsubst | oc apply -f -

  # or vector 
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-deploy-instance-vector.yaml | envsubst | oc apply -f -
  
  oc get po -n openshift-logging
  ```

### Search index in elasticsearch by keyword

* Find index
  ```
  oc exec -it -n openshift-logging -c elasticsearch $(oc get pod -n openshift-logging \
    -l cluster-name=elasticsearch -o jsonpath='{.items[0].metadata.name}') \
    -- curl --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key \
    --cacert /etc/elasticsearch/secret/admin-ca \
    -X GET "https://localhost:9200/_cat/indices?v"
  ```

* Search for keywords in a specific index
  ```
  export INDEX=app-000001
  export KEYWORD='Hello World'
  
  oc exec -it -n openshift-logging -c elasticsearch $(oc get pod -n openshift-logging \
    -l cluster-name=elasticsearch -o jsonpath='{.items[0].metadata.name}') \
    -- curl --cert /etc/elasticsearch/secret/admin-cert --key /etc/elasticsearch/secret/admin-key \
    --cacert /etc/elasticsearch/secret/admin-ca \
    -XGET "https://localhost:9200/${INDEX}/_search?pretty" -H 'Content-Type: application/json' \
    --data '{
      "query": {
        "match": {
          "message": "'"${KEYWORD}"'"
        }
      }
    }'
  ```
