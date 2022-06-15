## mtc operator

### mtc operator 安装

**1. ocp3.11 安装 MTC**
选项 A. ocp3.11 在线环境:
~~~
$ sudo podman login registry.redhat.io

$ sudo podman cp $(sudo podman create \
  registry.redhat.io/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3):/operator.yml ./

$ sudo podman cp $(sudo podman create \
  registry.redhat.io/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3):/controller.yml ./

$ oc create -f operator.yml

$ oc create -f controller.yml

$ oc get pods -n openshift-migration
NAME                                   READY     STATUS    RESTARTS   AGE
migration-log-reader-b86497df8-7s8rd   2/2       Running   0          51m
migration-operator-665d57f5b4-cttsn    1/1       Running   0          53m
restic-48lt9                           1/1       Running   0          52m
restic-ggs4w                           1/1       Running   0          52m
restic-jv2z5                           1/1       Running   0          52m
restic-rwcfn                           1/1       Running   0          52m
restic-xjzr2                           1/1       Running   0          52m
velero-8689f5d7f6-v4nz9                1/1       Running   0          52m
~~~

选项 B. ocp3.11 离线环境（使用可以访问互联网的堡垒机）:
[Installing the legacy Migration Toolkit for Containers Operator on OpenShift Container Platform 3](https://docs.openshift.com/container-platform/4.8/migrating_from_ocp_3_to_4/installing-restricted-3-4.html#migration-installing-legacy-operator_installing-restricted-3-4)
~~~
或使用如下方法：
$ sudo podman login registry.redhat.io

$ sudo podman cp $(sudo podman create \
  registry.redhat.io/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3):/operator.yml ./

- 打开operator.yml，确认image，以我的环境为例，总共有13个image，使用skopeo命令下载image至离线镜像仓库。
$ cat operator.yml
    spec:
      serviceAccountName: migration-operator
      containers:
      - name: operator
        image:  registry.redhat.io/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3
        ···
        - name: REGISTRY
          value: registry.redhat.io
        - name: PROJECT
          value: rhmtc
        - name: RSYNC_TRANSFER_REPO
          value: openshift-migration-rsync-transfer-rhel8
        ···  
- 例如：
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3 \
              docker://harbor.registry.example.net/openshift-migration-legacy-rhel8-operator:v1.5.3
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-rsync-transfer-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-rsync-transfer-rhel8:v1.5.3-1                   
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-hook-runner-rhel7:v1.5.3-2 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-hook-runner-rhel7:v1.5.3-2                      
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-controller-rhel8:v1.5.3-2 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-controller-rhel8:v1.5.3-2                       
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-ui-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-ui-rhel8:v1.5.3-1                               
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-log-reader-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-log-reader-rhel8:v1.5.3-1                       
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-registry-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-registry-rhel8:v1.5.3-1                         
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-velero-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-velero-rhel8:v1.5.3-1                           
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-velero-plugin-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-velero-plugin-rhel8:v1.5.3-1                              
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-velero-restic-restore-helper-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-velero-restic-restore-helper-rhel8:v1.5.3-1     
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-velero-plugin-for-aws-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-velero-plugin-for-aws-rhel8:v1.5.3-1            
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-velero-plugin-for-gcp-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-velero-plugin-for-gcp-rhel8:v1.5.3-1            
$ skopeo copy docker://registry.redhat.io/rhmtc/openshift-migration-velero-plugin-for-microsoft-azure-rhel8:v1.5.3-1 \
              docker://harbor.registry.example.net/rhmtc/openshift-migration-velero-plugin-for-microsoft-azure-rhel8:v1.5.3-1

- 登录到ocp3.11
$ sudo docker cp $(sudo docker create \
  harbor.registry.example.net/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3):/operator.yml ./

$ vim operator.yml
    spec:
      serviceAccountName: migration-operator
      containers:
      - name: operator
        image:  registry.redhat.io/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3  #<-修改镜像地址为离线仓库镜像地址
        ···
        - name: REGISTRY
          value: registry.redhat.io    #<-修改镜像仓库地址为离线仓库地址
        - name: PROJECT
          value: rhmtc                 #<-修改为离线仓库中存放image的project名称
        - name: RSYNC_TRANSFER_REPO
          value: openshift-migration-rsync-transfer-rhel8
        ···  

$ sudo docker cp $(sudo docker create \
  harbor.registry.example.net/rhmtc/openshift-migration-legacy-rhel8-operator:v1.5.3):/controller.yml ./

$ oc create -f operator.yml

$ oc create -f controller.yml
~~~

**2.ocp4.6+ 安装 MTC**
如果是离线环境请参考[离线operator hub](https://docs.google.com/document/d/1uZIZNjtvnidsuXmjNqyZsossF3LOzzSecwNg05bPqaQ/edit)
~~~
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


### 目标集群安装 MinIO S3 存储对象

- 使用mtc operator迁移时需要用到replication repository，此复制存储必须是支持S3的对象存储，主要作用为源集群的资源project资源会先复制到replication repository，然后在从replication repository迁移至目标集群。

**1. 通过模板部署 MinIO:**
~~~
$ oc new-project minio
$ oc process -f https://raw.githubusercontent.com/liuxiaoyu-git/minio-ocp/master/minio.yaml | oc apply -n minio -f -
~~~

**2.查看资源状态，并设置 MinIO Route 变量:**
~~~
$ oc get pod -n minio
NAME             READY   STATUS      RESTARTS   AGE
minio-1-deploy   0/1     Completed   0          9m47s
minio-1-r4nns    1/1     Running     0          9m42s

$ MINIO_ADDR=$(oc get route minio -o jsonpath='https://{.spec.host}')
~~~

**3.bastion 机器安装 Minio Client:**
~~~
$ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
$ chmod +x mc && mv mc /usr/bin
~~~

**4.创建 Bucket:**
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

## 目标集群中添加cluster及replication repository

**1.在目标集群 MTC Web 中将源集群api地址添加至cluster中**
~~~
a. 登录到源集群，确认 migration-controller 服务帐户 token:
$ oc sa get-token migration-controller -n openshift-migration

b. 打开 源集群 MTC Web 控制台:
clusters -> Add cluster
Cluster name: source
URL : https://lb.registry.example.local:8443   #<-- 源集群的ocp api 地址
Service account token: 源集群中输入 oc sa get-token migration-controller -n openshift-migration
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

**2.在目标集群 MTC Web 中添加replication repository**
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

### 目标集群中创建 Migration plans

**迁移方式**
~~~
stage：   PV暂存（复制）到目标集群,实际服务并不会迁移。
cutover： 迁移所有资源（project资源+数据）至目标集群。
rollback：使用cutover迁移完成后可以使用rollback回滚至源集群，回滚时修改/增量的资源和数据不会rollback，rollback即退回至源集群资源的初始状态。
stage+cutover：首先可以通过stage方式迁移数据至目标集群，然后在通过cutover进行迁移
~~~

#### 演示：ocp4.7 ~ ocp4.8 stage迁移方式

**1.源集群创建测试应用及pv+pvc**
~~~
$ oc new-project stage-demo
- 测试用镜像：
$ podman tag quay.io/redhattraining/hello-world-nginx:v1.0 harbor.registry.example.net/image/hello-world-nginx:v1.0
$ podman push harbor.registry.example.net/image/hello-world-nginx:v1.0      #<-- 此镜像仓库源集群和目标集群都可以访问。
$ oc new-app --name nginx --docker-image  harbor.registry.example.net/image/hello-world-nginx:v1.0
$ oc create -f pv.yaml 
$ oc create -f pvc.yaml
$ oc set volumes deployment/nginx --add --name pv005 --type=PersistentVolumeClaim --claim-name=pvc005 --mount-path /data
$ oc expose svc/nginx
$ curl nginx-stage-demo.apps.ocp4.example.local | grep Hello
<h1>Hello, world from nginx!</h1>

$ oc rsh nginx-7564c7664f-b7ssf
sh-4.4$ df -h /data
Filesystem               Size  Used Avail Use% Mounted on
10.72.37.100:/nfs/pv005  200G   43G  157G  22% /data
sh-4.4$ vi /data/test  #<--随意编写内容，以便迁移确认。
hello world
~~~

**2.为了迁移数据，需要提前在目标集群中创建一个pv，pv的大小与源集群的测试用pv大小一致**
~~~
$ oc create -f pv.yaml 
$ oc get pv pv005
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
pv005   10Gi       RWX            Retain           Available                                   23s
~~~

**3.目标集群MTC UI中创建迁移计划**
~~~
1）General：根据提示输入plan name为以及选择源集群和目标集群信息，并选择replication repository：
2）Namespaces: stage-demo
3）Persistent volumes： Migration = Copy
4）Copy options
Copy method: Filesystem copy
Target storage class: none  #<--非nfs时需要使用storage class，因此如果使用storage class，选择storage class name,并且无需在目标集群中提前创建pv。
5）6）跳过：
~~~

**4.开始迁移，按预期会仅迁移数据（pv数据）**
~~~
1）点击 Stage 开始迁移，等待迁移完成，迁移完成时会显示Stage succeeded：
2）进入目标集群并切换至stage-demo project 确认pvc：

$ oc project stage-demo

$ oc get pv pv005
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM               STORAGECLASS   REASON   AGE
pv005   10Gi       RWX            Retain           Bound    stage-demo/pvc005                           4m13s

$ oc get pvc
NAME     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc005   Bound    pv005    10Gi       RWX                           52s

$ oc get po #<-- 按预期不会迁移pod：
No resources found in stage-demo namespace.

3）为了确认数据是否真实迁移，创建一个临时pod，并挂载此pvc确认数据：
$ oc new-app --name loadtest --docker-image quay.io/redhattraining/loadtest:v1.0

$ oc set volumes deployment/loadtest --add --name pv005 --type=PersistentVolumeClaim --claim-name=pvc005 --mount-path /data

$ oc rsh loadtest-79d4d7c987-f86c5
(app-root)sh-4.2$ df -h /data
Filesystem                Size  Used Avail Use% Mounted on
10.74.254.124:/nfs/pv005  120G   14G  106G  12% /data
(app-root)sh-4.2$ cat /data/test 
hello world
~~~

**5. 确认源集群的服务**
~~~
$ oc get all -n stage-demo
NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-7564c7664f-b7ssf   1/1     Running   0          118m

NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/nginx   ClusterIP   172.30.28.34   <none>        8080/TCP   118m

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   1/1     1            1           118m

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-7564c7664f   1         1         1       118m
replicaset.apps/nginx-cd8bf98b5    0         0         0       118m
replicaset.apps/nginx-dbdcbf99f    0         0         0       118m

NAME                                   IMAGE REPOSITORY                                                                  TAGS   UPDATED
imagestream.image.openshift.io/nginx   default-route-openshift-image-registry.apps.ocp4.example.local/stage-demo/nginx   v1.0   2 hours ago

NAME                             HOST/PORT                                  PATH   SERVICES   PORT       TERMINATION   WILDCARD
route.route.openshift.io/nginx   nginx-stage-demo.apps.ocp4.example.local          nginx      8080-tcp                 None

$ oc get pvc -n stage-demo
NAME     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc005   Bound    pv005    10Gi       RWX                           120m

~~~

#### 演示：ocp4.7 ~ ocp4.8 cutover迁移方式(迁移包含pv数据)
**1. 源集群创建测试应用及pv+pvc**
~~~
$ oc new-project cutover-demo
- 测试用镜像：
$ podman tag quay.io/redhattraining/hello-world-nginx:v1.0 harbor.registry.example.net/image/hello-world-nginx:v1.0
$ podman push harbor.registry.example.net/image/hello-world-nginx:v1.0  #<-- 此镜像仓库源集群和目标集群都可以访问。
$ oc new-app --name nginx --docker-image harbor.registry.example.net/image/hello-world-nginx:v1.0
$ oc create -f pv.yaml 
$ oc create -f pvc.yaml
$ oc set volumes deployment/nginx --add --name pv006 --type=PersistentVolumeClaim --claim-name=pvc006 --mount-path /data
$ oc expose svc/nginx
$ curl nginx-cutover-demo.apps.ocp4.example.local | grep Hello
<h1>Hello, world from nginx!</h1>

$ oc rsh nginx-79675c77d6-66g87
sh-4.4$ df -h /data
Filesystem               Size  Used Avail Use% Mounted on
10.72.37.100:/nfs/pv006  200G   43G  157G  22% /data
sh-4.4$ vi /data/test  #<--随意编写内容，以便迁移确认。
hello test
~~~

**2.为了迁移数据，需要提前在目标集群中创建一个pv，pv的大小与源集群的测试用pv大小一致，如果使用storageclass，则可以跳过此步骤**
~~~
$ oc create -f pv.yaml 
$ oc get pv pv006
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
pv006   10Gi       RWX            Retain           Available                                   3m59s
~~~

**3.目标集群MTC UI中创建迁移计划**
~~~
1）General：根据提示输入plan name为以及选择源集群和目标集群信息，并选择replication repository：
2）Namespaces: cutover-demo
3）Persistent volumes： Migration = Copy
4）Copy options
Copy method: Filesystem copy
Target storage class: none  #<--非nfs时需要使用storage class，因此如果使用storage class，选择storage class name。
5）全选，6）跳过：
~~~

**4.开始迁移，按预期会迁移数据（pv数据)和project其它资源**
~~~
1）点击cutover开始迁移，等待迁移完成，迁移完成时会显示Migration succeeded：
2）进入目标集群并切换至cutover-demo project 确认pod/pvc，按预期pod和pvc都会迁移：

$ oc project cutover-demo
$ oc get po
NAME                     READY   STATUS    RESTARTS   AGE
nginx-79675c77d6-ljwq5   1/1     Running   0          50s

$ curl nginx-cutover-demo.apps.ocp4.example.com | grep Hello
<h1>Hello, world from nginx!</h1>

$ oc get pv pv006
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                 STORAGECLASS   REASON   AGE
pv006   10Gi       RWX            Retain           Bound    cutover-demo/pvc006                           11m

$ oc get pvc
NAME     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc006   Bound    pv006    10Gi       RWX                           2m48s

3）确认数据是否真实迁移，我们进入pod确认数据，可以看到数据以迁移成功：
$ oc rsh nginx-79675c77d6-ljwq5
(app-root)sh-4.2$ df -h /data
Filesystem                Size  Used Avail Use% Mounted on
10.74.254.124:/nfs/pv006  120G   14G  106G  12% /data
(app-root)sh-4.2$ cat /data/test 
hello test
~~~

**5.确认源集群的资源是否存在**
~~~
$ oc get all -n cutover-demo
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/nginx   ClusterIP   172.30.189.54   <none>        8080/TCP   99m

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   0/0     0            0           99m

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-79675c77d6   0         0         0       99m
replicaset.apps/nginx-cd8bf98b5    0         0         0       99m
replicaset.apps/nginx-dbdcbf99f    0         0         0       99m

NAME                                   IMAGE REPOSITORY                                                                    TAGS   UPDATED
imagestream.image.openshift.io/nginx   default-route-openshift-image-registry.apps.ocp4.example.local/cutover-demo/nginx   v1.0   2 hours ago

NAME                             HOST/PORT                                    PATH   SERVICES   PORT       TERMINATION   WILDCARD
route.route.openshift.io/nginx   nginx-cutover-demo.apps.ocp4.example.local          nginx      8080-tcp                 None

$ oc get pvc -n cutover-demo 
NAME     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc006   Bound    pv006    10Gi       RWX                           100m
~~~

**6.查看源集群pod是否可以使用**
~~~
$ oc scale deployment/nginx --replicas=2 -n cutover-demo
$ oc get po
NAME                     READY   STATUS    RESTARTS   AGE
nginx-79675c77d6-j68jg   1/1     Running   0          8s
nginx-79675c77d6-snlc6   1/1     Running   0          8s

$ oc rsh nginx-79675c77d6-j68jg
sh-4.4$ df -h /data
Filesystem               Size  Used Avail Use% Mounted on
10.72.37.100:/nfs/pv006  200G   43G  157G  22% /data
sh-4.4$ cat /data/test 
hello test

$ curl nginx-cutover-demo.apps.ocp4.example.com | grep Hello
    <h1>Hello, world from nginx!</h1>

$ oc scale deployment/nginx --replicas=0 -n cutover-demo
~~~

#### 演示 ocp4.7 ~ ocp4.8 Rollback

**1. 源集群创建测试应用及pv+pvc**
~~~
$ oc new-project rollback-demo
- 测试用镜像：
$ podman tag quay.io/redhattraining/hello-world-nginx:v1.0 harbor.registry.example.net/image/hello-world-nginx:v1.0
$ podman push harbor.registry.example.net/image/hello-world-nginx:v1.0  #<-- 此镜像仓库源集群和目标集群都可以访问。
$ oc new-app --name nginx --docker-image harbor.registry.example.net/image/hello-world-nginx:v1.0
$ oc create -f pv.yaml 
$ oc create -f pvc.yaml
$ oc set volumes deployment/nginx --add --name pv007 --type=PersistentVolumeClaim --claim-name=pvc007 --mount-path /data
$ oc expose svc/nginx
$ curl nginx-rollback-demo.apps.ocp4.example.local | grep Hello
<h1>Hello, world from nginx!</h1>

$ oc rsh nginx-5ff8cb4c7f-6wx54
sh-4.4$ df -h /data
Filesystem               Size  Used Avail Use% Mounted on
10.72.37.100:/nfs/pv007  200G   43G  157G  22% /data
sh-4.4$ vi /data/test  #<--随意编写内容，以便迁移确认。
hello test
~~~

**2.为了迁移数据，需要提前在目标集群中创建一个pv，pv的大小与源集群的测试用pv大小一致**
~~~
$ oc create -f pv.yaml 
$ oc get pv pv007
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
pv007   10Gi       RWX            Retain           Available                                   6s
~~~

**3.目标集群MTC UI中创建迁移计划**
~~~
1）General：根据提示输入plan name为以及选择源集群和目标集群信息，并选择replication repository：
2）Namespaces: rollback-demo
3）Persistent volumes： Migration = Copy
4）Copy options
Copy method: Filesystem copy
Target storage class: none   #<--非nfs时需要使用storage class，因此如果使用storage class，选择storage class name。
5）6）跳过：
~~~

**4.点击cutover开始迁移，按预期会仅迁移数据（pv数据)及project其它资源**
~~~
1）点击cutover开始迁移，按等待迁移完成，迁移完成时会显示Migration succeeded：
2）进入目标集群并切换至rollback-demo project 确认pod/pvc，按预期pod和pvc都会迁移：
$ oc project rollback-demo
$ oc get po
NAME                     READY   STATUS    RESTARTS   AGE
nginx-5ff8cb4c7f-7t27d   1/1     Running   0          3m8s

