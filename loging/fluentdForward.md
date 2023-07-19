### Test
1. deploy logging
2. Deploying an application pod that generates logs
3. Deploy two log-aggregatorss (fluentd)
4. Create a ClusterLogForwarder
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

5. Modify the default buffer size and change the copy of elasticsearch deployment to 0
~~~
$ oc get clusterloggings.logging.openshift.io instance -o yaml
spec:
  collection:
    logs:
      fluentd: {}
      type: fluentd
  forwarder:
    fluentd:
      buffer:
        totalLimitSize: 100m

$ oc get deployment -n openshift-logging
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
cluster-logging-operator       1/1     1            1           28h
elasticsearch-cdm-2rabw8xz-1   0/0     0            0           4h45m   # replicas 0
elasticsearch-cdm-2rabw8xz-2   0/0     0            0           4h45m   # replicas 0
elasticsearch-cdm-2rabw8xz-3   0/0     0            0           4h45m   # replicas 0
kibana                         1/1     1            1           4h44m
~~~

6. master03-Fluentd buffer status is full
~~~
$ oc logs collector-rdw2q -n openshift-logging
2023-07-18 10:05:37 +0000 [warn]: [default] failed to flush the buffer. retry_times=9 next_retry_time=2023-07-18
 10:06:43 +0000 chunk="600be3d73df4300444f7365651f227a3" error_class=Fluent::Plugin::ElasticsearchOutput::Recove
rableRequestFailure error="could not push logs to Elasticsearch cluster ({:host=>\"elasticsearch\", :port=>9200,
 :scheme=>\"https\"}): Couldn't connect to server"
  2023-07-18 10:05:37 +0000 [warn]: suppressed same stacktrace
2023-07-18 10:07:44 +0000 [warn]: [default] failed to write data into buffer by buffer overflow action=:block
2023-07-18 10:08:53 +0000 [warn]: [default] failed to flush the buffer. retry_times=10 next_retry_time=2023-07-1
8 10:09:53 +0000 chunk="600bd45933f6387e5785678283202557" error_class=Fluent::Plugin::ElasticsearchOutput::Recov
erableRequestFailure error="could not push logs to Elasticsearch cluster ({:host=>\"elasticsearch\", :port=>9200
, :scheme=>\"https\"}): Couldn't connect to server"

$ oc get po -o wide -n logsample 
logsample-test-3-5bd765f4fc-4cl95   1/1     Running   0          51m     10.129.1.65    master03.ocp4.example.com
logsample-test-3-5bd765f4fc-rk62h   1/1     Running   0          51m     10.129.1.66    master03.ocp4.example.com

$ oc -n openshift-logging get po -o wide collector-rdw2q
NAME              READY   STATUS    RESTARTS   AGE    IP            NODE                        NOMINATED NODE   READINESS GATES
collector-rdw2q   2/2     Running   0          111m   10.129.1.51   master03.ocp4.example.com   

$ oc -n openshift-logging rsh collector-rdw2q
Defaulted container "collector" out of: collector, logfilesmetricexporter
sh-4.4# date
Tue Jul 18 10:08:30 UTC 2023
sh-4.4# cd /var/lib/fluentd/
sh-4.4# du -sh *
106M    default
40K     pos
0       remote_fluentd_forward
0       remote_fluentd_forward_sub
0       retry_default
~~~

7. After the buffer status is full, the log is not forwarded
# fluentd 1/2
~~~
/fluentd/log $ date
Tue Jul 18 10:39:46 UTC 2023

/fluentd/log $ cat app.b600bc898209b9799031608e2f7e1eec9.log | grep logsample-test-3
···
## fluentd 1
2023-07-18T10:07:43+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log
## fluentd 2
2023-07-18T10:07:43+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log 
~~~

8. After the bufeer is reduced by 4mb, some logs are forwarded.
~~~
$ oc -n openshift-logging rsh collector-rdw2q
sh-4.4# date
Tue Jul 18 10:52:38 UTC 2023
sh-4.4# cd /var/lib/fluentd/
sh-4.4# du -sh *
102M    default
40K     pos
0       remote_fluentd_forward
0       remote_fluentd_forward_sub
0       retry_default

# fluentd 1
/fluentd/log $ date
Tue Jul 18 11:08:23 UTC 2023

2023-07-18T10:08:01+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log
···
2023-07-18T10:49:26+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log

