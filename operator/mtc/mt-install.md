
**1.OpenShift 源集群和目标集群安装mtc operaotr**

~~~
- ocp3.11 安装 MTC
  在线/离线: https://note.youdao.com/s/LHQrytJY
- ocp4.6+ 安装 MTC
a. webconsole -> Operators → OperatorHub -> Migration Toolkit for Containers Operator -> Install

-  Create Instance
b. Migration Toolkit for Containers Operator-> Migration Controller -> Create Instance

- 在 OpenShift 源集群/目标集群确认实例创建成功:
$ oc get pods -n openshift-migration
NAME                                    READY   STATUS    RESTARTS   AGE
migration-controller-5b59dddd5c-hcppz   2/2     Running   0          63m
migration-log-reader-7847c4c4-xmnp2     2/2     Running   0          63m
migration-operator-58d5454657-7q7qq     1/1     Running   0          81m
migration-ui-54489c6d65-v7k8l           1/1     Running   0          62m
restic-52gdk                            1/1     Running   0          66m
restic-bjrwt                            1/1     Running   0          49m
velero-9766bc9b-rnvb8                   1/1     Running   0          66m
~~~

**2.源集群创建测试用 pod:**
~~~
$ oc new-project test
$ oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
$ oc expose svc/nginx --hostname  nginx.apps.ocp4.example.local

$ oc set volumes deployment/nginx \
   --add --name nginx-storage --type pvc --claim-class nfs-storage \
   --claim-mode RWO --claim-size 1Gi --mount-path /data \
   --claim-name nginx-storage

- 在 test 目录下随意创建文件并同步到pod中:
$ oc get po
NAME                     READY   STATUS    RESTARTS   AGE
nginx-5697898488-5lq8k   1/1     Running   0          64s
$ oc rsync ~/test pod/nginx-5697898488-5lq8k:/data
~~~

**3.目标集群安装 MinIO**
a. 通过模板部署 MinIO:
~~~
$ oc new-project minio
$ oc process -f https://raw.githubusercontent.com/liuxiaoyu-git/minio-ocp/master/minio.yaml | oc apply -n minio -f -
- 或者使用如下方法创建minio
$ oc process -f minio.yaml | oc apply -n minio -f -
$ vim minio.yaml
apiVersion: template.openshift.io/v1
kind: Template
labels:
  app: minio-ephemeral
  template: minio-ephemeral-template
message: Minio is an object storage compatible with S3
metadata:
  annotations:
    openshift.io/display-name: Minio (Ephemeral)
    tags: instant-app,minio
  name: minio-ephemeral
objects:

- apiVersion: v1
  kind: Route
  metadata:
    annotations:
      haproxy.router.openshift.io/timeout: 4m
      template.openshift.io/expose-uri: http://{.spec.host}{.spec.path}
    name: ${MINIO_SERVICE_NAME}
  spec:
    tls:
      insecureEdgeTerminationPolicy: Redirect
      termination: edge
    to:
      kind: Service
      name: ${MINIO_SERVICE_NAME}

- apiVersion: v1
  kind: DeploymentConfig
  metadata:
    annotations:
      template.alpha.openshift.io/wait-for-ready: "true"
    name: ${MINIO_SERVICE_NAME}
  spec:
    replicas: 1
    selector:
      name: ${MINIO_SERVICE_NAME}
    strategy:
      type: Recreate
    template:
      metadata:
        labels:
          name: ${MINIO_SERVICE_NAME}
      spec:
        containers:
        - capabilities: {}
          args:
          - server
          - /data
          env:
          - name: MINIO_ROOT_USER
            value: "${MINIO_ROOT_USER}"
          - name: MINIO_ROOT_PASSWORD
            value: "${MINIO_ROOT_PASSWORD}"
          image: 'minio/minio:latest'
          imagePullPolicy: IfNotPresent
          livenessProbe:
            failureThreshold: 3
            httpGet:
              path: /minio/health/live
              port: 9000
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 20
          name: minio
          readinessProbe:
            httpGet:
              path: /minio/health/live
              port: 9000
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 20
          resources:
            limits:
              memory: "2Gi"
              cpu: "1000m"
            requests:
              memory: "1Gi"
              cpu: "1000m"
          securityContext:
            capabilities: {}
            privileged: false
          volumeMounts:
            - mountPath: /data
              name: ephemeral-data
        dnsPolicy: ClusterFirst
        restartPolicy: Always
        volumes:
         - name: ephemeral-data
           emptyDir:
             medium: ""
    triggers:
    - type: ConfigChange

- apiVersion: v1
  kind: Service
  metadata:
    annotations:
      service.alpha.openshift.io/dependencies: '[{"name": "${MINIO_SERVICE_NAME}", "namespace": "", "kind": "Service"}]'
      service.openshift.io/infrastructure: "true"
    name: ${MINIO_SERVICE_NAME}
  spec:
    ports:
    - name: web
      nodePort: 0
      port: 80
      protocol: TCP
      targetPort: 9000
    selector:
      name: ${MINIO_SERVICE_NAME}
    sessionAffinity: None
    type: ClusterIP

# Import minio's image
- apiVersion: "image.openshift.io/v1"
  kind: ImageStream
  metadata:
    name: minio
    label:
      app: minio
      template: minio-template
  spec:
    failedBuildHistoryLimit: 1
    successfulBuildsHistoryLimit: 1
    lookupPolicy:
      local: true
    tags:
      - name: latest
        from:
          kind: DockerImage
          name: docker.io/minio/minio
        importPolicy:
          scheduled: true
