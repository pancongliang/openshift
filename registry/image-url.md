### Web
~~~
oc new-app --name todo --image quay.io/redhattraining/todo-angular:v1.1

oc new-app --name hello-openshift --image quay.io/redhattraining/hello-openshift:latest

oc new-app --name nginx --image quay.io/redhattraining/hello-world-nginx:v1.0

oc new-app --name loadtest --image quay.io/redhattraining/loadtest:v1.0

oc new-app --name famous-quotes --image quay.io/redhattraining/famous-quotes:2.1

oc new-app --name todo --image quay.io/redhattraining/todo-angular:v1.2

# PVC
oc new-app --name nginx --image quay.io/redhattraining/hello-world-nginx:v1.0

export STORAGE_CLASS=managed-nfs-storage

oc set volumes deployment/nginx \
  --add --name nginx-storage --type pvc --claim-class $STORAGE_CLASS \
  --claim-mode rwo --claim-size 5Gi --mount-path /usr/share/nginx/html \
  --claim-name nginx-storage
~~~~

#### Database
~~~
oc new-app --name=mysql \
   --image registry.access.redhat.com/rhscl/mysql-57-rhel7:latest \
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
   --image registry.redhat.io/rhel8/postgresql-12:1-43 \
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
cat << EOF | oc apply -f -
apiVersion: v1
kind: List
items:
  - kind: Namespace
    apiVersion: v1
    metadata:
      name: todo-list
      labels:
        app: mysql
  - apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: todo-list-sa
      namespace: todo-list
      labels:
        component: todo-list
  - apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: mysql
      namespace: todo-list
      labels:
        app: mysql
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
  - kind: SecurityContextConstraints
    apiVersion: security.openshift.io/v1
    metadata:
      name: todo-list-scc
    allowPrivilegeEscalation: true
    allowPrivilegedContainer: true
    runAsUser:
      type: RunAsAny
    seLinuxContext:
      type: RunAsAny
    fsGroup:
      type: RunAsAny
    supplementalGroups:
      type: RunAsAny
    volumes:
    - '*'
    users:
    - system:admin
    - system:serviceaccount:todo-list:todo-list-sa
  - apiVersion: v1
    kind: Service
    metadata:
      annotations:
        template.openshift.io/expose-uri: mariadb://{.spec.clusterIP}:{.spec.ports[?(.name=="mysql")].port}
      name: mysql
      namespace: todo-list
      labels:
        app: mysql
        service: mysql
    spec:
      ports:
      - protocol: TCP
        name: mysql
        port: 3306
      selector:
        app: mysql
  - apiVersion: apps/v1
    kind: Deployment
    metadata:
      annotations:
        template.alpha.openshift.io/wait-for-ready: 'true'
      name: mysql
      namespace: todo-list
      labels:
        e2e-app: "true"
    spec:
      selector:
        matchLabels:
          app: mysql
      strategy:
        type: Recreate
      template:
        metadata:
          labels:
            e2e-app: "true"
            app: mysql
        spec:
          securityContext:
            runAsNonRoot: true
          serviceAccountName: todo-list-sa
          containers:
          - image: registry.redhat.io/rhel8/mariadb-105:latest
            name: mysql
            securityContext:
              privileged: false
              allowPrivilegeEscalation: false
              capabilities:
                drop:
                - ALL
              seccompProfile:
                type: RuntimeDefault
            env:
              - name: MYSQL_USER
                value: changeme
              - name: MYSQL_PASSWORD
                value: changeme
              - name: MYSQL_ROOT_PASSWORD
                value: root
              - name: MYSQL_DATABASE
                value: todolist
            ports:
            - containerPort: 3306
              name: mysql
            resources:
              limits:
                memory: 512Mi
            volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
            livenessProbe:
              tcpSocket:
                port: mysql
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
            startupProbe:
              exec:
                command:
                - /usr/bin/timeout
                - 1s
                - /usr/bin/mysql
                - $(MYSQL_DATABASE)
                - -h
                - 127.0.0.1
                - -u$(MYSQL_USER)
                - -p$(MYSQL_PASSWORD)
                - -e EXIT
              initialDelaySeconds: 5
              periodSeconds: 30
              timeoutSeconds: 2
              successThreshold: 1
              failureThreshold: 40 # 40x30sec before restart pod
          volumes:
          - name: mysql-data
            persistentVolumeClaim:
              claimName: mysql
  - apiVersion: v1
    kind: Service
    metadata:
      name: todolist
      namespace: todo-list
      labels:
        app: todolist
        service: todolist
        e2e-app: "true"
    spec:
      ports:
        - name: web
          port: 8000
          targetPort: 8000
      selector:
        app: todolist
        service: todolist
  - apiVersion: apps.openshift.io/v1
    kind: DeploymentConfig
    metadata:
      name: todolist
      namespace: todo-list
      labels:
        app: todolist
        service: todolist
        e2e-app: "true"
    spec:
      replicas: 1
      selector:
        app: todolist
        service: todolist
      strategy:
        type: Recreate
      template:
        metadata:
          labels:
            app: todolist
            service: todolist
            e2e-app: "true"
        spec:
          containers:
          - name: todolist
            image: quay.io/konveyor/todolist-mariadb-go:v2_4
            env:
              - name: foo
                value: bar
            ports:
              - containerPort: 8000
                protocol: TCP
          initContainers:
          - name: init-myservice
            image: docker.io/curlimages/curl:8.5.0
            command: ['sh', '-c', 'sleep 10; until /usr/bin/nc -z -w 1 mysql 3306; do echo Trying to connect to mysql DB port; sleep 5; done; echo mysql DB port reachable']
  - apiVersion: route.openshift.io/v1
    kind: Route
    metadata:
      name: todolist
      namespace: todo-list
    spec:
      path: "/"
      to:
        kind: Service
        name: todolist
EOF
~~~
