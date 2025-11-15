## Install and configure Red Hat Openshift Logging and elasticsearch operator

### Install Red Hat Openshift Logging and elasticsearch operator

* Install the Operator using the default namespace
  ```
  export ES_SUB_CHANNEL="stable"
  export LOGGING_SUB_CHANNEL="stable-5.9"
  export CATALOG_SOURCE="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/01-operator.yaml | envsubst | oc apply -f -
  export OPERATOR_NS="openshift-logging"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  sleep 3
  export OPERATOR_NS="openshift-operators-redhat"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```
  

### Deploy ClusterLogging instance

* Deploy [NFS Storage Class](/storage/nfs-sc/readme.md)
  ```
  export STORAGE_CLASS_NAME="managed-nfs-storage"
  ```

* Create ClusterLogging instance
  ```
  # fluentd:
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-fluentd.yaml | envsubst | oc apply -f -

  # or vector 
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/elasticsearch/02-instance-vector.yaml | envsubst | oc apply -f -
  
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
