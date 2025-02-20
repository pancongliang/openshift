### Disable master node scheduling of custom pods
~~~
oc patch schedulers.config.openshift.io cluster --type merge --patch '{"spec": {"mastersSchedulable": false}}'
~~~

### Enable master node scheduling of custom pods
~~~
oc patch schedulers.config.openshift.io cluster --type merge --patch '{"spec": {"mastersSchedulable": true}}'
~~~
