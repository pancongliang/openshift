### Modify the default kube-scheduler log level to collect scheduling scoring logs.
~~~
$ oc patch kubescheduler cluster  --type=json -p='[{"op": "replace", "path": "/spec/logLevel", "value":"TraceAll"}]'
~~~

### View scheduling scoring logs
~~~
$ oc -n openshift-kube-scheduler logs openshift-kube-scheduler-master01.ocp4.example.com | grep nginx
~~~

### Reset the kube-scheduler log level to its default value
~~~
$ oc patch kubescheduler cluster  --type=json -p='[{"op": "replace", "path": "/spec/logLevel", "value":"Normal"}]'
~~~
