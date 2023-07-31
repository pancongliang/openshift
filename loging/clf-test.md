### When there are multiple log-aggregators, simulate the failure of 1 log-aggregator to see if the vector can continue to forward logs

env: openshift 4.12 openshift logging5.7


1.Kafka can receive logs normally
~~~
$ oc get clusterloggings.logging.openshift.io instance -o yaml
···
spec:
  collection:
    logs:
      type: vector

$ oc get clusterlogforwarders instance -o yaml
···
spec:
  outputs:
  - name: remote-kafka-forward
    type: kafka
    url: tls://my-cluster-kafka-bootstrap.kafka-1.svc:9092/topic-logging-app
  - name: remote-kafka-forward-sub
    type: kafka
    url: tls://my-cluster-kafka-bootstrap.kafka-2.svc:9092/topic-logging-app
  pipelines:
  - inputRefs:
    - application
    name: enable-default-log-store
    outputRefs:
    - default
  - inputRefs:
    - application
    name: enable-remote-kafka-forward-log-store
    outputRefs:
    - remote-kafka-forward
  - inputRefs:
    - application
    name: enable-remote-kafka-forward-log-store-sub
    outputRefs:
    - remote-kafka-forward-sub

# Generate application logs
$ ab -n 200 -c 1 http://hello.apps.ocp4.example.com/
$ ab -n 200 -c 1 http://stdout.apps.ocp4.example.com/

$ oc rsh -n kafka-1 my-cluster-kafka-0
$ oc rsh -n kafka-2 my-cluster-kafka-0
sh-4.4$ cd /opt/kafka
sh-4.4$ du -sh /var/lib/kafka/data/kafka-log0/topic-logging-app-0/
59M     /var/lib/kafka/data/kafka-log0/topic-logging-app-0/
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
200
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
200
~~~

2.Simulate a log-aggregator failure
~~~
$ oc scale --replicas 0 -n openshift-operators-redhat deployments/elasticsearch-operator
$ oc scale --replicas 0 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-1
$ oc scale --replicas 0 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-2
$ oc scale --replicas 0 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-3

$ oc logs collector-zkr5l -c collector 
22023-07-30T04:03:59.675767Z ERROR sink{component_kind="sink" component_id=default component_type=elasticsearch component_name=default}: vector::internal_events::http_client: HTTP error. error=error trying to connect: tcp connect error: Connection timed out (os error 110) error_type="request_failed" stage="processing"
2023-07-30T04:03:59.675918Z  WARN sink{component_kind="sink" component_id=default component_type=elasticsearch component_name=default}: vector::sinks::util::retries: Retrying after error. error=Failed to make HTTP(S) request: error trying to connect: tcp connect error: Connection timed out (os error 110)
~~~

3.Generate application logs to verify that 1 log aggregator will continue forwarding to the healthy log aggregator if it fails.
~~~
# Generate application logs
$ ab -n 1000 -c 1 http://stdout.apps.ocp4.example.com/
$ oc logs stdout-app-688fd45fc4-mdd8k -n test | grep '123456789' |wc -l 
1200

$ ab -n 1000 -c 1 http://hello.apps.ocp4.example.com/
$ oc logs hello-world-f6568fcf7-mzx7n -n test | grep 'hello world' |wc -l   
1200

# 'hello world' logs are not forwarded to healthy log-aggregator
$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ cd /opt/kafka
sh-4.4$ ls /var/lib/kafka/data/kafka-log0/topic-logging-app-0/  
00000000000000000000.index  00000000000000000000.log  00000000000000000000.timeindex  leader-epoch-checkpoint  partition.metadata

sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
200 

sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
1200

# All application logs are not forwarded, After waiting for about 1 hour, the logs are still not forwarded to the healthy log-aggregator
$ date
Sun Jul 30 04:11:22 UTC 2023

# Generate application logs
$ ab -n 1000 -c 1 http://stdout.apps.ocp4.example.com/
$ oc logs stdout-app-688fd45fc4-mdd8k -n copan-test | grep '123456789' |wc -l 
2200

$ ab -n 1000 -c 1 http://hello.apps.ocp4.example.com/
$ oc logs hello-world-f6568fcf7-mzx7n -n copan-test | grep 'hello world' |wc -l   
2200

$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ date
Sun Jul 30 04:13:31 UTC 2023
sh-4.4$ cd /opt/kafka
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
200

sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
1200

sh-4.4$ date
Sun Jul 30 05:15:25 UTC 2023
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
200

sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
1200
~~~

