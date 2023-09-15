**1.Install Red Hat Openshift Logging and Loki Operator in the console**

**2.Install lokistack using minio and nfs sc**

a.[Install minio and nfs sc](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md)

b.Create Secret/LokiStack/ClusterLogging/ClusterLogForwarder resource
~~~
$ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/deploy_loki_using_minio.yaml
~~~

**Install lokistack using odf**
