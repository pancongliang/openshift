**1. deploy logging**

**2. deploy application**
~~~
$ oc new-project logsample
$ oc create -f https://raw.githubusercontent.com/pancongliang/fluentd_sidecar_openshift/main/kube/deployment_sidecar_stdout.yaml

$ oc get po -o wide -n logsample 
NAME                         READY   STATUS    RESTARTS   AGE   IP            NODE                        NOMINATED NODE   READINESS GATES
samplelog-5f9748dc86-frqpt   2/2     Running   0          7s    10.131.0.58   worker01.ocp4.example.com   <none>           <none>

$ oc logs samplelog-5f9748dc86-frqpt -n logsample -c fluentd
···
2023-07-17 09:47:33 +0000 [info]: #0 fluentd worker is now running worker=0

$ ssh core@worker01.ocp4.example.com sudo cat /var/log/containers/samplelog-5f9748dc86-frqpt_logsample_fluentd-8ae3a824196266f1b037ed2da095af15063d6f6a67a6274d3ce4dc4fd7ba3983.log
···
2023-07-17T09:47:33.691036787+00:00 stdout F 2023-07-17 09:47:33 +0000 [info]: #0 following tail of /var/app/samplelog.log
2023-07-17T09:47:33.691036787+00:00 stdout F 2023-07-17 09:47:33 +0000 [info]: #0 fluentd worker is now running worker=0
~~~

**3. Deploy two log-aggregatorss (fluentd)**
~~~
$ oc new-project fluentd-aosqe-1
$ oc create -f https://raw.githubusercontent.com/openshift/verification-tests/master/testdata/logging/clusterlogforwarder/fluentd/insecure/configmap.yaml 
$ oc create -f https://raw.githubusercontent.com/openshift/verification-tests/master/testdata/logging/clusterlogforwarder/fluentd/insecure/deployment.yaml 
$ oc expose deployment/fluentdserver

$ oc new-project fluentd-aosqe-2
$ oc create -f https://raw.githubusercontent.com/openshift/verification-tests/master/testdata/logging/clusterlogforwarder/fluentd/insecure/configmap.yaml 
$ oc create -f https://raw.githubusercontent.com/openshift/verification-tests/master/testdata/logging/clusterlogforwarder/fluentd/insecure/deployment.yaml 
$ oc expose deployment/fluentdserver
~~~

**4.Create a ClusterLogForwarder**
~~~
$ cat << EOF | oc apply -f -
apiVersion: "logging.openshift.io/v1"
kind: ClusterLogForwarder
metadata:
  name: instance 
  namespace: openshift-logging 
spec:
  outputs:
    - name: remote-fluentd-forward
      syslog:
        rfc: RFC5424
      type: fluentdForward
      url: 'tcp://fluentdserver.fluentd-aosqe-1.svc:24224'
    - name: remote-fluentd-forward-sub
      syslog:
        rfc: RFC5424
      type: fluentdForward
      url: 'tcp://fluentdserver.fluentd-aosqe-2.svc:24224'
  pipelines:
    - inputRefs:
        - application
        - infrastructure
        - audit
      name: enable-default-log-store
      outputRefs:
        - default
    - inputRefs:
        - application
        - infrastructure
        - audit
      name: enable-remote-fluentd-forward-log-store
      outputRefs:
        - remote-fluentd-forward
    - inputRefs:
        - application
        - infrastructure
        - audit
      name: enable-remote-fluentd-forward-log-store-sub
      outputRefs:
        - remote-fluentd-forward-sub
EOF
~~~

**5. Confirm that the log has been forwarded, and confirm the log size and time**
~~~
$ oc -n fluentd-aosqe-1 rsh fluentdserver-c47657575-lnszp du -sm /fluentd/log/
306     /fluentd/log/

$ oc -n fluentd-aosqe-2 rsh fluentdserver-c47657575-jwqhz du -sm /fluentd/log/
304     /fluentd/log/

