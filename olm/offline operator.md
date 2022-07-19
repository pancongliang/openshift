## Using Operator Lifecycle Manager on restricted networks

### - Operator catalogs
~~~
$ podman run -p50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.8
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > redhat-operator-packages.out

$ podman run -p50051:50051 -it registry.redhat.io/redhat/certified-operator-index:v4.8
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > certified-operator-packages.out

$ podman run -p50051:50051 -it registry.redhat.io/redhat/community-operator-index:v4.8
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > community-operator-packages.out

$ podman run -p50051:50051 -it registry.redhat.io/redhat/redhat-marketplace-index:v4.8
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > redhat-marketplace-packages.out
~~~

**1.先决条件**
a.安装 opm 和 grpcurl CLI:**
~~~
- 安装 grpcurl CLI tools:
$ wget https://github.com/fullstorydev/grpcurl/releases/download/v1.7.0/grpcurl_1.7.0_linux_x86_64.tar.gz
$ tar -xvf grpcurl_1.7.0_linux_x86_64.tar.gz
$ cp grpcurl /usr/local/bin/; chmod +x /usr/local/bin/grpcurl

- 安装opm CLI tools（运行环境:rhel8) :
$ wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.8/opm-linux.tar.gz
$ tar -xvf opm-linux.tar.gz
$ cp ./opm /usr/local/bin; chmod +x /usr/local/bin/opm
~~~

b.确保 podman 1.9.3+:
~~~
$ podman --version
podman version 3.2.3
~~~

c.禁用 OperatorHub 默认目录源:
~~~
$ oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
~~~

d.登录 registry.redhat.io 及 local_registry:
~~~
$ podman login registry.redhat.io

$ podman login <target_local_registry>
~~~


### 2.修剪 index image

a. 确认 index image 中的 operator 名称:
~~~
- 在 Terminal-2 中，获取 redhat operator index image:
$ podman run -p 50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.8
  WARN[0004] unable to set termination log path            error="open /dev/termination-log: permission denied"
  INFO[0006] Keeping server open for infinite seconds      database=/database/index.db port=50051
  INFO[0006] serving registry                              database=/database/index.db port=50051

- 在 Terminal-1 中，通过 grpcurl CLI,获取 redhat operator 列表:
$ grpcurl -plaintext localhost:50051 api.Registry/ListPackages > packages.out

- 生成 package.out 文件之后，停止 Terminal 2 的命令，按 ctrl+c 即可停止，然后在 Terminal-1 中确认 operator：
$ cat packages.out | grep -E "elasticsearch-operator|cluster-logging"
  "name": "cluster-logging"
  "name": "elasticsearch-operator"

- 可选 查看operator都有哪些版本[1]
$ podman login registry.redhat.io
$ mkdir ~/.docker
$ cp -p /run/user/$UID/containers/auth.json ~/.docker/config.json
$ opm render --skip-tls registry.redhat.io/redhat/redhat-operator-index:v4.8 > redhat-operator-index-4-8.json
$ cat redhat-operator-index-4-8.json | jq -r 'select(.package == "elasticsearch-operator") | select(.schema == "olm.bundle") | select( [.properties[]|select(.type == "olm.maxOpenShiftVersion")] == []) | .name'
elasticsearch-operator.5.0.12-1
elasticsearch-operator.5.2.11
elasticsearch-operator.5.3.8
elasticsearch-operator.5.4.2
or
$ opm render --skip-tls registry.redhat.io/redhat/redhat-operator-index:v4.8 | jq -r 'select(.package == "elasticsearch-operator") | select(.schema == "olm.bundle") | select( [.properties[]|select(.type == "olm.maxOpenShiftVersion")] == []) | .name'
~~~
[1]How to get the list of operator's versions available in the catalog from an OpenShift operator bundle?：
 - https://access.redhat.com/solutions/6963859

b.使用 opm CLI 修剪 operator hub index image:
~~~
$ opm index prune \
    -f registry.redhat.io/redhat/redhat-operator-index:v4.8 \             #<-- 要修剪的index image
    -p elasticsearch-operator,cluster-logging \                           #<-- 要保留的operator
    -t docker.registry.example.net:5000/olm/redhat-operator-index:v4.8    #<-- 新的index image名称（如果镜像仓库端口为443，默认可以不写端口号）

$ opm index prune \
    -f registry.redhat.io/redhat/redhat-operator-index:v4.8 \
    -p kubernetes-nmstate-operator,mtc-operator,cluster-logging,elasticsearch-operator,kiali-ossm,jaeger-product,servicemeshoperator,serverless-operator,performance-addon-operator,web-terminal,cincinnati-operator \
    -t docker://docker.registry.example.com:5000/olm/redhat-operator-index:v4.8

$ opm index prune \
    -f registry.redhat.io/redhat/redhat-operator-index:v4.7 \
    -p cluster-logging,elasticsearch-operator \
    -t docker://docker.registry.example.net:5000/olm/redhat-operator-index:v4.7
~~~

c.确认新生成的 index imag 并上传至 local registry:
~~~
$ podman push docker.registry.example.net:5000/olm/redhat-operator-index:v4.10
~~~

**3.catalog mirroring**
a. 在可以联网的机器中，缓存 operator 至 local registry:
~~~
$ REG_CREDS=${XDG_RUNTIME_DIR}/containers/auth.json

$ oc adm catalog mirror \
    docker.registry.example.net:5000/olm/redhat-operator-index:v4.8 \   #<-- 修剪过的index image
    docker.registry.example.net:5000/olm \                              #<-- 指定要缓存operator的local registry name 及 port 和 namespace
    -a ${REG_CREDS} \
    --insecure
Output········
wrote mirroring manifests to manifests-redhat-operator-index-1614211642  #<-- 保存输出中的路径信息

$ oc adm catalog mirror \
    docker.registry.example.net:5000/olm/redhat-operator-index:v4.10-1 \
    docker.registry.example.net:5000/olm \
    -a ${REG_CREDS} \
    --insecure

$ oc adm catalog mirror \
    harbor.registry.example.net/olm/redhat-operator-index:v4.8 \
    harbor.registry.example.net/olm \
    -a ${REG_CREDS} \
    --insecure
~~~

**4.创建imageContentSourcePolicy.yaml(ocp 4.8以上不会触发mc重启机制）**
a. 创建imageContentSourcePolicy:
~~~
$ ls manifests-redhat-operator-index-1614211642          #<-- 此信息在 3 -> a 步骤中可以确认
catalogsource.yaml  imageContentSourcePolicy.yaml  mapping.txt

$ oc create -f /root/manifests-redhat-operator-index-1614211642/imageContentSourcePolicy.yaml
imagecontentsourcepolicy.operator.openshift.io/redhat-operator-index created
~~~

### 5.创建catalogsource
~~~
$ vim catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: redhat-operators              #<-- 自定义catalogSource名称
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: docker.registry.example.net:5000/olm/redhat-operator-index:v4.8     #<-- index image tag
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

