### Forwarding logs to external third-party logging systems

* Download clusterlogforwarder template
  ~~~
  wget https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/clusterlogforwarder.yaml
  ~~~


### Deploy external log aggregator

* Deploy kafka in project kafka
  ~~~
  export NAMESPACE=kafka
  oc new-project $NAMESPACE

  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/kafka/01_og_amqstreams_template.yaml -p AMQ_NAMESPACE=$NAMESPACE |oc create -f -
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/kafka/02_sub_amq_streams.yaml
  # Waiting util the operator is running
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/kafka/03_kafka_my-cluster-no-authorization.yaml
  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/kafka/04_kafka_topics_template.yaml -p KAFKA_TOPIC=topic-logging-app| oc create -f -

  # View the logs forwarded to Kafka
  sh-4.4$ ls /var/lib/kafka/data/kafka-log0/topic-logging-app-0/
  sh-4.4$ /opt/kafka/bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log \ --deep-iteration --print-data-log 
  ~~~

* Deploy syslog in project syslog
  ~~~
  oc new-project syslog
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/syslog/01_rsyslogserver_configmap.yaml
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/syslog/02_rsyslogserver_deployment.yaml
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/syslog/03_rsyslogserver_svc.yaml
  ~~~
  
* Deploy fluentd receiver in project fluentd
  ~~~
  oc new-project fluentd
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/fluentd/01_configmap.yaml
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/fluentd/02.deployment.yaml
  oc expose deployment/fluentdserver
  
  # View the logs forwarded to fluentd
  cd /fluentd/log
  ~~~
  
* Deploy Elasticsearch in project elasticsearch
  ~~~
  export NAMESPACE=elasticsearch
  oc new-project $NAMESPACE
  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/es/01_configmap.yaml -p NAMESPACE=$NAMESPACE |oc create -f -
  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/clf/es/02_deployment.yaml -p NAMESPACE=$NAMESPACE |oc create -f -
  oc expose deployment/elasticsearch-server
  ~~~