$ curl nginx-rollback-demo.apps.ocp4.example.com | grep Hello
<h1>Hello, world from nginx!</h1>

$ oc get pv pv007
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   REASON   AGE
pv007   10Gi       RWX            Retain           Bound    rollback-demo/pvc007                           8m52s

$ oc get pvc
NAME     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc007   Bound    pv007    10Gi       RWX                           2m41s

3）确认数据是否真实迁移，我们进入pod确认数据，可以看到数据以迁移成功：
$ oc rsh nginx-5ff8cb4c7f-7t27d
(app-root)sh-4.2$ df -h /data
Filesystem                Size  Used Avail Use% Mounted on
10.74.254.124:/nfs/pv007  120G   14G  106G  12% /data
(app-root)sh-4.2$ cat /data/test 
hello test

4) 查看源集群资源是否存在：
$ oc get all -n rollback-demo
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/nginx   ClusterIP   172.30.135.40   <none>        8080/TCP   16m

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   0/0     0            0           16m

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-5ff8cb4c7f   0         0         0       15m
replicaset.apps/nginx-cd8bf98b5    0         0         0       16m
replicaset.apps/nginx-dbdcbf99f    0         0         0       16m

NAME                                   IMAGE REPOSITORY                                                                     TAGS   UPDATED
imagestream.image.openshift.io/nginx   default-route-openshift-image-registry.apps.ocp4.example.local/rollback-demo/nginx   v1.0   16 minutes ago

