~~~
oc new-project elasticsearch
#create configmap for elasticserch receiver:
oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/elasticsearch/01_configmap.yaml -p NAMESPACE=$project_name |oc create -f -

or

oc process -f aosqe-tools/logging/log_template/external-elasticsearch/7.16/http/no_user/configmap.yaml -p NAMESPACE=$project_name |oc create -f -
#create deployment fore elasticsearch receiver and expose svc:

oc process -f https://raw.githubusercontent.com/pancongliang/openshift/main/loging/elasticsearch/02_deployment.yaml -p NAMESPACE=$project_name |oc create -f -

or

oc process -f aosqe-tools/logging/log_template/external-elasticsearch/7.16/http/no_user/deployment.yaml -p NAMESPACE=$project_name |oc create -f -

oc expose deployment/elasticsearch-server
~~~
