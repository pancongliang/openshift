### Web
~~~
oc new-app --name todo --image quay.io/redhattraining/todo-angular:v1.1

oc new-app --name hello-openshift --image quay.io/redhattraining/hello-openshift:latest

oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

oc new-app --name loadtest --docker-image quay.io/redhattraining/loadtest:v1.0

oc new-app --name famous-quotes --docker-image quay.io/redhattraining/famous-quotes:2.1

oc new-app --name todo --docker-image quay.io/redhattraining/todo-angular:v1.2

# PVC
oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

export STORAGE_CLASS=managed-nfs-storage

oc set volumes deployment/nginx \
  --add --name nginx-storage --type pvc --claim-class $STORAGE_CLASS \
  --claim-mode rwo --claim-size 5Gi --mount-path /usr/share/nginx/html \
  --claim-name nginx-storage
~~~~

#### Database
~~~
oc new-app --name=mysql \
   --docker-image registry.access.redhat.com/rhscl/mysql-57-rhel7:latest \
   -e MYSQL_USER=user1 -e MYSQL_PASSWORD=mypa55 -e MYSQL_DATABASE=testdb \
   -e MYSQL_ROOT_PASSWORD=r00tpa55

export STORAGE_CLASS=managed-nfs-storage

oc set volumes deployment/mysql \
   --add --name mysql-storage --type pvc --claim-class $STORAGE_CLASS \
   --claim-mode rwm --claim-size 5Gi --mount-path /var/lib/mysql/data \
   --claim-name mysql-storage
~~~
~~~
oc new-app --name postgresql \
   --docker-image registry.redhat.io/rhel8/postgresql-12:1-43 \
   -e POSTGRESQL_USER=redhat \
   -e POSTGRESQL_PASSWORD=redhat123 \
   -e POSTGRESQL_DATABASE=persistentdb

export STORAGE_CLASS=managed-nfs-storage

oc set volumes deployment/postgresql-persistent \
   --add --name postgresql-date --type pvc --claim-class $STORAGE_CLASS \
   --claim-mode rwm --claim-size 5Gi --mount-path /var/lib/pgsql \
   --claim-name postgresql-persistent-pvc
~~~

### Tool
~~~
cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dnsutils
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dnsutils
  template:
    metadata:
      labels:
        app: dnsutils
    spec:
      containers:
        - name: dnsutils
          image: k8s.gcr.io/e2e-test-images/jessie-dnsutils@sha256:143e8cd723f58a8b341526c060d3577e8a129c4fb7bb71cbba343297028331cb
          command:
            - sleep
            - "3600"
EOF

cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      dnsConfig:
        options:
        - name: ndots
          value: "1"   
      containers:
        - name: busybox
          image: docker.io/library/busybox:latest
          command:
            - sleep
            - "3600"
EOF


cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ose
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ose
  template:
    metadata:
      labels:
        app: ose
    spec:
      containers:
        - name: ose
          image: registry.redhat.io/openshift4/ose-cli 
          command:
            - sleep
            - "3600"
EOF
~~~
