## Using Operator Lifecycle Manager on restricted networks

### - 离线缓存 operator
    - 选项 A: Mirror registry 主机可以访问互联网:
    - 选项 B: Mirror registry 在断开连接的主机上:

### - Operator catalogs
~~~
$ podman run -p50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.6
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > redhat-operator-packages.out

$ podman run -p50051:50051 -it registry.redhat.io/redhat/certified-operator-index:v4.6
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > certified-operator-packages.out

$ podman run -p50051:50051 -it registry.redhat.io/redhat/community-operator-index:v4.6
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > community-operator-packages.out

$ podman run -p50051:50051 -it registry.redhat.io/redhat/redhat-marketplace-index:v4.6
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > redhat-marketplace-packages.out
~~~

### 1.先决条件
**1.1 安装 opm 和 grpcurl 命令行**
~~~
- 安装 grpcurl 命令行:
$ wget https://github.com/fullstorydev/grpcurl/releases/download/v1.7.0/grpcurl_1.7.0_linux_x86_64.tar.gz
$ tar -xvf grpcurl_1.7.0_linux_x86_64.tar.gz
$ cp grpcurl /usr/local/bin/; chmod +x /usr/local/bin/grpcurl

- 安装opm（运行环境:rhel8) :
$ wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest-4.6/opm-linux.tar.gz
$ tar -xvf opm-linux.tar.gz
$ cp ./opm /usr/local/bin; chmod +x /usr/local/bin/opm
~~~

**1.2 确保 podman 1.9.3+**
~~~
$ podman --version
podman version 3.2.3
~~~

**1.3 禁用 OperatorHub 默认目录源: true/false**
~~~
$ oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
~~~

**1.4 登录 registry.redhat.io 及 local_registry**
~~~
$ podman login registry.redhat.io
Username: rhn-support-copan
Password: 
Login Succeeded!

$ podman login <target_local_registry>
Username: admin
Password: 
Login Succeeded!
~~~