NAME                             HOST/PORT                                     PATH   SERVICES   PORT       TERMINATION   WILDCARD
route.route.openshift.io/nginx   nginx-rollback-demo.apps.ocp4.example.local          nginx      8080-tcp                 None

$ oc get pvc -n rollback-demo
NAME     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc007   Bound    pv007    10Gi       RWX                           16m
~~~

**5. 测试Rollback，按预期Rollback会回滚至源集群迁移对象（project）初始状态，回滚时不会带回增量数据**
~~~
- 在目标集群上添加数据，然后测试Rollback时是否会把目标增量数据带回源进群：
$ oc project rollback-demo
$ oc get po
NAME                     READY   STATUS    RESTARTS   AGE
nginx-5ff8cb4c7f-7t27d   1/1     Running   0          3m43s

$ oc rsh nginx-5ff8cb4c7f-7t27d
sh-4.4$ df -h /data
Filesystem                Size  Used Avail Use% Mounted on
10.74.254.124:/nfs/pv007  120G   14G  106G  12% /data
sh-4.4$ vi /data/test  
hello test
hello world  #<--添加内容
sh-4.4$ vi /data/hello  #<--创建文件并添加内容
test rollback

- MTC UI上选择Rollback，成功会提示Rollback succeeded， 成功后在源集群确认资源：
$ oc get po -n rollback-demo
NAME                     READY   STATUS    RESTARTS   AGE
nginx-5ff8cb4c7f-njzzw   1/1     Running   0          2m25s

