### Updating a restricted network cluster

**- 准备事项:**
  - 可以访问 Internet 以获取必要的容器image，
  - 对受限网络环境中的容器registry具有写入权限以push和pull image。容器registry必须与Docker registry API v2兼容
  - 安装oc命令行界面 (CLI) 工具
  - 以具有admin特权的用户身份访问集群
  - 有一个最近的etcd备份，以防升级失败
    https://docs.openshift.com/container-platform/4.8/backup_and_restore/disaster_recovery/scenario-2-restoring-cluster-state.html#dr-restoring-cluster-state
  - 确保所有MCP都在运行且未pause
  - pull secret

**1.简化安装定义变量:**
~~~
- 定义发布版本:
$ export OCP_RELEASE=4.8.21

- 定义local mirror registry及host port: 
$ export LOCAL_REGISTRY='harbor.registry.example.com'
$ export LOCAL_REGISTRY='bastion.ocp4.example.com:5000'

- 定义local repository name: 
$ export LOCAL_REPOSITORY='ocp4/openshift4'

- 定义mirror的repository name, 对于生产版本，您必须指定openshift-release-dev: 
$ export PRODUCT_REPO='openshift-release-dev'

- 定义registry pull secret 路径: 
$ export LOCAL_SECRET_JSON='/root/pull-secret'

- 定义发布 mirror: 
$ export RELEASE_NAME="ocp-release"

- 定义服务器的架构类型，例如x86_64.:
$ export ARCHITECTURE=x86_64

- 指定 mirror usb 目录，包括初始正斜杠 (/) 字符: 
$ export REMOVABLE_MEDIA_PATH="/root/mirror"
~~~

**2.查看 mirror 及配置清单:**
~~~
$ oc adm release mirror -a ${LOCAL_SECRET_JSON} --to-dir=${REMOVABLE_MEDIA_PATH}/mirror quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} --dry-run
~~~

**3.将镜像映射到内部registry**
**- 可选(A): mirror registry 可以访问 internet**
a. 通过如下命令，缓存image到 offline mirror registry:
~~~
$ oc adm release mirror -a ${LOCAL_SECRET_JSON} --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} 
# Output········
# To use the new mirrored repository for upgrades, use the following to create an ImageContentSourcePolicy:
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: example
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~

b.复制 a 步骤中输出的ImageContentSourcePolicy内容，然后创建ImageContentSourcePolicy(更新icsp后会重启node):
~~~
$ vim icsp.yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: example
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

$ oc apply -f icsp.yaml

- 更新icsp后会重启node: 
$ oc get mcp 
$ oc get node 
~~~

c.手动创建image signature config map:
~~~
- 将版本添加到OCP_RELEASE_NUMBER环境变量中: 
$ export OCP_RELEASE_NUMBER=4.8.21

- 将集群系统架构添加到architecture环境变量中: 
$ export ARCHITECTURE=x86_64

- 从Quay获取image摘要: 
$ export DIGEST="$(oc adm release info quay.io/openshift-release-dev/ocp-release:${OCP_RELEASE_NUMBER}-${ARCHITECTURE} | sed -n 's/Pull From: .*@//p')"

- 设置摘要算法: 
$ export DIGEST_ALGO="${DIGEST%%:*}"

- 设置摘要签名: 
$ export DIGEST_ENCODED="${DIGEST#*:}"

- 从mirror.openshift.com网站获取image签名: 
$ export SIGNATURE_BASE64=$(curl -s "https://mirror.openshift.com/pub/openshift-v4/signatures/openshift/release/${DIGEST_ALGO}=${DIGEST_ENCODED}/signature-1" | base64 -w0 && echo)

- 创建configmap并应用
$ cat >checksum-${OCP_RELEASE_NUMBER}.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: release-image-${OCP_RELEASE_NUMBER}
  namespace: openshift-config-managed
  labels:
    release.openshift.io/verification-signatures: ""
binaryData:
  ${DIGEST_ALGO}-${DIGEST_ENCODED}: ${SIGNATURE_BASE64}
EOF

$ oc apply -f checksum-${OCP_RELEASE_NUMBER}.yaml
~~~

d.通过如下命令，升级集群
~~~
$ oc adm upgrade --allow-explicit-upgrade --to-image ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}<sha256_sum_value> 

