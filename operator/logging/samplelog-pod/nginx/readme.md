### Create nginx pod using configmap and secret
~~~
oc new-project test

oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nginx/nginx-test.yaml

export ROUTE=$(oc get route nginx -n test -o jsonpath='{"http://"}{.spec.host}{"\n"}')

curl -s -u admin:password ${ROUTE}
~~~

Access URL generation log
~~~
oc new-project samplelog
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nginx/nginx-log.yaml

export ROUTE=$(oc get route sample-log-app -n test -o jsonpath='{"http://"}{.spec.host}{"\n"}')

curl -s ${ROUTE} |grep Hello
    <h1>Hello, world from nginx!</h1>

oc logs sample-log-app-d857dd4bf-lqpfv
2024-03-15T09:37:53+00:00 hello world

or

yum install httpd-tools
ab -n 10 -c 1 ${ROUTE}/

oc logs sample-log-app-d857dd4bf-lqpfv
2024-03-15T09:37:53+00:00 hello world
2024-03-15T09:39:27+00:00 hello world
2024-03-15T09:40:32+00:00 hello world
2024-03-15T09:40:32+00:00 hello world
2024-03-15T09:40:32+00:00 hello world
~~~
