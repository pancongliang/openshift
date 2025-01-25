#### 1. Change the default kubescheduler logLevel so that scheduling scoring logs can be collected
~~~
$ oc patch kubescheduler cluster  --type=json -p='[{"op": "replace", "path": "/spec/logLevel", "value":"TraceAll"}]'
~~~

#### 2.Check kube-scheduler pod restarting
~~~   
$ oc get pods -n openshift-kube-scheduler
openshift-kube-scheduler-master-1
openshift-kube-scheduler-master-2
openshift-kube-scheduler-master-3
~~~

#### 3.View the Scheduling Scoring Log
~~~
$ oc -n openshift-kube-scheduler logs openshift-kube-scheduler-master01.ocp4.example.com | grep nginx
~~~

#### 4..Restore kubescheduler logLevel
~~~
$ oc patch kubescheduler cluster  --type=json -p='[{"op": "replace", "path": "/spec/logLevel", "value":"Normal"}]'
~~~