- 例如:
- $ oc adm upgrade --allow-explicit-upgrade --to-image ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}@sha256:f7e664bf56c882f934ed02eb05018e2683ddf42135e33eae1e4192948372d5ae

- sha256_sum_value值确认方法: 
  - 方法1:  https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.8.21/release.txt
  - 方法2:  a 步骤输出中确认，并把 sha256-xxx 中的 - 改为 : 即可: 
  - 方法3:  more /path-to/mirror/config/signature-sha256-xxxx.yaml
~~~

**- 可选(B): offline 环境: 完全隔离的网络中使用usb移动镜像:**
a.通过如下命令，将image和configuration manifests下载至usb移动设备,并保存ImageContentSourcePolicy输出:
~~~
$ oc adm release mirror -a ${LOCAL_SECRET_JSON} --to-dir=${REMOVABLE_MEDIA_PATH}/mirror quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE}
# Output········
# To use the new mirrored repository for upgrades, use the following to create an ImageContentSourcePolicy:
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: example
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~

b.确认镜像是否下载完成，带 .download 的还没下载完:
~~~
ls -ltr /path-to/mirror/v2/openshift/release/blobs
-rw------- 1 root root  32991334 Jul 13 08:32 sha256:02f2c0460a851814ecfab36b80df694c1746c39b480a6ad5a7e4f26e5880969a
-rw------- 1 root root 112982468 Jul 13 08:37 sha256:05812bc5e0758d0374f1ece3b4afb139731446062aaf39ae4fc920971000b884.download
~~~

c.将usb连接至受限网络环境后，上传image至local mirror registry:
~~~
$ oc image mirror  -a ${LOCAL_SECRET_JSON} --from-dir=${REMOVABLE_MEDIA_PATH}/mirror "file://openshift/release:${OCP_RELEASE}*" ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} 
~~~

d.复制 a 步骤中输出的ImageContentSourcePolicy内容，然后创建ImageContentSourcePolicy(更新icsp后会重启node):
~~~
$ vim icsp.yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: example
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - bastion.ocp4.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

$ oc apply -f icsp.yaml

- 更新icsp后会重启node: 
$ oc get mcp 
$ oc get node 
~~~

e.手动创建image signature config map:
~~~ 
- 将版本添加到OCP_RELEASE_NUMBER环境变量中: 
$ export OCP_RELEASE_NUMBER=4.8.21

- 将集群系统架构添加到architecture环境变量中: 
$ export ARCHITECTURE=x86_64

- 从Quay获取image摘要: 
$ export DIGEST="$(oc adm release info quay.io/openshift-release-dev/ocp-release:${OCP_RELEASE_NUMBER}-${ARCHITECTURE} | sed -n 's/Pull From: .*@//p')"

- 设置摘要算法: 
$ export DIGEST_ALGO="${DIGEST%%:*}"

- 设置摘要签名: 
$ export DIGEST_ENCODED="${DIGEST#*:}"

- 从mirror.openshift.com网站获取image签名: 
$ export SIGNATURE_BASE64=$(curl -s "https://mirror.openshift.com/pub/openshift-v4/signatures/openshift/release/${DIGEST_ALGO}=${DIGEST_ENCODED}/signature-1" | base64 -w0 && echo)

- 创建configmap并应用:
$ cat >checksum-${OCP_RELEASE_NUMBER}.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: release-image-${OCP_RELEASE_NUMBER}
  namespace: openshift-config-managed
  labels:
    release.openshift.io/verification-signatures: ""
binaryData:
  ${DIGEST_ALGO}-${DIGEST_ENCODED}: ${SIGNATURE_BASE64}
EOF

$ oc apply -f checksum-${OCP_RELEASE_NUMBER}.yaml
~~~

f. 更新集群:
~~~
$ oc adm upgrade --allow-explicit-upgrade --to-image ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}<sha256_sum_value> 

- 例如:
$ oc adm upgrade --allow-explicit-upgrade --to-image ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}@sha256:f7e664bf56c882f934ed02eb05018e2683ddf42135e33eae1e4192948372d5ae

- sha256_sum_value值确认方法: 
  - 方法1:  https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.8.21/release.txt
  - 方法2:  a 步骤输出中确认，并把 sha256-xxx 中的 - 改为 : 即可: 
  - 方法3:  more /path-to/mirror/config/signature-sha256-xxxx.yaml
~~~
