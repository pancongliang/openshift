
### Build samplelog-app image
~~~
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/index.jsp
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/Dockerfile

podman build -t docker.registry.example.com:5000/samplelog/samplelog-app:latest .
podman push docker.registry.example.com:5000/samplelog/samplelog-app:latest
~~~

### Create samplelog app serive
~~~
oc new-project samplelog
oc new-app --name samplelog-app --docker-image docker.registry.example.com:5000/samplelog/samplelog-app:latest
oc expose svc samplelog-app --hostname hello-world.apps.ocp4.example.com

curl -s http://hello-world.apps.ocp4.example.com |grep :Hello World"
        Hello World
~~~

### Generate log(Generate 10 logs)
~~~
yum install httpd-tools

ab -n 10 -c 1 http://hello-world.apps.ocp4.example.com/

oc logs -n samplelog samplelog-app-69d56fb7db-bjpmz |grep "Hello World"
Hello World
Hello World
···
~~~