/fluentd/log $ ls -ltr
total 2092824
lrwxrwxrwx 1 1000710000 root         56 Jul 18 05:52 infra.log -> /fluentd/log/infra.b600bc86def57b6f4690a7fb587c912c3.log
lrwxrwxrwx 1 1000710000 root         54 Jul 18 05:53 app.log -> /fluentd/log/app.b600bc898209b9799031608e2f7e1eec9.log
lrwxrwxrwx 1 1000710000 root         66 Jul 18 09:50 infra-container.log -> /fluentd/log/infra-container.b600bfd84b75e4994c2846a6c7235c7e8.log
-rw-r--r-- 1 1000710000 root  255744575 Jul 18 09:50 infra-container.20230718.log
-rw-r--r-- 1 1000710000 root 1534374001 Jul 18 10:49 audit.20230718.log
lrwxrwxrwx 1 1000710000 root         56 Jul 18 10:49 audit.log -> /fluentd/log/audit.b600c0ab4597a8c1dcb4d8d6c4d02809f.log
-rw-r--r-- 1 1000710000 root         81 Jul 18 11:09 infra.b600bc86def57b6f4690a7fb587c912c3.log.meta
-rw-r--r-- 1 1000710000 root   77699151 Jul 18 11:09 infra.b600bc86def57b6f4690a7fb587c912c3.log
-rw-r--r-- 1 1000710000 root  102103804 Jul 18 11:09 audit.b600c0ab4597a8c1dcb4d8d6c4d02809f.log
-rw-r--r-- 1 1000710000 root         81 Jul 18 11:09 audit.b600c0ab4597a8c1dcb4d8d6c4d02809f.log.meta
-rw-r--r-- 1 1000710000 root         81 Jul 18 11:09 app.b600bc898209b9799031608e2f7e1eec9.log.meta
-rw-r--r-- 1 1000710000 root   49557234 Jul 18 11:09 app.b600bc898209b9799031608e2f7e1eec9.log
-rw-r--r-- 1 1000710000 root         81 Jul 18 11:09 infra-container.b600bfd84b75e4994c2846a6c7235c7e8.log.meta
-rw-r--r-- 1 1000710000 root   54296464 Jul 18 11:09 infra-container.b600bfd84b75e4994c2846a6c7235c7e8.log

# fluentd 2
/fluentd/log $ date
Tue Jul 18 11:08:41 UTC 2023

2023-07-18T10:08:01+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log 
···
2023-07-18T10:49:26+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log

/fluentd/log $ ls -ltr
total 2152364
lrwxrwxrwx 1 1000700000 root         54 Jul 18 05:55 app.log -> /fluentd/log/app.b600bc8eb525417ae7d42cc4eef8eb8c5.log
lrwxrwxrwx 1 1000700000 root         56 Jul 18 05:55 infra.log -> /fluentd/log/infra.b600bc8eb81fe5db2cd5358d0d2c60f8e.log
lrwxrwxrwx 1 1000700000 root         66 Jul 18 09:52 infra-container.log -> /fluentd/log/infra-container.b600bfdf36b4306b61849dd1666388627.log
-rw-r--r-- 1 1000700000 root  255019960 Jul 18 09:52 infra-container.20230718.log
-rw-r--r-- 1 1000700000 root 1542589249 Jul 18 10:50 audit.20230718.log
lrwxrwxrwx 1 1000700000 root         56 Jul 18 10:50 audit.log -> /fluentd/log/audit.b600c0afb4ae3b75beb95d1aab6e9211c.log
-rw-r--r-- 1 1000700000 root         81 Jul 18 11:08 infra.b600bc8eb81fe5db2cd5358d0d2c60f8e.log.meta
-rw-r--r-- 1 1000700000 root   74188209 Jul 18 11:08 infra.b600bc8eb81fe5db2cd5358d0d2c60f8e.log
-rw-r--r-- 1 1000700000 root         81 Jul 18 11:08 infra-container.b600bfdf36b4306b61849dd1666388627.log.meta
-rw-r--r-- 1 1000700000 root   52540214 Jul 18 11:08 infra-container.b600bfdf36b4306b61849dd1666388627.log
-rw-r--r-- 1 1000700000 root         81 Jul 18 11:08 audit.b600c0afb4ae3b75beb95d1aab6e9211c.log.meta
-rw-r--r-- 1 1000700000 root   71135386 Jul 18 11:08 audit.b600c0afb4ae3b75beb95d1aab6e9211c.log
-rw-r--r-- 1 1000700000 root         81 Jul 18 11:08 app.b600bc8eb525417ae7d42cc4eef8eb8c5.log.meta
-rw-r--r-- 1 1000700000 root   49427632 Jul 18 11:08 app.b600bc8eb525417ae7d42cc4eef8eb8c5.log
~~~

