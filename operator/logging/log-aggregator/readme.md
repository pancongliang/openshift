## Install and configure external log aggregator


### Forwarding logs to external third-party logging systems

* Download clusterlogforwarder template
  ```
  wget https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/clusterlogforwarder.yaml
  ```


### Deploy external log aggregator

* Deploy kafka in project kafka
  ```
  export NAMESPACE=kafka
  oc new-project $NAMESPACE

  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/kafka/01-og-amqstreams-template.yaml -p AMQ_NAMESPACE=$NAMESPACE |oc create -f -
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/kafka/02-sub-amq-streams.yaml  
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/kafka/03-kafka-my-cluster-no-authorization.yaml
  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/kafka/04-kafka-topics-template.yaml -p KAFKA_TOPIC=topic-logging-app| oc create -f -

  # View the logs forwarded to Kafka
  sh-4.4ls /var/lib/kafka/data/kafka-log0/topic-logging-app-0/
  sh-4.4/opt/kafka/bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log \ --deep-iteration --print-data-log 
  ```

* Deploy syslog in project syslog
  ```
  export NAMESPACE=syslog
  oc new-project $NAMESPACE
  
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/syslog/01-rsyslogserver-configmap.yaml
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/syslog/02-rsyslogserver-deployment.yaml
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/syslog/03-rsyslogserver-svc.yaml
  ```
  
* Deploy fluentd receiver in project fluentd
  ```
  export NAMESPACE=fluentd
  oc new-project $NAMESPACE
  
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/fluentd/01-configmap.yaml
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/fluentd/02-deployment.yaml
  oc expose deployment/fluentdserver
  
  # View the logs forwarded to fluentd
  cd /fluentd/log
  ```
  
* Deploy Elasticsearch in project elasticsearch
  ```
  export NAMESPACE=elasticsearch
  oc new-project $NAMESPACE
  
  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/es/01-configmap.yaml -p NAMESPACE=$NAMESPACE |oc create -f -
  oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/log-aggregator/es/02-deployment.yaml -p NAMESPACE=$NAMESPACE |oc create -f -
  oc expose deployment/elasticsearch-server
  ```
