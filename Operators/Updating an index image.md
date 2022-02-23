## Updating an index image

### 1.查看当前index image 有哪些 operator 及版本

**1.1 确认目前正在使用的 index image 中有哪些 operator 以及版本:** 
~~~

$ podman run -p 50051:50051 -it harbor.registry.example.com/olm/redhat-operator-index:v4.7
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages
{
  "name": "cluster-logging"
}
{
  "name": "elasticsearch-operator"
}
~~~

**1.2 确认目前正在使用的 index image 中 operator 版本:**
~~~
- 在 Terminal-2 中，运行如下命令，其中 index image 为当前使用的 index image:
$ podman run -p 50051:50051 -it harbor.registry.example.com/olm/redhat-operator-index:v4.7

- 在 Terminal-1 中，通过 grpcurl 命令,获取 Bundles,并生成 bundles.txt 文件:
$ grpcurl -plaintext localhost:50051 api.Registry.ListBundles > bundles.txt

- 通过如下命令筛选 bundlePath:
$ grep -A3 <operator-name> bundles.txt | egrep '"(bundlePath|channelName|value)"'
$ grep -A3  elasticsearch-operator bundles.txt | egrep '"(bundlePath|channelName|value)"'
  "channelName": "4.6",
  "bundlePath": "registry.redhat.io/openshift4/ose-elasticsearch-operator-bundle@sha256:037eac94f8d1b63c52f09b0abafd48b7bb3a76db6d01b457fc3a16f63f60a639",
      "value": "{\"packageName\":\"elasticsearch-operator\",\"version\":\"4.6.0-202103010126.p0\"}"
  "channelName": "5.0",
  "bundlePath": "registry.redhat.io/openshift-logging/elasticsearch-operator-bundle@sha256:c011207891172c83989a5042a1e927df94af7d26d730110c9a559460dece3dad",
      "value": "{\"packageName\":\"elasticsearch-operator\",\"version\":\"5.0.8-6\"}"
···output···
~~~

### 2.获取 bundles
**2.1 登录 registry:**
~~~
$ podman login registry.redhat.io
$ podman login <local registry>
~~~

**2.2 获取 bundles 文件:**
~~~
- 在 Terminal-2 中，获取 redhat operator index image:
$ podman run -p 50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.7

- 在 Terminal-1 中，通过 grpcurl 命令,获取 Bundles,并生成 bundles.txt 文件:
$ grpcurl -plaintext localhost:50051 api.Registry.ListBundles > bundles.txt
or
$ grpcurl -plaintext -d '{"name":"cluster-logging"}' localhost:50051 api.Registry.ListBundles 
$ grpcurl -plaintext -d '{"pkgName":"cluster-logging","channelName":"stable"}' localhost:50051 api.Registry.ListBundles
~~~

**2.3 通过如下命令筛选 bundlePath:**
~~~
$ grep -A3 <operator-name> bundles.txt | egrep '"(bundlePath|channelName|value)"'

- 查找 elasticsearch-operator 的 bundlePath:
$ grep -A3 elasticsearch-operator bundles.txt | egrep '"(bundlePath|channelName|value)"'
 ···output···
  "channelName": "stable-5.2",
  "bundlePath": "registry.redhat.io/openshift-logging/elasticsearch-operator-bundle@sha256:6e05a9f3f276f1679d4b18a6e105b2222cefc1710ae7d54b46f00f86cca344c1",
      "value": "{\"packageName\":\"elasticsearch-operator\",\"version\":\"5.2.2-21\"}"

- 查找 cluster-logging 的 bundlePath:
$ grep -A3 cluster-logging bundles.txt | egrep '"(bundlePath|channelName|value)"'
  ···output···
  "channelName": "stable-5.2",
  "bundlePath": "registry.redhat.io/openshift-logging/cluster-logging-operator-bundle@sha256:f21bb9310b2500745317879ac1f214e952c11e77c2a438878ae11812d717d07e",
      "value": "{\"packageName\":\"cluster-logging\",\"version\":\"5.2.2-21\"}"

- 查找 metering-ocp 的 bundlePath:
$ grep -A15 metering-ocp bundles.txt | egrep '"(bundlePath|channelName|value)"'
  "channelName": "4.7",
  "bundlePath": "registry.redhat.io/openshift4/ose-metering-ansible-operator-bundle@sha256:e3d4a8bb9733857d297a215aad5b5d0b833a9915f19321d5a23e9cbaa6cef5ec",
      "value": "{\"packageName\":\"metering-ocp\",\"version\":\"4.7.0-202110141946\"}"
~~~


### 3. 更新并新增 operator
**3.1 更新 elasticsearch-operator，cluster-logging  并新增加 metering-ocp 至新的 image index:**
~~~
$ opm index add \
    --bundles <registry>/<namespace>/<new_bundle_image>@sha256:<digest> \ #<-- 要添加到index的其他bundle images用 , 分隔
    --from-index <registry>/<namespace>/<existing_index_image>:<tag> \    #<-- 之前使用的 index
    --tag <registry>/<namespace>/<existing_index_image>:<tag> \           #<-- 更新后的 index image 具有的image tag
    -p podman                                                             #<-- 使用 podman 时指定此参数, 不然会报unexpected status code [manifests v4.7-2]: 401 Unauthorized

