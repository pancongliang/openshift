### Build samplelog-app image
~~~
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nodejs/app.js
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nodejs/package.json
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nodejs/Dockerfile

podman build -t docker.registry.example.com:5000/nodejs/nodejs-app:latest .
podman push docker.registry.example.com:5000/nodejs/nodejs-app:latest
~~~

### Create samplelog app serive
~~~
oc new-project nodejs-log
oc new-app --name nodejs-log --docker-image docker.registry.example.com:5000/nodejs/nodejs-app:latest
oc expose svc nodejs-log --hostname nodejs.apps.ocp4.example.com

curl http://nodejs.apps.ocp4.example.com
Hello World

oc -n nodejs-log logs nodejs-log-5f4cdb9bcf-rvzk8
2023-12-26T18:23:47.729Z INFO: This is 
a multiline nodejs app


log.
~~~


