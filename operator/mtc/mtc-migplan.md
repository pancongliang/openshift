### MTC 迁移
**环境：源集群：4.7，目标集群：4.8**

**迁移方式**
~~~
stage：   PV暂存（复制）到目标集群,实际服务并不会迁移。
cutover： 迁移所有资源（project资源+数据）至目标集群。
rollback：使用cutover迁移完成后可以使用rollback回滚至源集群，回滚时修改/增量的资源和数据不会rollback，rollback即退回至源集群资源的初始状态。
~~~

#### 演示：stage迁移方式

**1.源集群与目标集群安装mtc，并创建Migration Controller实例**
~~~
OpenShift 和 MTC 兼容性：
ocp3.11：mtc 1.5.3
ocp4.5及更早版本：mtc 1.5.3
ocp4.6：1.6.以上
~~~

**2.在目标集MTC Web 控制台中将源集群添加到目标集群 MTC Web 控制台**
~~~
clusters -> Add cluster
Cluster name: source
URL : https://api.ocp4.example.local:6443   #<-- 源集群的ocp api server
Service account token: 源集群: oc sa get-token migration-controller -n openshift-migration
Exposed route host to image registry: 参考[A]。
Add cluster
~~~
> [A] 添加 Image registry 路由
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


**3.按照提示添加复制存储库**

**4.源集群创建测试应用及pv+pvc**
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

**5.为了迁移数据，需要提前在目标集群中创建一个pv，pv的大小与源集群的测试用pv大小一致**
~~~
$ oc create -f pv.yaml 
$ oc get pv pv005
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
pv005   10Gi       RWX            Retain           Available                                   23s
~~~

**6.目标集群MTC UI中创建迁移计划**
~~~
1）General：根据提示输入plan name为以及选择源集群和目标集群信息，并选择复制存储库：
2）Namespaces: stage-demo
3）Persistent volumes： Migration = Copy
4）Copy options
Copy method: Filesystem copy
Target storage class: none  #<--非nfs时需要使用storage class，因此如果使用storage class，选择storage class name。
5）6）跳过：
~~~

**7.开始迁移，按预期会仅迁移数据（pv数据）**
~~~
#1）点击cutover开始迁移，等待迁移完成，迁移完成时会显示Stage succeeded：
#2）进入目标集群并切换至stage-demo project 确认pvc：

$ oc project stage-demo

$ oc get pv pv005
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM               STORAGECLASS   REASON   AGE
pv005   10Gi       RWX            Retain           Bound    stage-demo/pvc005                           4m13s

$ oc get pvc
NAME     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc005   Bound    pv005    10Gi       RWX                           52s

$ oc get po #<-- 按预期不会迁移pod：
No resources found in stage-demo namespace.

#3）为了确认数据是否真实迁移，我们可以创建一个pod，并挂载此pvc确认数据：
$ oc new-app --name loadtest --docker-image quay.io/redhattraining/loadtest:v1.0

$ oc set volumes deployment/loadtest --add --name pv005 --type=PersistentVolumeClaim --claim-name=pvc005 --mount-path /data

$ oc rsh loadtest-79d4d7c987-f86c5
(app-root)sh-4.2$ df -h /data
Filesystem                Size  Used Avail Use% Mounted on
10.74.254.124:/nfs/pv005  120G   14G  106G  12% /data
(app-root)sh-4.2$ cat /data/test 
hello world
~~~

**8. 确认源集群的服务**
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

### 演示：cutover迁移方式(迁移包含pv数据)
**1，2，3步骤因为在stage demo阶段都设置完成，因此我们从第4步骤开始**
**4. 源集群创建测试应用及pv+pvc**
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

**5.为了迁移数据，需要提前在目标集群中创建一个pv，pv的大小与源集群的测试用pv大小一致**
~~~
$ oc create -f pv.yaml 
$ oc get pv pv006
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
pv006   10Gi       RWX            Retain           Available                                   3m59s
~~~

**6.目标集群MTC UI中创建迁移计划**
~~~
1）General：根据提示输入plan name为以及选择源集群和目标集群信息，并选择复制存储库：
2）Namespaces: cutover-demo
3）Persistent volumes： Migration = Copy
4）Copy options
Copy method: Filesystem copy
Target storage class: none  #<--非nfs时需要使用storage class，因此如果使用storage class，选择storage class name。
5）6）跳过：
~~~

**7.开始迁移，按预期会仅迁移数据（pv数据)及project其它资源**
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
~~~

3）确认数据是否真实迁移，我们进入pod确认数据，可以看到数据以迁移成功：
~~~
$ oc rsh nginx-79675c77d6-ljwq5
(app-root)sh-4.2$ df -h /data
Filesystem                Size  Used Avail Use% Mounted on
10.74.254.124:/nfs/pv006  120G   14G  106G  12% /data
(app-root)sh-4.2$ cat /data/test 
hello test
~~~

**8.确认源集群的资源是否存在**
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

**9.查看源集群pod是否可以使用**
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

### 演示 Rollback

**1，2，3步骤因为在stage demo阶段都设置完成，因此我们从第4步骤开始**
**4. 源集群创建测试应用及pv+pvc**
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

**5.为了迁移数据，需要提前在目标集群中创建一个pv，pv的大小与源集群的测试用pv大小一致**
~~~
$ oc create -f pv.yaml 
$ oc get pv pv007
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
pv007   10Gi       RWX            Retain           Available                                   6s
~~~

**6.目标集群MTC UI中创建迁移计划**
~~~
1）General：根据提示输入plan name为以及选择源集群和目标集群信息，并选择复制存储库：
2）Namespaces: rollback-demo
3）Persistent volumes： Migration = Copy
4）Copy options
Copy method: Filesystem copy
Target storage class: none   #<--非nfs时需要使用storage class，因此如果使用storage class，选择storage class name。
5）6）跳过：
~~~

**7.点击cutover开始迁移，按预期会仅迁移数据（pv数据)及project其它资源**
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

**8. 测试Rollback，按预期Rollback会回滚至源集群迁移对象（project）初始状态，回滚时不会带回增量数据**
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