$ oc rsh nginx-5ff8cb4c7f-njzzw 
sh-4.4$ df -h /data
Filesystem               Size  Used Avail Use% Mounted on
10.72.37.100:/nfs/pv007  200G   43G  157G  22% /data
sh-4.4$ ls /data       #<--Rollback之前创建的/data/hello文件已经没有了
test
sh-4.4$ cat /data/test #<--Rollback之前增加的内容也没有了
hello test
~~~

## 问题总结
~~~
1. MTC迁移工具是否必须配置replication repository？，离线环境下是否必须配置多云对象网关（OCS）？
   - replication repository的作用为迁移资源时首先源集群的的资源会复制到replication repository，然后在从replication repository迁移至目标集群，因此必须需要设置replication repository。
   - Doc上表明离线环境下仅支持使用多云对象网关（OCS)，但实际测试离线环境下使用minio对象存储迁移ocp3 project至ocp4正常。

2. 是否可以安装不同版本的mtc operator？
   - 如果源集群与目标集群环境为4.6以上版本，那需要安装mtc 1.6以上版本，且源/目标集群版本必须一直。
   - 如果源集群为3.11，那3.11集群中需要安装mtc 1.5.3版本，此时ocp4.6+以上环境需要安装mtc 1.6以上版本。

3. mtc安装完成后MTC UI -> clusters选项中的host状态为Connection Failed
   - 首先排除代理问题，然后查看版本是否兼容，如果版本不兼容时升级解决，此次问题为客户安装了低版本导致，升级后恢复正常。

