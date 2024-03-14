### Create nginx pod using configmap and secret
~~~
oc new-project test

oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nginx/nginx-test.yaml

export ROUTE=$(oc get route nginx -n test -o jsonpath='{"http://"}{.spec.host}{"\n"}')

curl -s -u admin:password ${ROUTE}
~~~
~~~
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to Nginx!</title>
</head>
<body>
  <h1>Hello, World!</h1>
  <p>This HTML content is served by Nginx from a ConfigMap.</p>
</body>
</html>
~~~