$ oc -n fluentd-aosqe-1 rsh fluentdserver-c47657575-lnszp ls -ltr /fluentd/log
total 312908
lrwxrwxrwx 1 1000910000 root        66 Jul 17 09:56 infra-container.log -> /fluentd/log/infra-container.b600abce86d2045beba6b0abf1da186b8.log
lrwxrwxrwx 1 1000910000 root        56 Jul 17 09:56 infra.log -> /fluentd/log/infra.b600abce9611933ddc83dcce00ac9fcd3.log
lrwxrwxrwx 1 1000910000 root        56 Jul 17 09:56 audit.log -> /fluentd/log/audit.b600abce99f168e6420c4510cb9ae474c.log
-rw-r--r-- 1 1000910000 root        81 Jul 17 10:12 infra.b600abce9611933ddc83dcce00ac9fcd3.log.meta
-rw-r--r-- 1 1000910000 root   5770474 Jul 17 10:12 infra.b600abce9611933ddc83dcce00ac9fcd3.log
-rw-r--r-- 1 1000910000 root 145754661 Jul 17 10:12 audit.b600abce99f168e6420c4510cb9ae474c.log
-rw-r--r-- 1 1000910000 root        83 Jul 17 10:12 audit.b600abce99f168e6420c4510cb9ae474c.log.meta
-rw-r--r-- 1 1000910000 root        81 Jul 17 10:12 infra-container.b600abce86d2045beba6b0abf1da186b8.log.meta
-rw-r--r-- 1 1000910000 root  28965867 Jul 17 10:12 infra-container.b600abce86d2045beba6b0abf1da186b8.log

$ oc -n fluentd-aosqe-2 rsh fluentdserver-c47657575-jwqhz ls -ltr /fluentd/log
total 310668
lrwxrwxrwx 1 1000930000 root        66 Jul 17 09:56 infra-container.log -> /fluentd/log/infra-container.b600abce86e81b68a039fc1aa54ea6999.log
lrwxrwxrwx 1 1000930000 root        56 Jul 17 09:56 infra.log -> /fluentd/log/infra.b600abce964ac1360460416604431c575.log
lrwxrwxrwx 1 1000930000 root        56 Jul 17 09:56 audit.log -> /fluentd/log/audit.b600abce99fe99776e40a103b3c23104a.log
-rw-r--r-- 1 1000930000 root        81 Jul 17 10:12 infra-container.b600abce86e81b68a039fc1aa54ea6999.log.meta
-rw-r--r-- 1 1000930000 root  30247179 Jul 17 10:12 infra-container.b600abce86e81b68a039fc1aa54ea6999.log
-rw-r--r-- 1 1000930000 root        81 Jul 17 10:12 infra.b600abce964ac1360460416604431c575.log.meta
-rw-r--r-- 1 1000930000 root   5844429 Jul 17 10:12 infra.b600abce964ac1360460416604431c575.log
-rw-r--r-- 1 1000930000 root        83 Jul 17 10:12 audit.b600abce99fe99776e40a103b3c23104a.log.meta
-rw-r--r-- 1 1000930000 root 148562496 Jul 17 10:12 audit.b600abce99fe99776e40a103b3c23104a.log
~~~

**6. Delete the svc in the fluentd-aosqe-1 project to simulate a communication interruption of an external log-aggregators**
~~~
$ oc -n fluentd-aosqe-1 get svc fluentdserver
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)     AGE
fluentdserver   ClusterIP   172.30.25.109   <none>        24224/TCP   23m

$ oc -n fluentd-aosqe-1 delete svc fluentdserver
$ oc -n openshift-logging logs collector-5kpf4
2023-07-17 10:15:12 +0000 [warn]: [remote_fluentd_forward] failed to flush the buffer. retry_times=4 next_retry_time=2023-07-17 10:15:28 +0000 chunk="600ac0d2e541ce15a9a8b5fa42a51877" error_class=Errno::EHOSTUNREACH error="No route to host - connect(2) for \"172.30.25.109\" port 24224"
  2023-07-17 10:15:12 +0000 [warn]: suppressed same stacktrace

- After fluentd-aosqe-1 network interruption, confirm the last log time
$ oc -n fluentd-aosqe-1 rsh fluentdserver-c47657575-lnszp tail /fluentd/log/infra-container.b600abce86d2045beba6b0abf1da186b8.log
2023-07-17T10:13:50+00:00  ···
~~~

