
### Build samplelog-app image
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/index.jsp
wget https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/Dockerfile

podman build -t docker.registry.example.com:5000/samplelog/samplelog-app:latest .
podman push docker.registry.example.com:5000/samplelog/samplelog-app:latest
~~~

### Create samplelog app serive
~~~
oc new-project samplelog
oc new-app --name samplelog-app --docker-image docker.registry.example.com:5000/samplelog/samplelog-app:latest
oc expose svc samplelog-app --hostname hello-world.apps.ocp4.example.com
~~~

### Generate log(Generate 10 logs)
~~~
yum install httpd-tools

ab -n 10 -c 1 http://hello-world.apps.ocp4.example.com/
~~~
