

**Download clusterlogforwarder template**
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/loging/clusterlogforwarder.yaml
~~~

**Deploy kafka in project amq-aosqe** 
~~~
oc new-project amq

oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/kafka/01_og_amqstreams_template.yaml -p AMQ_NAMESPACE=amq-aosqe |oc create -f -
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/kafka/02_sub_amq_streams.yaml

# Waiting util the operator is running
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/kafka/03_kafka_my-cluster-no-authorization.yaml
oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/kafka/04_kafka_topics_template.yaml -p KAFKA_TOPIC=topic-logging-app| oc create -f -
~~~

**Deploy syslog in project syslog-aosqe**
~~~
oc new-project syslog
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/syslog/01_rsyslogserver_configmap.yaml
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/syslog/02_rsyslogserver_deployment.yaml
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/syslog/03_rsyslogserver_svc.yaml
~~~

**Deploy fluentd receiver in project fluentd-aosqe**
~~~
oc new-project fluentd
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/fluentd/01_configmap.yaml
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/fluentd/02.deployment.yaml
oc expose deployment/fluentdserver
~~~

**Deploy Elasticsearch in project es-aosqe**
~~~
oc new-project elasticsearch

oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/elasticsearch/01_configmap.yaml -p NAMESPACE=$project_name |oc create -f -

oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/elasticsearch/02_deployment.yaml -p NAMESPACE=$project_name |oc create -f -

oc expose deployment/elasticsearch-server
~~~
