## Installing a cluster quickly on AWS

### Setting Environment Variables

```
export OCP_VERSION=4.14.20
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
export SSH_KEY_PATH="$HOME/.ssh"
export PULL_SECRET_PATH="$HOME/aws-ipi/pull-secret"   # https://cloud.redhat.com/openshift/install/metal/installer-provisioned
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export REGION="ap-northeast-1"
export AWS_ACCESS_KEY_ID="xxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxx"
```

### Installing a cluster quickly on AWS(Client Mac)
```
# Mac:
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-install-mac.sh
source aws-ipi-install.sh

# RHEL:
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-install-rhel.sh
source aws-ipi-install.sh
```


### View the installation log
```
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
tail -f $OCP_INSTALL_DIR/install.log
```

### Set up an alias to run oc with the new cluster credentials

```
# Mac:
echo 'export KUBECONFIG=$OCP_INSTALL_DIR/auth/kubeconfig' >> $HOME/.zshrc
source $HOME/.zshrc

# RHEL:
echo "export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig" >> ~/.bash_profile
source ~/.bash_profile
```

### Uninstalling a cluster on AWS

```
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
export AWS_ACCESS_KEY_ID="xxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxx"

wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-uninstall.sh
source aws-ipi-uninstall.sh
```

### Scheduled installation and uninstallation of OpenShift IPI
```
timedatectl set-timezone Asia/Shanghai
hwclock --systohc
mkdir -p /root/aws-ipi/logs && cd /root/aws-ipi/

wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-install-rhel.sh
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-uninstall.sh

# Add variables to the script
vim aws-ipi-install-rhel.sh
vim aws-ipi-uninstall.sh

crontab -e
0 7 * * 1 /bin/bash /root/aws-ipi/aws-ipi-install-rhel.sh >> /root/aws-ipi/logs/install_`date '+\%m-\%d-\%Y'`.log 2>&1
0 21 * * 3 /bin/bash /root/aws-ipi/aws-ipi-uninstall.sh >> /root/aws-ipi/logs/uninstall_`date '+\%m-\%d-\%Y'`.log 2>&1
0 7 * * 4 /bin/bash /root/aws-ipi/aws-ipi-install-rhel.sh >> /root/aws-ipi/logs/install_`date '+\%m-\%d-\%Y'`.log 2>&1
0 21 * * 5 /bin/bash /root/aws-ipi/aws-ipi-uninstall.sh >> /root/aws-ipi/logs/uninstall_`date '+\%m-\%d-\%Y'`.log 2>&1
```