4.After restarting the collector pod, the healthy log-aggregator only received part of the logs(Waited for about 30 minutes and still haven't received the log).
~~~
$ oc delete po collector-2wmrv collector-h8qcr collector-hf72n collector-mkbtz collector-p658v collector-vjhp5

$ oc logs stdout-app-688fd45fc4-mdd8k -n copan-test | grep '123456789' |wc -l 
2200
$ oc logs hello-world-f6568fcf7-mzx7n -n copan-test | grep 'hello world' |wc -l   
2200

$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
2200
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
1200
~~~

5.Recover the elasticsearch pod, wait for 15 minutes and still not forward the logs.
~~~
$ oc scale --replicas 1 -n openshift-operators-redhat deployments/elasticsearch-operator
$ oc scale --replicas 1 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-1
$ oc scale --replicas 1 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-2
$ oc scale --replicas 1 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-3

$ oc logs stdout-app-688fd45fc4-mdd8k -n copan-test | grep '123456789' |wc -l 
2200
$ oc logs hello-world-f6568fcf7-mzx7n -n copan-test | grep 'hello world' |wc -l   
2200

$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
2200
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
1200

$ oc logs collector-g7djs -c collector
2023-07-30T05:48:55.227975Z ERROR sink{component_kind="sink" component_id=default component_type=elasticsearch component_name=default}: vector::internal_events::http_client: HTTP error. error=error trying to connect: tcp connect error: Connection timed out (os error 110) error_type="request_failed" stage="processing"
2023-07-30T05:48:55.228106Z  WARN sink{component_kind="sink" component_id=default component_type=elasticsearch component_name=default}: vector::sinks::util::retries: Retrying after error. error=Failed to make HTTP(S) request: error trying to connect: tcp connect error: Connection timed out (os error 110)

$ date
Sun Jul 30 06:03:01 UTC 2023
~~~

6.After restarting the collector pod, the log-aggregator still hasn't received the logs,
  Therefore, the application log was regenerated and a part of the log was found to be missing.
~~~
$ oc delete po collector-5qbxz collector-8gmpq collector-dsxj9 collector-g7djs collector-kmlqn collector-sg64h
$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
2200
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
1200

# Generate application logs
$ ab -n 1000 -c 1 http://stdout.apps.ocp4.example.com/
$ oc logs stdout-app-688fd45fc4-mdd8k -n copan-test | grep '123456789' |wc -l 
3200
$ ab -n 1000 -c 1 http://hello.apps.ocp4.example.com/
$ oc logs hello-world-f6568fcf7-mzx7n -n copan-test | grep 'hello world' |wc -l   
3200

$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
2200
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
3200
~~~

7.Set the elasticsearch pod copy to 0, test the application log generated during the failure of one log-aggregator, and check whether other healthy log-aggregators can receive the log.
~~~
$ oc scale --replicas 0 -n openshift-operators-redhat deployments/elasticsearch-operator
$ oc scale --replicas 0 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-1
$ oc scale --replicas 0 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-2
$ oc scale --replicas 0 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-3

# Confirm the number of log-aggregator logs before generating logs
$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
2200
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
3200

# Regenerate 1000 logs through the following command, and the forwarding is successful.
$ ab -n 1000 -c 1 http://stdout.apps.ocp4.example.com/
$ oc logs stdout-app-688fd45fc4-mdd8k -n copan-test | grep '123456789' |wc -l 
4200
$ ab -n 1000 -c 1 http://hello.apps.ocp4.example.com/
$ oc logs hello-world-f6568fcf7-mzx7n -n copan-test | grep 'hello world' |wc -l   
4200

$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
3200
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
4200

# Regenerate 10000 logs by the following command,only 132 logs forwarded（Waiting for about 15 minutes only received 132 logs）
$ ab -n 10000 -c 1 http://stdout.apps.ocp4.example.com/
$ ab -n 10000 -c 1 http://hello.apps.ocp4.example.com/
$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
4332
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
3200

# Restore the elasticsearch pod to see if the log can be received, then regenerate the log.
$ oc scale --replicas 1 -n openshift-operators-redhat deployments/elasticsearch-operator
$ oc scale --replicas 1 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-1
$ oc scale --replicas 1 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-2
$ oc scale --replicas 1 -n openshift-logging deployments/elasticsearch-cdm-8qonknn5-3

$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
14200
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
13200

# Generate application logs
$ ab -n 20000 -c 1 http://stdout.apps.ocp4.example.com/
$ ab -n 20000 -c 1 http://hello.apps.ocp4.example.com/

$ oc rsh -n kafka-1 my-cluster-kafka-0
sh-4.4$ bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep '123456789' |wc -l
34200
sh-4.4$  bin/kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/lib/kafka/data/kafka-log0/topic-logging-app-0/00000000000000000000.log --deep-iteration --print-data-log |grep 'hello world' |wc -l
33200
~~~
