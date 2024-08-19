## Installing a cluster quickly on AWS

### Setting Environment Variables

```
export OCP_VERSION=4.14.20
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
export SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"
export PULL_SECRET_PATH="$HOME/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export REGION="ap-northeast-1"
export AWS_ACCESS_KEY_ID="xxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxx"
```

### Installing a cluster quickly on AWS(Client Mac)
```
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-install.sh
source aws-ipi-install.sh
```

### View the installation log
```
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
tail -f $OCP_INSTALL_DIR/install.log
```

### Set up an alias to run oc with the new cluster credentials

```
echo 'export KUBECONFIG=$OCP_INSTALL_DIR/auth/kubeconfig' >> $HOME/.zshrc
source $HOME/.zshrc
```

### Uninstalling a cluster on AWS

```
openshift-install destroy cluster --dir $OCP_INSTALL_DIR --log-level info
```
