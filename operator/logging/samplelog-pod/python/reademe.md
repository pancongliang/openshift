## Generate JSON format logs every 5 seconds

### Build python-app image
~~~
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/python/index.jsp
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/python/Dockerfile

podman build -t docker.registry.example.com:5000/python/python-app:latest .
podman push docker.registry.example.com:5000/python/python-app:latest
~~~

### Create python-app serive
~~~
oc new-project sample-python-app
oc new-app --name python-app --docker-image docker.registry.example.com:5000/python/python-app:latest

oc logs python-app-dcb9c57b5-r8vw2
{"message": "This is a structured log message", "timestamp": "2023-12-22T05:27:50.310511", "log_level": "INFO", "user_id": "12345", "example_key": "example_value"}
~~~