- 例如: 
$ opm index add \
    --bundles registry.redhat.io/openshift4/ose-metering-ansible-operator-bundle@sha256:e3d4a8bb9733857d297a215aad5b5d0b833a9915f19321d5a23e9cbaa6cef5ec,\
    registry.redhat.io/openshift-logging/cluster-logging-operator-bundle@sha256:f21bb9310b2500745317879ac1f214e952c11e77c2a438878ae11812d717d07e,\
    registry.redhat.io/openshift-logging/elasticsearch-operator-bundle@sha256:6e05a9f3f276f1679d4b18a6e105b2222cefc1710ae7d54b46f00f86cca344c1\
    --from-index harbor.registry.example.com/olm/redhat-operator-index:v4.7 \
    --tag harbor.registry.example.com/olm/redhat-operator-index:v4.7-1 \
    --pull-tool  podman
~~~

**3.2 确认新增及更新的 operator:**
~~~
- 确认新增 operator:
$ podman push harbor.registry.example.com/olm/redhat-operator-index:v4.7-1
$ podman run -p 50051:50051 -it harbor.registry.example.com/olm/redhat-operator-index:v4.7-1
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages

- 确认更新的 operator:
$ grpcurl -plaintext localhost:50051 api.Registry.ListBundles > bundles.txt
grep -A3 elasticsearch-operator bundles.txt | egrep '"(bundlePath|channelName|value)"'
$ grep -A3 cluster-logging bundles.txt | egrep '"(bundlePath|channelName|value)"'
$ grep -A15 metering-ocp bundles.txt | egrep '"(bundlePath|channelName|value)"'
~~~


