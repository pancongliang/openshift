## Download the specified operator version


### 1.获取 bundles
**a. 登录 registry:**
~~~
$ podman login registry.redhat.io
$ podman login <local registry>
~~~

**b. 获取 bundles 文件:**
~~~
- 在 Terminal-2 中，获取 redhat operator index image:
$ podman run -p 50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.7

- 在 Terminal-1 中，通过 grpcurl CLI,获取 Bundles,并生成 bundles.txt 文件:
$ grpcurl -plaintext localhost:50051 api.Registry.ListBundles > bundles.txt
~~~

**c. 通过如下命令筛选 bundlePath:**
~~~
$ grep -A3 <operator-name> bundles.txt | egrep '"(bundlePath|channelName|value)"'

- 查找 elasticsearch-operator 的 bundlePath:
$ grep -A3 elasticsearch-operator bundles.txt | egrep '"(bundlePath|channelName|value)"'
$ grep -A3 file-integrity-operator bundles.txt | egrep '"(bundlePath|channelName|csvName)"'
 ···output···
  "channelName": "stable-5.2",
  "bundlePath": "registry.redhat.io/openshift-logging/elasticsearch-operator-bundle@sha256:6e05a9f3f276f1679d4b18a6e105b2222cefc1710ae7d54b46f00f86cca344c1",
      "value": "{\"packageName\":\"elasticsearch-operator\",\"version\":\"5.2.2-21\"}"

- 无法查找operator时可以尝试使用如下命令
$ cat bundles.txt  | jq -r 'select(.packageName == "elasticsearch-operator")'  | egrep '"(bundlePath|channelName|csvName)"'
$ cat bundles.txt  | jq -r 'select(.packageName == "elasticsearch-operator")'  | egrep '"(bundlePath|channelName|csvName|version)"'
~~~


### 2. 仅缓存指定的operator版本
**a. 更新 elasticsearch-operator，cluster-logging  并新增加 metering-ocp 至新的 image index:**
~~~
- 命令参数详解
$ opm index add \
    --bundles <registry>/<namespace>/<new_bundle_image>@sha256:<digest> \ #<-- 要添加到index的其他bundle images用 , 分隔
    --from-index <registry>/<namespace>/<existing_index_image>:<tag> \    #<-- 之前使用的 index
    --tag <registry>/<namespace>/<existing_index_image>:<tag> \           #<-- 更新添加后的 index image tag
    -p podman                                                             #<-- 使用 podman 时指定此参数, 不然会报unexpected status code [manifests v4.7-2]: 401 Unauthorized


- 首先指定 1 个 operator 的 bundle 创建 index image
$ opm index add \
    --bundles registry.redhat.io/openshift-logging/cluster-logging-operator-bundle@sha256:7b4219619dfd37e9df620098454cef878839b4c359f87959ab232f06d70ebb7f,\
    --tag harbor.registry.example.bet/olm/redhat-operator-index:v4.10.1

- 然后把需要的 operator bundle 全部添加(添加多个bundle时用 , 表示多个)
$ opm index add \
    --bundles registry.redhat.io/openshift-logging/elasticsearch-operator-bundle@sha256:d9244651528cb53cd83d4e16dbe067f36a9e0e60e31faab8eb61b54218b9e022,\
    registry.redhat.io/rhmtc/openshift-migration-operator-bundle@sha256:697a0375f3ff849b4b3d17c203ba8df25d194482655932de7af1bdd35b4cc07a \
    --from-index harbor.registry.example.bet/olm/redhat-operator-index:v4.10.1\
    --tag harbor.registry.example.bet/olm/redhat-operator-index:v4.10.2
~~~

### 3. 缓存步骤与其它方法相同（参考：）
