### Log Aggregator pod
- [Deploy Kafka](/operator/logging/log-aggregator.md#deploy-kafka)
- [Deploy Syslog](/operator/logging/log-aggregator.md#deploy-syslog)
- [Deploy Fluentd Receiver](/operator/logging/log-aggregator.md#deploy-fluentd-receiver)
- [Deploy Elasticsearch](/operator/logging/log-aggregator.md#deploy-elasticsearch)


### Deploy kafka
```bash
oc new-project kafka
cat > og-amqstreams-template.yaml << EOF
kind: Template
apiVersion: template.openshift.io/v1
metadata:
  name: external-log-store-template
objects:
- apiVersion: v1
  data:
    elasticsearch.yml: |
      node.name:  ${NAME}
      cluster.name: ${NAME}
      discovery.zen.minimum_master_nodes: 1
      network.host: 0.0.0.0
      http.port: 9200
      http.host: 0.0.0.0
      transport.host: 127.0.0.1
      discovery.type: single-node
      xpack.security.enabled: false
      xpack.security.authc.api_key.enabled: false
      xpack.monitoring.enabled : false
      xpack.license.self_generated.type: basic
      xpack.security.http.ssl.enabled: false
  kind: ConfigMap
  metadata:
    name: ${NAME}
    namespace: ${NAMESPACE}
parameters:
- name: NAME
  value: elasticsearch-server
- name: NAMESPACE
  value: openshift-logging
EOF

cat > sub-amqstreams.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: amq-streams
spec:
  channel: stable
  installPlanApproval: Automatic
  name: amq-streams
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  
cat > kafka-my-cluster-no-authorization.yaml << EOF
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
spec:
  kafka:
    replicas: 1 
    version: 3.3.1
    resources: 
      requests:
        memory: 2Gi
        cpu: "1"
      limits:
        memory: 2Gi
        cpu: "1"
    jvmOptions: 
      -Xms: 1024m
      -Xmx: 1024m
    config:
      log.message.format.version: "3.2.3"
      offsets.topic.replication.factor: 1
      transaction.state.log.min.isr: 1
      transaction.state.log.replication.factor: 1
      ssl.cipher.suites: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384" 
      ssl.enabled.protocols: "TLSv1.2"
      ssl.protocol: "TLSv1.2"
      message.max.bytes: 10485760
    listeners: 
      - name: plain 
        port: 9092 
        type: internal 
        tls: false 
        configuration:
          useServiceDnsDomain: true 
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication: 
          type: tls
    storage:
      type: ephemeral
  zookeeper:
    replicas: 1
    storage:
      type: ephemeral
  entityOperator:
    topicOperator:
      reconciliationIntervalSeconds: 90
    userOperator:
      reconciliationIntervalSeconds: 120
EOF
  
cat > kafka-topics-template.yaml << EOF
kind: Template
apiVersion: template.openshift.io/v1
metadata:
  name: amq-consumer
  annotations:
    description: "Deploy AMQ "
    tags: "amq-aosqe"
objects:
- apiVersion: kafka.strimzi.io/v1beta2
  kind: KafkaTopic
  metadata:
    name: ${KAFKA_TOPIC}
    labels:
      strimzi.io/cluster: my-cluster
  spec:
    partitions: 1
    replicas: 1
    config:
      segment.bytes: 10737418240
      retention.ms: 604800000
      retention.bytes: 107374182400
parameters:
  - name: KAFKA_TOPIC
    value: "topic-logging-app"
EOF

oc process -f og-amqstreams-template.yaml -p AMQ_NAMESPACE=$NAMESPACE |oc create -f -
oc create -f sub-amqstreams.yaml  
oc create -f kafka-my-cluster-no-authorization.yaml
oc process -f kafka-topics-template.yaml -p KAFKA_TOPIC=topic-logging-app| oc create -f -

# View the logs forwarded to Kafka
sh-4.4# ls /var/lib/kafka/data/kafka-log0/topic-logging-app-0/
sh-4.4# /opt/kafka/bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log \ --deep-iteration --print-data-log 
```


### Deploy syslog
```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: open-cluster-management
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: rsyslogserver
  labels:
    provider: aosqe
    component: "rsyslogserver"
data:
  rsyslog.conf: |+
    global(processInternalMessages="on")
    module(load="imptcp")
    module(load="imudp" TimeRequery="500")
    input(type="imptcp" port="6514")
    input(type="imudp" port="6514")
    :programname, contains, "kubernetes.var.log.containers" {
      if $msg contains "namespace_name=openshift" or $msg contains "namespace_name=default" or $msg contains "namespace_name=kube" then /var/log/custom/infra-container.log
      if not ($msg contains "namespace_name=openshift" or $msg contains "namespace_name=default" or $msg contains "namespace_name=kube") then /var/log/custom/app-container.log
    }
    :programname, contains, "journal.system" /var/log/custom/infra.log
    :programname, contains, "k8s-audit.log" /var/log/custom/audit.log
    :programname, contains, "openshift-audit.log" /var/log/custom/audit.log 
    :msg, contains, "docker"{
      if $msg contains "infrastructure" then /var/log/clf/infra-container.log
      if $msg contains "infra-write" then /var/log/clf/infra-container.log
      if $msg contains "application" then /var/log/clf/app-container.log
      if $msg contains "app-write" then /var/log/clf/app-container.log
    }
    :msg, contains, "_STREAM_ID" /var/log/clf/infra.log
    :msg, contains, "auditID" /var/log/clf/audit.log
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: rsyslogserver
  labels:
    provider: aosqe
    component: "rsyslogserver"
    appname: rsyslogserver
spec:
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      provider: aosqe
      component: "rsyslogserver"
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        provider: aosqe
        component: "rsyslogserver"
        appname: rsyslogserver
    spec:
      containers:
      - name: "rsyslog"
        args:
        - "-f"
        - "/etc/rsyslog/conf/rsyslog.conf"
        - "-n"
        command:
        - "/usr/sbin/rsyslogd"
        image: quay.io/openshifttest/rsyslogd-container@sha256:e806eb41f05d7cc6eec96bf09c7bcb692f97562d4a983cb019289bd048d9aee2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 6514
          name: rsyslog-pod-tcp
          protocol: TCP
        - containerPort: 6514
          name: rsyslog-pod-udp
          protocol: UDP
        volumeMounts:
        - mountPath: /etc/rsyslog/conf
          name: main
          readOnly: true
      volumes:
      - configMap:
          defaultMode: 420
          name: rsyslogserver
        name: main
---
apiVersion: v1
kind: Service
metadata:
  annotations:
    description: Exposes and load balances the application pods
  labels:
    provider: aosqe
    component: "rsyslogserver"
  name: rsyslogserver
spec:
  ports:
  - name: rsyslogserver-tcp
    port: 514
    targetPort: 6514
    protocol: TCP
  - name: rsyslogserver-udp
    port: 514
    targetPort: 6514
    protocol: UDP
  selector:
    appname: rsyslogserver
    provider: aosqe
EOF
```

### Deploy fluentd receiver
```bash
cat << EOF | oc apply -f -
apiVersion: v1
data:
  fluent.conf: |
    <source>
      @type forward
      port  24224
    </source>

    <match *_default_** **_kube-*_** **_openshift-*_** **_openshift_** kubernetes.var.log.pods.openshift-*_** kubernetes.var.log.pods.default_** kubernetes.var.log.pods.kube-*_**>
      @type file
      append true
      path /fluentd/log/infra-container.*.log
      symlink_path /fluentd/log/infra-container.log
      time_slice_format %Y%m%d
      time_slice_wait   1m
      time_format       %Y%m%dT%H%M%S%z
    </match>
    <match journal.** system.var.log**>
      @type file
      append true
      path /fluentd/log/infra.*.log
      symlink_path /fluentd/log/infra.log
      time_slice_format %Y%m%d
      time_slice_wait   1m
      time_format       %Y%m%dT%H%M%S%z
    </match>
    <match kubernetes.**>
      @type file
      append true
      path /fluentd/log/app.*.log
      symlink_path /fluentd/log/app.log
      time_slice_format %Y%m%d
      time_slice_wait   1m
      time_format       %Y%m%dT%H%M%S%z
    </match>
    <match linux-audit.log** k8s-audit.log** openshift-audit.log** ovn-audit.log**>
      @type file
      append true
      path /fluentd/log/audit.*.log
      symlink_path /fluentd/log/audit.log
      time_slice_format %Y%m%d
      time_slice_wait   1m
      time_format       %Y%m%dT%H%M%S%z
    </match>
    <match **>
      @type stdout
    </match>
kind: ConfigMap
metadata:
  name: fluentdserver
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "fluentdserver"
  labels:
    provider: aosqe
    component: "fluentdserver"
    logging-infra: "fluentdserver"
spec:
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      provider: aosqe
      component: "fluentdserver"
      logging-infra: "fluentdserver"
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        logging-infra: "fluentdserver"
        provider: aosqe
        component: "fluentdserver"
    spec:
      containers:
      - name: "fluentdserver"
        image: "quay.io/openshifttest/fluentd@sha256:7442342ab540f0b9e8bb99a58326591fc43cb9de2fa049f77ae11e375826364a"
        imagePullPolicy: "IfNotPresent"
        ports:
        - containerPort: 24224
          name: fluentdserver
        volumeMounts:
        - mountPath: /fluentd/etc
          name: config
          readOnly: true
      volumes:
      - configMap:
          defaultMode: 420
          name: fluentdserver
        name: config
EOF
```

### Deploy Elasticsearch
```bash
oc new-project elasticsearch

cat > configmap.yaml << EOF
kind: Template
apiVersion: template.openshift.io/v1
metadata:
  name: external-log-store-template
objects:
- apiVersion: v1
  data:
    elasticsearch.yml: |
      node.name:  ${NAME}
      cluster.name: ${NAME}
      discovery.zen.minimum_master_nodes: 1
      network.host: 0.0.0.0
      http.port: 9200
      http.host: 0.0.0.0
      transport.host: 127.0.0.1
      discovery.type: single-node
      xpack.security.enabled: false
      xpack.security.authc.api_key.enabled: false
      xpack.monitoring.enabled : false
      xpack.license.self_generated.type: basic
      xpack.security.http.ssl.enabled: false
  kind: ConfigMap
  metadata:
    name: ${NAME}
    namespace: ${NAMESPACE}
parameters:
- name: NAME
  value: elasticsearch-server
- name: NAMESPACE
  value: openshift-logging
EOF

cat > deployment.yaml << EOF
kind: Template
apiVersion: template.openshift.io/v1
metadata:
  name: external-log-store-template
objects:
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    labels:
      app: ${NAME}
    name: ${NAME}
    namespace: ${NAMESPACE}
  spec:
    replicas: 1
    revisionHistoryLimit: 10
    selector:
      matchLabels:
        app: ${NAME}
    strategy:
      activeDeadlineSeconds: 21600
      resources: {}
      rollingParams:
        intervalSeconds: 1
        maxSurge: 25%
        maxUnavailable: 25%
        timeoutSeconds: 600
        updatePeriodSeconds: 1
      type: Recreate
    template:
      metadata:
        labels:
          app: ${NAME}
      spec:
        containers:
        - image: docker.elastic.co/elasticsearch/elasticsearch:7.16.1
          imagePullPolicy: IfNotPresent
          name: ${NAME}
          ports:
          - containerPort: 9300
            protocol: TCP
          - containerPort: 9200
            protocol: TCP
          volumeMounts:
          - mountPath: /usr/share/elasticsearch/config/elasticsearch.yml
            subPath: elasticsearch.yml
            name: elasticsearch-config
          resources: {}
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
        volumes:
        - configMap:
            defaultMode: 420
            name: ${NAME}
          name: elasticsearch-config
        dnsPolicy: ClusterFirst
        restartPolicy: Always
parameters:
- name: NAME
  value: elasticsearch-server
- name: NAMESPACE
  value: openshift-logging
EOF

oc process -f configmap.yaml -p NAMESPACE=$NAMESPACE |oc create -f -
oc process -f deployment.yaml -p NAMESPACE=$NAMESPACE |oc create -f -
oc expose deployment/elasticsearch-server
```