> **- Prompt** 
> 
> 使用 “可选 B: 如果 Mirror registry 在断开连接的主机上” 缓存镜像， 请确保 OC command 高于 4.6.45 版本。
> 
> [Bug: oc adm catalog mirror doesn work for the air-gapped cluster](https://bugzilla.redhat.com/show_bug.cgi?id=1942818)
>
> [Download: CLI](https://access.redhat.com/downloads/content/290/ver=4.6/rhel---8/4.6.45/x86_64/product-software)

### 2.修剪 index image

**2.1 确认 index image 中的 operator 名称**
~~~
- 在 Terminal-2 中，获取 redhat operator index image:
$ podman run -p 50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.7
  ···mirror.registry.example.com/olm/redhat-operator-index:v4.8-2
  WARN[0004] unable to set termination log path            error="open /dev/termination-log: permission denied"
  INFO[0006] Keeping server open for infinite seconds      database=/database/index.db port=50051
  INFO[0006] serving registry                              database=/database/index.db port=50051

- 在 Terminal-1 中，通过 grpcurl 命令,获取 redhat operator 列表:
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > packages.out

- 生成 package.out 文件之后，停止 Terminal 2 的命令，按 ctrl+c 即可停止，然后在 Terminal-1 中确认 operator：
$ cat packages.out | grep -E "elasticsearch-operator|cluster-logging"
  "name": "cluster-logging"
  "name": "elasticsearch-operator"
~~~

**2.2 使用 opm 修剪 operator hub index image**
~~~
$ opm index prune \
    -f registry.redhat.io/redhat/redhat-operator-index:v4.6 \          #<-- 要修剪的index image
    -p elasticsearch-operator,cluster-logging \                        #<-- 要保留的operator
    -t bastion.ocp4.example.com:5000/olm/redhat-operator-index:v4.6    #<-- 新的index image名称（如果镜像仓库端口为443，默认可以不写端口号）

$ opm index prune \
    -f registry.redhat.io/redhat/redhat-operator-index:v4.8 \
    -p elasticsearch-operator,jaeger-product,kiali-ossm,servicemeshoperator \
    -t mirror.registry.example.com/olm/redhat-operator-index:v4.8
~~~

**2.3 确认新生成的 index imag 并上传至 local registry**
~~~
$ podman images
  REPOSITORY                                                TAG     IMAGE ID      CREATED        SIZE
  bastion.ocp4.example.com:5000/olm/redhat-operator-index   v4.6    746fd8e49d32  3 minutes ago  89.1 MB
  mirror.registry.example.com/olm/redhat-operator-index     v4.6    804153c26291  2 minutes ago  138 MB

- 如果要确认新的index image中的operator，可以参考步骤 2 确认。

$ podman push bastion.ocp4.example.com:5000/olm/redhat-operator-index:v4.6
$ podman push mirror.registry.example.com/olm/redhat-operator-index:v4.6
~~~

### 3.缓存 operator catalog
**3.1 将 REG_CREDS 环境变量设置为 registry credentials 文件路径**
~~~
$ REG_CREDS=${XDG_RUNTIME_DIR}/containers/auth.json
$ cat ${REG_CREDS}
{
        "auths": {
                "bastion.ocp4.example.com:5000": {
                        "auth": "YWRtaW46cmVkaGF0"
                },
                "mirror.registry.example.com": {
                        "auth": "YWRtaW46cmVkaGF0"
                },
                "registry.redhat.io": {
                        "auth": "cmhuLXN1cHBvcnQtY29wYW46IWNrZGxzazg4"
                }
        }
~~~
**3.2 缓存 operator 并生成 manifests 文件**

**- 选项 A: Mirror registry 主机可以访问互联网**

a.执行以下命令将 operator 缓存至 local registry。
~~~
$ oc adm catalog mirror \
    bastion.ocp4.example.com:5000/olm/redhat-operator-index:v4.6 \  #<-- 修剪过的index image
    bastion.ocp4.example.com:5000/olm \                             #<-- 缓存index image仓库
    -a ${REG_CREDS} \
    --insecure

$ oc adm catalog mirror \
    mirror.registry.example.com/olm/redhat-operator-index:v4.6 \
    mirror.registry.example.com/olm \
    -a ${REG_CREDS} \
    --insecure

Output········

- 保存输出中的文件名称：
wrote mirroring manifests to manifests-redhat-operator-index-1614211642 
~~~

**- 选项 B: Mirror registry 在断开连接的主机上**

a. 在可以访问互联网的环境中运行如下命令缓存 image 至本地文件中。
~~~
$ oc adm catalog mirror \
     bastion.ocp4.example.com:5000/olm/redhat-operator-index:v4.6 \ #<-- 修剪过的index image
     file:///local/index  \                                         #<-- 将 image 下载至当前目录中的本地文件
     -a ${REG_CREDS} --insecure  \

Output········

- 保存输出中的路径信息：
   oc adm catalog mirror file://local/index/olm/redhat-operator-index:v4.6 REGISTRY/REPOSITORY
~~~

b. 复制修剪好的 index image 和本地 v2/ 目录至受限网络 Mirror registry 主机。
~~~
- 保存 image 为 operator.tar 文件:
$ podman images
  REPOSITORY                                               TAG      IMAGE ID      CREATED        SIZE
  bastion.ocp4.example.com:5000/olm/redhat-operator-index  v4.6     0f5747b7b7c7  3 hours ago    128 MB

$ podman save -o operator.tar 0f5747b7b7c7

$ cp operator.tar /mnt/usb
$ cp -R -p v2 /mnt/usb
~~~

c. 在受限 local registry 主机中导入index image 和本地 v2/ 目录。
~~~
- 导入 operator.tar 文件转移至受限网络 Mirror registry
$ podman load -i operator.tar

- 修改 tag
$ podman tag 0f5747b7b7c7 mirror.registry.example.com/olm/redhat-operator-index:v4.6

- 导入 index image:
$ podman push mirror.registry.example.com/olm/redhat-operator-index:v4.6

- v2 目录以转移至受限 registry 主机中
$ ls /root/v2
local
~~~

d. 将 REG_CREDS 环境变量设置为 local registry 凭据的文件路径。
~~~
$ podman login mirror.registry.example.com
$ REG_CREDS=${XDG_RUNTIME_DIR}/containers/auth.json
$ cat ${REG_CREDS}
{
        "auths": {
                "mirror.registry.example.com": {
                        "auth": "YWRtaW46cmVkaGF0"
                }
        }
~~~

e. 上传 v2目录至 local registry。
~~~
$ oc adm catalog mirror \
    file://local/index/olm/redhat-operator-index:v4.6 \   #<-- 从步骤 a 的输出中确认
    mirror.registry.example.com/olm \                     #<-- local registry 名称及namespace
    -a ${REG_CREDS} \
    --insecure
Output········
no digest mapping available for file://local/index/olm/redhat-operator-index:v4.6, skip writing to ImageContentSourcePolicy
wrote mirroring manifests to manifests-index/olm/redhat-operator-index-1632672387
~~~


**3.3 创建imageContentSourcePolicy.yaml，执行此步骤会触发 machine config reboot机制，所有节点都会自动重启**

> **- Prompt**  
> 
  >上一步骤（选项B 3.2 e）由于引用了本地目录，因此在最后一步中生成的 imageContentSourcePolicy.yaml 不起作用,因此需要手动重新生成。
  >
  >[Bug: oc adm catalog mirror imageContentSourcePolicy.yaml for disconnected cluster confusion](https://bugzilla.redhat.com/show_bug.cgi?id=1977793)

a. 创建imageContentSourcePolicy。
参考 <选项 A: Mirror registry 主机可以访问互联网> 下载image时可直接创建icsp。
~~~
$ ls manifests-redhat-operator-index-1614211642          #<-- 此信息在 3.2 -> A -> a 步骤中可以确认
catalogsource.yaml  imageContentSourcePolicy.yaml  mapping.txt

$ oc create -f /root/manifests-redhat-operator-index-1632673108/imageContentSourcePolicy.yaml
imagecontentsourcepolicy.operator.openshift.io/redhat-operator-index created
~~~

参考 <选项 B: Mirror registry 在断开连接的主机上> 下载image时，因icsp路径错误，所以需要手动重新生成manifests文件。
~~~
$ oc adm catalog mirror  mirror.registry.example.com/olm/redhat-operator-index:v4.6 \
   mirror.registry.example.com/olm  -a ${REG_CREDS}  --insecure --filter-by-os=linux/amd64 --manifests-only
Output········
no digest mapping available for mirror.registry.example.com/olm/redhat-operator-index:v4.6, skip writing to ImageContentSourcePolicy
 # 保存此文件信息
wrote mirroring manifests to manifests-redhat-operator-index-1632673108

$ ls  /root/manifests-redhat-operator-index-1632673108
catalogSource.yaml  imageContentSourcePolicy.yaml  mapping.txt

$ oc create -f /root/manifests-redhat-operator-index-1632673108/imageContentSourcePolicy.yaml 

$ oc create -f manifests-redhat-operator-index-1614211642/imageContentSourcePolicy.yaml
imagecontentsourcepolicy.operator.openshift.io/redhat-operator-index created
~~~

b. 等待机器重启完成。
~~~
$ oc get mcp
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-ab4953170a100212d326bb9bc01ff049   False     True       False      3              1                   1                     0                      31d
worker   rendered-worker-7dc269d082c6739084dde8674bb554e0   False     True       False      3              1                   1                     0                      31d

$ oc get mcp
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-5193c01d7442e940293ffa7f5416c3f2   True      False      False      3              3                   3                     0                      31d
worker   rendered-worker-cd1d1481a35eec6206d81a6c80d0081c   True      False      False      3              3                   3                     0                      31d
~~~

### 4.创建catalogsource
~~~
$ vim catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: redhat-operators              #<-- 自定义catalogSource名称
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: bastion.ocp4.example.com:5000/olm/redhat-operator-index:v4.6     #<-- index image
  displayName: RedHat Operator Catalog     
  publisher: rh                      #<-- 自定义组织或个人名称
  updateStrategy:                    
    registryPoll:                    #<-- 目录源可以自动检查新版本以保持最新
      interval: 30m

$ oc create -f catalogsource.yaml

$ oc get packagemanifest -n openshift-marketplace
NAME                     CATALOG                   AGE
cluster-logging          RedHat Operator Catalog   2m46s
elasticsearch-operator   RedHat Operator Catalog   2m46s

$ oc get catalogsource -n openshift-marketplace
NAME               DISPLAY                   TYPE   PUBLISHER   AGE
redhat-operators   RedHat Operator Catalog   grpc   rh          3m36s
~~~

### 5. 安装 operator 测试是否有无问题
~~~
$ oc get pods -n openshift-logging
NAME                                            READY   STATUS    RESTARTS   AGE
cluster-logging-operator-78cc77c5c8-vlsmg       1/1     Running     0          22m
elasticsearch-cdm-x5b31iqc-1-5fd6cdb69-z859j    2/2     Running     0          14m
elasticsearch-cdm-x5b31iqc-2-68dfcdfcbb-lznqs   2/2     Running     0          14m
elasticsearch-cdm-x5b31iqc-3-7f96f5b8dc-r5sv5   2/2     Running     0          14m
elasticsearch-im-app-1632678300-zs8c4           0/1     Completed   0          70s
elasticsearch-im-audit-1632678300-gdfhv         0/1     Completed   0          70s
elasticsearch-im-infra-1632678300-7wwvl         0/1     Completed   0          69s
fluentd-6zsxn                                   1/1     Running     0          14m
fluentd-7fszc                                   1/1     Running     0          14m
fluentd-9q9sf                                   1/1     Running     0          14m
fluentd-cl69m                                   1/1     Running     0          14m
fluentd-ssn8v                                   1/1     Running     0          14m
fluentd-z2vw7                                   1/1     Running     0          14m
kibana-78dc469d-jpg2d                           2/2     Running     0          13m
~~~