9. Delay forwarded part of the log while the buffer autoflush size.
~~~
sh-4.4# date
Tue Jul 18 12:02:31 UTC 2023
sh-4.4# du -sh *
103M    default
40K     pos
0       remote_fluentd_forward
0       remote_fluentd_forward_sub
0       retry_default

# fluentd 1
/fluentd/log $ date
Tue Jul 18 12:04:05 UTC 2023
2023-07-18T10:50:02+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log 
···
2023-07-18T11:49:49+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-4cl95_a2c7a2ce-bea6-462d-921c-85a8a8186d63.output-containerx.0.log

# fluentd 2
/fluentd/log $ date
Tue Jul 18 12:04:17 UTC 2023
2023-07-18T10:50:02+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log
···
2023-07-18T11:49:49+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-4cl95_a2c7a2ce-bea6-462d-921c-85a8a8186d63.output-containerx.0.log 
~~~

~~~
sh-4.4# date
Tue Jul 18 13:25:36 UTC 2023
sh-4.4# du -sh *
103M    default
40K     pos
0       remote_fluentd_forward
0       remote_fluentd_forward_sub
0       retry_default

# fluentd 1
2023-07-18T12:50:40+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-4cl95_a2c7a2ce-bea6-462d-921c-85a8a8186d63.output-containerx.0.log 

# fluentd 2
2023-07-18T12:50:40+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-4cl95_a2c7a2ce-bea6-462d-921c-85a8a8186d63.output-containerx.0.log
~~~

~~~
sh-4.4# date
Tue Jul 18 16:21:06 UTC 2023
sh-4.4# du -sh *
105M    default
40K     pos
0       remote_fluentd_forward
0       remote_fluentd_forward_sub
0       retry_default

# fluentd 1
···
2023-07-18T15:56:59+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log 

# fluentd 2
···
2023-07-18T15:56:59+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log
~~~

~~~
sh-4.4# date
Wed Jul 19 01:16:30 UTC 2023
sh-4.4# du -sh *
102M    default
40K     pos
0       remote_fluentd_forward
0       remote_fluentd_forward_sub
0       retry_default

# fluentd 1
2023-07-19T00:59:26+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-rk62h_213a382e-00dc-4e4b-953b-349b188469b6.output-containerx.0.log
# fluentd 2
2023-07-19T00:59:26+00:00       kubernetes.var.log.pods.logsample_logsample-test-3-5bd765f4fc-4cl95_a2c7a2ce-bea6-462d-921c-85a8a8186d63.output-containerx.0.log
~~~

10. Other fluentds buffers are not full continue to forward logs
~~~
$ oc get po -o wide -n openshift-logging
collector-xcmz9                             2/2     Running     0          16h   10.130.1.215   master01.ocp4.example.com 
$ oc rsh collector-xcmz9
sh-4.4# date
Wed Jul 19 01:17:01 UTC 2023
sh-4.4# du -sh *
55M     default
84K     pos
44K     remote_fluentd_forward
44K     remote_fluentd_forward_sub
0       retry_default

$ oc get po -n logsample  -o wide
logsample-test-1-66fcbd95f-82fv7    1/1     Running   0          15h   10.130.1.229   master01.ocp4.example.com   
logsample-test-1-66fcbd95f-f46vd    1/1     Running   0          15h   10.130.1.230   master01.ocp4.example.com   

# fluentd 1
···
2023-07-19T01:18:39+00:00       kubernetes.var.log.pods.logsample_logsample-test-1-66fcbd95f-82fv7_c3a1a1e9-bd06-48b8-9706-8cfbabd3e188.output-containerx.0.log
···
2023-07-19T01:34:49+00:00       kubernetes.var.log.pods.logsample_logsample-test-1-66fcbd95f-82fv7_c3a1a1e9-bd06-48b8-9706-8cfbabd3e188.output-containerx.0.log

# fluentd 2
···
2023-07-19T01:19:21+00:00       kubernetes.var.log.pods.logsample_logsample-test-1-66fcbd95f-f46vd_eee892c0-b6e0-4503-9f40-389ba29c8292.output-containerx.0.log
···
2023-07-19T01:35:42+00:00       kubernetes.var.log.pods.logsample_logsample-test-1-66fcbd95f-f46vd_eee892c0-b6e0-4503-9f40-389ba29c8292.output-containerx.0.log
~~~