### 4. 缓存 image 至 local registry
**4.1 将 REG_CREDS 环境变量设置为 registry 凭证文件路径(podman login 认证文件):**
~~~
$ podman login harbor.registry.example.com
$ REG_CREDS=${XDG_RUNTIME_DIR}/containers/auth.json
$ cat ${REG_CREDS}
{
        "auths": {
                "harbor.registry.example.com": {
                        "auth": "YWRtaW46cmVkaGF0"
                },
                "registry.redhat.io": {
                        "auth": "cmhuLXN1cHBvcnQtY29wYW46IWNrZGxzazg4"
                }
        }
~~~

**4.2 运行如下命令将 index_image 缓存至 local registry:**
~~~
$ oc adm catalog mirror \
    harbor.registry.example.com/olm/redhat-operator-index:v4.7-1 \
    harbor.registry.example.com/olm \
    -a ${REG_CREDS} \
    --insecure
Output········
wrote mirroring manifests to manifests-redhat-operator-index-1635419959 #<--保存如下文件名称
~~~

### 5. 使用replace命令替换icsp
**5.1 替换icsp（执行此步骤会触发 machine config reboot机制，所有节点都会自动重启）:**
~~~
$ ls manifests-redhat-operator-index-1635419959
catalogsource.yaml  imageContentSourcePolicy.yaml  mapping.txt

$ oc replace -f manifests-redhat-operator-index-1635419959/imageContentSourcePolicy.yaml
imagecontentsourcepolicy.operator.openshift.io/redhat-operator-index created
~~~

**5.2 节点重启:**
~~~
$ oc get mcp
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-8e1b448c2ebc070a3e20e05e1d79147e   False     True       False      3              0                   0                     0                      9d
worker   rendered-worker-d3acd1da90077b696a7aad091c712316   False     True       False      1              0                   0                     0                      9d

- 重启完成:
$ oc get mcp
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-8e1b448c2ebc070a3e20e05e1d79147e   True      False      False      3              3                   3                     0                      9d
worker   rendered-worker-d3acd1da90077b696a7aad091c712316   True      False      False      1              1                   1                     0                      9d
~~~

### 6. 更改现有catalogsource index image url
~~~
$ oc get catalogsource -n openshift-marketplace
$ oc edit catalogsource redhat-operator-index  -n openshift-marketplace
spec:
  displayName: RedHat Operator Catalog
  image: harbor.registry.example.com/olm/redhat-operator-index:v4.7-1  #<-- 更改为最新的 index image: 
~~~


### 7. 验证operator是否有可用更新及增加成功
~~~
- 查看 operator:
$ oc get packagemanifest -n openshift-marketplace
NAME                     CATALOG                   AGE
metering-ocp             RedHat Operator Catalog   4h38m     <-- new add operator
elasticsearch-operator   RedHat Operator Catalog   4h38m
cluster-logging          RedHat Operator Catalog   4h38m

- 查看 catalogsource:
$ oc get catalogsource -n openshift-marketplace
NAME                    DISPLAY                   TYPE   PUBLISHER   AGE
redhat-operator-index   RedHat Operator Catalog   grpc   rh          4h39m

- 验证 elasticsearch-operator 版本:
$ oc get packagemanifest elasticsearch-operator -o yaml -n openshift-marketplace | egrep "currentCSV:"
  - currentCSV: elasticsearch-operator.4.6.0-202103010126.p0
  - currentCSV: elasticsearch-operator.5.0.8-6
  - currentCSV: elasticsearch-operator.5.2.2-21
  - currentCSV: elasticsearch-operator.5.1.2-7
  - currentCSV: elasticsearch-operator.5.2.2-21         <-- new add version

- 验证 cluster-logging 版本:
$ oc get packagemanifest cluster-logging -o yaml -n openshift-marketplace | egrep "currentCSV:"
  - currentCSV: clusterlogging.4.6.0-202103010126.p0
  - currentCSV: cluster-logging.5.0.8-7
  - currentCSV: cluster-logging.5.2.2-21
  - currentCSV: cluster-logging.5.1.2-7
  - currentCSV: cluster-logging.5.2.2-21                <-- new add version
  - 
- 验证 metering-ocp版本:
$ oc get packagemanifest metering-ocp -o yaml -n openshift-marketplace | egrep "currentCSV:"
  - currentCSV: metering-operator.4.7.0-202110141946
~~~

### - 可选: 升级efk
**a.因为之前 efk channel 是 5.1 因此需要手动更改 channel 为 5.2:**
~~~
webconsole -> Administrator -> Operator -> installd Operator-> Project: All Projects -> Red Hat OpenShift Logging -> Subscription -> Channel -> stable-5.2 -> save 
~~~

**b.更改 Channel 后可以看到有 Upgrade available**
~~~
webconsole -> Administrator -> Operator -> installd Operator -> operator status 显示 Upgrade available:
~~~

**c. 升级efk, 在webconsole中先升级elasticsearch-operator成功后，在升级cluster-logging:**
~~~
webconsole -> Administrator -> Operator -> installd Operator -> elasticsearch-operator -> Upgrade available
webconsole -> Administrator -> Operator -> installd Operator -> cluster-logging -> Upgrade available
~~~

**d. 等待pod重启完成:**
~~~
$ oc get po -n openshift-logging
NAME                                            READY   STATUS              RESTARTS   AGE
cluster-logging-operator-5c8b9bb7bd-w88np       1/1     Running             0          4m13s
elasticsearch-cdm-o5hcewp5-1-576cff68b4-bj5nr   0/2     ContainerCreating   0          92s
elasticsearch-cdm-o5hcewp5-2-787b4f965c-89qfd   1/2     Running             0          29m
elasticsearch-im-app-1635436800-5zw9t           0/1     Completed           0          17m
elasticsearch-im-app-1635437700-4q8p7           1/1     Running             0          2m31s
elasticsearch-im-audit-1635436800-5lmxk         0/1     Completed           0          17m
elasticsearch-im-audit-1635437700-xbphn         1/1     Running             0          2m26s
elasticsearch-im-infra-1635436800-bf9dh         0/1     Completed           0          17m
elasticsearch-im-infra-1635437700-ph8xp         1/1     Running             0          2m21s
fluentd-f4bm4                                   1/1     Running             0          29m
fluentd-frbnh                                   1/1     Running             0          29m
fluentd-kz2mv                                   0/2     Init:0/1            0          2m42s
fluentd-l5dzc                                   1/1     Running             0          29m
kibana-6f78fd574d-vzcpb                         0/2     ContainerCreating   0          5m34s

$ oc get po -n openshift-logging
NAME                                            READY   STATUS      RESTARTS   AGE
cluster-logging-operator-5c8b9bb7bd-w88np       1/1     Running     0          94m
elasticsearch-cdm-o5hcewp5-1-576cff68b4-bj5nr   2/2     Running     0          91m
elasticsearch-cdm-o5hcewp5-2-5bff47bc49-hvshm   2/2     Running     0          83m
elasticsearch-im-app-1635443100-j67gw           0/1     Completed   0          2m25s
elasticsearch-im-audit-1635443100-7jsgf         0/1     Completed   0          2m42s
elasticsearch-im-infra-1635443100-pdvx9         0/1     Completed   0          2m39s
fluentd-479fd                                   2/2     Running     0          69m
fluentd-fd6nj                                   2/2     Running     0          70m
fluentd-kz2mv                                   2/2     Running     0          92m
fluentd-n27mk                                   2/2     Running     0          72m
kibana-6f78fd574d-vzcpb                         2/2     Running     0          95m
~~~

**e. 验证升级至预期版本:**
~~~
$ oc get csv -n openshift-logging
NAME                              DISPLAY                            VERSION    REPLACES                         PHASE
cluster-logging.5.2.2-21          Red Hat OpenShift Logging          5.2.2-21   cluster-logging.5.1.2-7          Succeeded
elasticsearch-operator.5.2.2-21   OpenShift Elasticsearch Operator   5.2.2-21   elasticsearch-operator.5.1.2-7   Succeeded
~~~