**7. Wait for 30m, and then check whether the normal log-aggregators is receiving logs normally**
~~~
$ oc -n fluentd-aosqe-1 rsh fluentdserver-c47657575-lnszp du -sm /fluentd/log/
192     /fluentd/log/

$ oc -n fluentd-aosqe-2 rsh fluentdserver-c47657575-jwqhz du -sm /fluentd/log/
627     /fluentd/log/

$ oc -n fluentd-aosqe-1 rsh fluentdserver-c47657575-lnszp ls -ltr /fluentd/log
total 196032
lrwxrwxrwx 1 1000910000 root        66 Jul 17 09:56 infra-container.log -> /fluentd/log/infra-container.b600abce86d2045beba6b0abf1da186b8.log
lrwxrwxrwx 1 1000910000 root        56 Jul 17 09:56 infra.log -> /fluentd/log/infra.b600abce9611933ddc83dcce00ac9fcd3.log
lrwxrwxrwx 1 1000910000 root        56 Jul 17 09:56 audit.log -> /fluentd/log/audit.b600abce99f168e6420c4510cb9ae474c.log
-rw-r--r-- 1 1000910000 root   6286829 Jul 17 10:13 infra.b600abce9611933ddc83dcce00ac9fcd3.log
-rw-r--r-- 1 1000910000 root        81 Jul 17 10:13 infra.b600abce9611933ddc83dcce00ac9fcd3.log.meta
-rw-r--r-- 1 1000910000 root 160158652 Jul 17 10:13 audit.b600abce99f168e6420c4510cb9ae474c.log
-rw-r--r-- 1 1000910000 root        83 Jul 17 10:13 audit.b600abce99f168e6420c4510cb9ae474c.log.meta
-rw-r--r-- 1 1000910000 root        81 Jul 17 10:13 infra-container.b600abce86d2045beba6b0abf1da186b8.log.meta
-rw-r--r-- 1 1000910000 root  34274875 Jul 17 10:13 infra-container.b600abce86d2045beba6b0abf1da186b8.log

$ oc -n fluentd-aosqe-2 rsh fluentdserver-c47657575-jwqhz ls -ltr /fluentd/log
total 641520
lrwxrwxrwx 1 1000930000 root        66 Jul 17 09:56 infra-container.log -> /fluentd/log/infra-container.b600abce86e81b68a039fc1aa54ea6999.log
lrwxrwxrwx 1 1000930000 root        56 Jul 17 09:56 infra.log -> /fluentd/log/infra.b600abce964ac1360460416604431c575.log
-rw-r--r-- 1 1000930000 root 255231126 Jul 17 10:24 audit.20230717.log
lrwxrwxrwx 1 1000930000 root        56 Jul 17 10:24 audit.log -> /fluentd/log/audit.b600ac33b873b82fea1f9691ffb223b50.log
-rw-r--r-- 1 1000930000 root        81 Jul 17 10:51 infra.b600abce964ac1360460416604431c575.log.meta
-rw-r--r-- 1 1000930000 root  14724609 Jul 17 10:51 infra.b600abce964ac1360460416604431c575.log
-rw-r--r-- 1 1000930000 root 105953300 Jul 17 10:51 infra-container.b600abce86e81b68a039fc1aa54ea6999.log
-rw-r--r-- 1 1000930000 root        81 Jul 17 10:51 infra-container.b600abce86e81b68a039fc1aa54ea6999.log.meta
-rw-r--r-- 1 1000930000 root        83 Jul 17 10:51 audit.b600ac33b873b82fea1f9691ffb223b50.log.meta
-rw-r--r-- 1 1000930000 root 240972582 Jul 17 10:51 audit.b600ac33b873b82fea1f9691ffb223b50.log

$ oc -n fluentd-aosqe-1 rsh fluentdserver-c47657575-lnszp tail /fluentd/log/infra-container.b600abce86d2045beba6b0abf1da186b8.log
2023-07-17T10:13:50+00:00 ···

$ oc -n fluentd-aosqe-2 rsh fluentdserver-c47657575-jwqhz tail /fluentd/log/infra-container.b600abce86e81b68a039fc1aa54ea6999.log
2023-07-17T10:52:33+00:00 ···
~~~