4. 卸载mtc，删除project，重新部署，ui无法正常访问，出现如下错误：
{"error":"invalid_request","error_description":"The request is missing a required parameter, includes an invalid parameter value, includes a parameter more than once, or is otherwise malformed."}
   - 参考官方文档，升级mtc operator后还需要在创建一次实例，此时mtc访问都正常，但是卸载mtc后，重新安装时因为存在两个实例，导致出现错误，可以参考kcs解决：https://access.redhat.com/solutions/6879701

5. 在创建migration plan，第四步copy option时，在target storageclass位置无法选择到创建的pvc？
   - 如果使用是nfs存储，可以在第四步copy option时选择none，并在目标集群中提前创建好大小一至的pv。
   - [仅支持nfs存储时使用pv方式](https://docs.openshift.com/container-platform/4.8/migrating_from_ocp_3_to_4/premigration-checklists-3-4.html#target-cluster_premigration-checklists-3-4)
6. 迁移时是否可以更改目标集群中的pvc名称？
   - 使用nfs为存储时，可以创建完migration plan后，在命令行下编辑migration plan名称进行修改，修改后，创建适当大小的pv，并开始迁移，此时显示迁移成功，但因为pod无法挂载pvc导致pending状态，需要人为干预修改pod yaml文件。
~~~
$ oc get migplan migration -n openshift-migration  
NAME        READY   SOURCE   TARGET   STORAGE          AGE
migration   True    ocp4     host     ocp-repository   2m

$ oc describe migplan migration-test-1 -n openshift-migration 
  Persistent Volumes:
    Capacity:           10Gi
    Name:               pv001
    Proposed Capacity:  214117M
    Pvc:
      Access Modes:
        ReadWriteMany
      Has Reference:  true
      Name:           pvc001:pvc001   #<-- 当在mtc ui -> Migration plans -> Target storage class选择 none 时会自动生成与源端相同的pvc名称。
      Namespace:      migration-test-1
~~~

7. 迁移时是否可以更改目标集群的project名称？或者提前在目标集群中创建project？
   - 可以参考[Mapping namespaces](https://docs.openshift.com/container-platform/4.8/migrating_from_ocp_3_to_4/advanced-migration-options-3-4.html#migration-mapping-destination-namespaces-in-the-migplan-cr_advanced-migration-options-3-4)修改migplan，但不能提前创建project。

8. source project有两个pv，如果一个pv设置skip，与这个pv相关的应用是否会迁移？
  - 经测试project下有两个pod，每个pod各一个pv时，选择其中一个pv skip的时候，两个pod都会进行迁移，但其中skip pv对应的pod因为无法适配pvc会显示为pending状态，未skip的pv对应的pod运行正常，即skip选项仅skip掉pv，不会skip pod。

9. 迁移过程中，源集群要迁移的project下rsync-pod出现如下无法pull image现象。
~~~
$ oc get pod
NAME               READY     STATUS             RESTARTS   AGE
nginx-pv-1-build   0/1       Completed          0          1d
rsync-zgmjq        0/2       ImagePullBackOff   0          12m

$ oc describe po rsync-zgmjq
event：Back-off pulling image "docker-registry.default.svc:5000/openshift-migration/openshift-migration-rsync-transfer-rhel8:v1.5.3-1"

$ docker pull docker-registry.default.svc:5000/openshift-migration/openshift-migration-rsync-transfer-rhel8:v1.5.3-1
2a99c93da168: Pull complete 
4418ace46c3d: Pull complete 
59cced56b868: Pull complete 
Digest: sha256:3aa639c6c05fb047ea86e3aaf9a7a7777526b51cbdfde9fed27fbe09b9cd67b4
Status: Downloaded newer image for docker-registry.default.svc:5000/openshift-migration/openshift-migration-rsync-transfer-rhel8:v1.5.3-1
~~~
  - 此问题在测试环境复现，通过image地址可以得知，此镜像仓库为ocp3的内部镜像仓库，而使用mtc迁移project时，会在源/目标集群project下创建rsync-pod并进行同步资源。
    但因为客户安装mtc时把mtc相关的镜像推送至内部的镜像仓库，导致其它project因为权限问题无法从mtc-project中获取image，因此如上情况需要在将被迁移的project下添加如下权限。
~~~
$ oc policy add-role-to-group system:image-puller system:serviceaccounts:<要被迁移的project> -n openshift-migration
~~~


### 相关资料文档
1. DO326 - Red Hat OpenShift Migration Lab
2. [Advanced migration options](https://docs.openshift.com/container-platform/4.8/migrating_from_ocp_3_to_4/advanced-migration-options-3-4.html)
3. [MTC workflow](https://docs.openshift.com/container-platform/4.8/migrating_from_ocp_3_to_4/troubleshooting-3-4.html)
~~~

