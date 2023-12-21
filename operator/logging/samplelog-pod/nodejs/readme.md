### Build samplelog-app image
~~~
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nodejs/server.js
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nodejs/package.json
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nodejs/Dockerfile

podman build -t docker.registry.example.com:5000/nodejs/nodejs-app:latest .
podman push docker.registry.example.com:5000/nodejs/nodejs-app:latest
~~~

### Create samplelog app serive
~~~
export NAMESPACE="nodejs-app"
export IMAGE="docker.registry.example.com:5000/nodejs/nodejs-app:latest"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nodejs/deployment.yaml | envsubst | oc apply -f -
oc expose svc nodejs-app --hostname nodejs.apps.ocp4.example.com

curl http://nodejs.apps.ocp4.example.com
Hello World!

oc logs nodejs-app-76f9f47b4f-x6c26
Example app listening at http://localhost:3000
{
  "event": "requestReceived",
  "url": "/",
  "method": "GET",
  "timestamp": "2023-12-21T17:24:18.087Z",
  "podName": "nodejs-app-76f9f47b4f-x6c26",
  "nodeName": "worker02.ocp4.example.com"
}
~~~

### Generate log(Generate 10 logs)
~~~
yum install httpd-tools

ab -n 10 -c 1 http://hello-world.apps.ocp4.example.com/

oc logs -n samplelog samplelog-app-69d56fb7db-bjpmz |grep "Hello World"
oc logs nodejs-app-76f9f47b4f-x6c26
Example app listening at http://localhost:3000
{
  "event": "requestReceived",
  "url": "/",
  "method": "GET",
  "timestamp": "2023-12-21T17:24:18.087Z",
  "podName": "nodejs-app-76f9f47b4f-x6c26",
  "nodeName": "worker02.ocp4.example.com"
}
···
~~~
