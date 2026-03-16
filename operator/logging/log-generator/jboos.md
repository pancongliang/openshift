
### Build samplelog-app image
```bash
cat > Dockerfile << EOF
FROM registry.redhat.io/jboss-webserver-5/jws57-openjdk11-openshift-rhel8:5.7.3-2.1687186259
RUN rm -rf /deployments/*
RUN mkdir /deployments/ROOT
COPY ./index.jsp /deployments/ROOT/
EOF

cat > index.jsp << EOF
<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
<head>
    <title>Log Test</title>
</head>
<body>
<%
    out.print("Hello World");
    System.out.println("Hello World");
%>
</body>
</html>
EOF

podman build -t docker.registry.example.com:5000/jboss-webserver-5/samplelog-app:latest .
podman push docker.registry.example.com:5000/jboss-webserver-5/samplelog-app:latest
```

### Create samplelog app serive
```bash
oc new-project samplelog
oc new-app --name samplelog-app --docker-image docker.registry.example.com:5000/jboss-webserver-5/samplelog-app:latest
oc expose svc samplelog-app --hostname hello-world.apps.ocp4.example.com

curl -s http://hello-world.apps.ocp4.example.com |grep "Hello World"
Hello World
```

### Generate log(Generate 10 logs)
```
yum install httpd-tools

ab -n 10 -c 1 http://hello-world.apps.ocp4.example.com/

oc logs -n samplelog samplelog-app-69d56fb7db-bjpmz |grep "Hello World"
Hello World
Hello World
···
```