~~~

b.查看资源状态，并设置 MinIO Route 变量:
~~~
$ oc get pod -n minio
NAME             READY   STATUS      RESTARTS   AGE
minio-1-deploy   0/1     Completed   0          9m47s
minio-1-r4nns    1/1     Running     0          9m42s

$ MINIO_ADDR=$(oc get route minio -o jsonpath='https://{.spec.host}')
~~~

c.bastion 机器安装 Minio Client:
~~~
$ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
$ chmod +x mc && mv mc /usr/bin
~~~

d.创建 Bucket:
~~~
- 设置访问 MinIO 服务的用户密码:
$ mc --insecure alias set my-minio ${MINIO_ADDR} minio minio123
mc: Configuration written to `/root/.mc/config.json`. Please update your access credentials.
mc: Successfully created `/root/.mc/share`.
mc: Initialized share uploads `/root/.mc/share/uploads.json` file.
mc: Initialized share downloads `/root/.mc/share/downloads.json` file.
Added `my-minio` successfully.

- 创建 Bucket,名称为 ocp-bucket:
$ mc --insecure mb my-minio/ocp-bucket
Bucket created successfully `my-minio/ocp-bucket`.

- 确认 MinIO 中的 Bucket:
$ mc --insecure ls my-minio
[2022-01-07 09:29:26 UTC]     0B ocp-bucket/
~~~

**4.目标集群通过输入以下命令获取 MTC Web 控制台 URL**
~~~
$ oc get -n openshift-migration route/migration -o go-template='https://{{ .spec.host }}'
https://migration-openshift-migration.apps.ocp4.example.com
~~~

**5.将源集群添加到 MTC Web 控制台**
~~~
a. 登录到源集群，确认 migration-controller 服务帐户 token:
$ oc sa get-token migration-controller -n openshift-migration

b. 打开 源集群 MTC Web 控制台:
clusters -> Add cluster
Cluster name: source
URL : https://api.ocp4.example.local:6443   #<-- 源集群的ocp api server
Service account token: 源集群: oc sa get-token migration-controller -n openshift-migration
Exposed route host to image registry: 参考[A]。
Add cluster
~~~
> [A]添加 Image registry 路由
> 1).公开 Image registry 路由：
> Exposed route host to image registry: 这一项根据源集群版本不同，创建route后输入route地址:
> - ocp 3:
> $ oc create route passthrough --service=docker-registry --port=5000 -n default
> $ oc get route -n default
> - ocp 4:
> $ oc create route passthrough --service=image-registry --port=5000 -n openshift-image-registry
> $ oc get route -n openshift-image-registry
>
> 2).目标集群需要可以[访问源集群离线仓库](https://docs.openshift.com/container-platform/4.8/registry/configuring-registry-operator.html#images-configuration-cas_configuring-registry-operator)


**6.将复制存储库添加到 MTC Web 控制台**
~~~
- 打开 目标集群 MTC Web 控制台 -> 点击Add replication repository: 
Storage provider type: S3
Replication repository name: ocp-repository
S3 bucket name: ocp-bucket
S3 endpoint: https://minio-minio.apps.ocp4.example.com   #<-- oc get route -n minio
S3 provider access key: minio
S3 provider secret access key: minio123
- 点击 Add repository
~~~

**7.Migration plans**
~~~
- Add migration plans
1.General
Plan name: test
Source cluster : source
Target cluster: host
Select a replication repository: ocp-repository

2. Namespaces: test

3. Persistent volumes
Migration: Copy

4. Copy options
Copy method: Filesystem copy
Target storage class: nfs-storage  #<-- 选择sc

5. 6. 默认即可
~~~

**8.Start migration plans**
- 开始迁移 -> Migration plans -> test （ ┇ ） -> Cutover，等待片刻，如果显示Migration succeeded则迁移成功:
> 迁移方式:
> 
> stage：   PV暂存（复制）到目标集群,实际服务并不会迁移。
> 
> cutover： 迁移所有资源（project资源+数据）至目标集群。
> 
> rollback：使用cutover迁移完成后可以使用rollback回滚至源集群，回滚时修改/增量的资源和数据不会rollback，rollback即退回至源集群资源的初始状态。
~~~
$ oc get all -n test
NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-5697898488-48md5   1/1     Running   0          39s

NAME            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/nginx   ClusterIP   172.30.248.109   <none>        8080/TCP   37s

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   1/1     1            1           39s

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-5697898488   1         1         1       39s

NAME                                   IMAGE REPOSITORY                                              TAGS   UPDATED
imagestream.image.openshift.io/nginx   image-registry.openshift-image-registry.svc:5000/test/nginx   v1.0   35 seconds ago

NAME                             HOST/PORT                       PATH   SERVICES   PORT       TERMINATION   WILDCARD
route.route.openshift.io/nginx   nginx.apps.ocp4.example.local          nginx      8080-tcp                 None

$ oc delete route nginx

$ oc expose svc/nginx --hostname  nginx.apps.ocp4.example.com
route.route.openshift.io/nginx exposed

$ oc rsh nginx-5697898488-48md5
sh-4.4$ ls /data
test  test.txt

$ curl nginx.apps.ocp4.example.com | grep Hello
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100    72  100    72    0     0    558      0 --:--:-- --:--:-- --:--:--   562
    <h1>Hello, world from nginx!</h1>
~~~
