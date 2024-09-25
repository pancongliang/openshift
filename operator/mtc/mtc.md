
### Install mtc operator on the OpenShift source and target clusters

~~~
a. webconsole -> Operators → OperatorHub -> Migration Toolkit for Containers Operator -> Install

-  Create Instance
b. Migration Toolkit for Containers Operator-> Migration Controller -> Create Instance

- Confirm that the instance was created successfully in the OpenShift source cluster/target cluster:
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

### Create a test pod in the source cluster
~~~
$ oc new-project test
$ oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
$ oc expose svc/nginx --hostname  nginx.apps.ocp4.example.local

$ oc set volumes deployment/nginx \
   --add --name nginx-storage --type pvc --claim-class nfs-storage \
   --claim-mode RWO --claim-size 1Gi --mount-path /data \
   --claim-name nginx-storage

$ oc get po
NAME                     READY   STATUS    RESTARTS   AGE
nginx-5697898488-5lq8k   1/1     Running   0          64s
$ oc rsync ~/test pod/nginx-5697898488-5lq8k:/data
~~~

### Install MinIO in the target cluster
* Deploy [Minio Object Storage](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-c-deploying-minio-with-nfs-storageclass-as-the-backend-storage) and create a bucket named `mtc-bucket`



### Get the MTC Web Console URL in the target cluster
~~~
$ oc get -n openshift-migration route/migration -o go-template='https://{{ .spec.host }}'
https://migration-openshift-migration.apps.ocp4.example.com
~~~

### Add the source cluster to the MTC Web Console of the target cluster
~~~
a. Log in to the source cluster and view the migration-controller service account token:
$ oc sa get-token migration-controller -n openshift-migration

b. Open the target cluster MTC Web console:
clusters -> Add cluster
Cluster name: source
URL : https://api.ocp4.example.local:6443   #<-- source cluster api server
Service account token: # source cluster: oc sa get-token migration-controller -n openshift-migration
Add cluster
~~~


### Adding a Replication Repository
~~~
- Open the target cluster MTC Web console -> click Add replication repository:
Storage provider type: S3
Replication repository name: ocp-repository
S3 bucket name: mtc-bucket
S3 endpoint: https://minio-minio.apps.ocp4.example.com   #<-- oc get route -n minio
S3 provider access key: minio123
S3 provider secret access key: minio123
~~~

### Migration plans**
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
Target storage class: nfs-storage

5. 6. Default
~~~

### Start migration plans
- Start migration -> Migration plans -> test ( ┇ ) -> Cutover, wait for the migration to complete:
> Migration Type:
> 
> stage：   The PV is temporarily stored (copied) to the target cluster, and the actual service will not be migrated
> 
> cutover： Migrate all resources (project resources + data) to the target cluster.
> 
> rollback：After the migration is completed using cutover, you can use rollback to roll back to the source cluster. During rollback, the modified/incremented resources and data will not be rolled back. Rollback means returning to the initial state of the source cluster resources.
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
