### Install Red Hat Openshift Logging and Loki Operator in the console
Install the Operator using the default namespace.


### Install Loki Stack resource

#### Option A: Install lokistack using minio and nfs sc
* Install [minio and nfs sc](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md)

* Create Secret LokiStack ClusterLogging ClusterLogForwarder resource
~~~
$ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/deploy_loki_using_minio.yaml
~~~

#### Option B: Install lokistack using ODF
* Install [odf](https://github.com/pancongliang/openshift/blob/main/storage/odf/readme.md)

* Create Secret LokiStack ClusterLogging ClusterLogForwarder resource
~~~
$ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/deploy_loki_using_minio.yaml
~~~
