## Installing a cluster quickly on AWS

### Installing

#### Setting Environment Variables

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

#### Installing a cluster quickly on AWS

```
# Client Mac or RHEL:
curl -sLO https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-inst.sh
source aws-ipi-inst.sh
```

#### Set up an alias to run oc with the new cluster credentials

```
# The script automatically creates a user with the cluster-admin role
oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443

# Client Mac:
echo 'export KUBECONFIG=$OCP_INSTALL_DIR/auth/kubeconfig' >> $HOME/.zshrc
source $HOME/.zshrc

# Client RHEL:
echo "export KUBECONFIG=$OCP_INSTALL_DIR/auth/kubeconfig" >> ~/.bash_profile
oc completion bash >> /etc/bash_completion.d/oc_completion
source ~/.bash_profile
```
### Uninstalling

#### Uninstalling a cluster on AWS

```
export OCP_INSTALL_DIR="$HOME/aws-ipi/ocp"
export AWS_ACCESS_KEY_ID="xxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxx"

curl -sLO https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-uninst.sh
source aws-ipi-uninst.sh
```

### Optional

#### Replace instance type
```
# Instance Type # https://aws.amazon.com/cn/ec2/instance-types/   # Bare Metal: m5.metal
export WORKER_INSTANCE_TYPE='m6i.xlarge'

# oc get machinesets -n openshift-machine-api command confirms the machine of the instance to be replaced.
export MACHINESET='xxxxx-xxxxx-worker-ap-northeast-1d'

# Replace instance              
sh <(curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-replace-instance.sh)
```
#### SSH OCP node
```
curl https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-ssh-deploy.sh | bash

./ssh <NODE-NAME>
```

#### Install bastion and registry
```
curl -sLO https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-inst-bastion.sh

# Changing variable parameters
vim aws-inst-bastion.sh
source aws-inst-bastion.sh

ssh ocp-bastion.sh
# Run one by one 
ls
inst-registry.sh inst-ocp-tool.sh ocp-login.sh
```

#### Scheduled installation and uninstallation of OpenShift IPI
```
timedatectl set-timezone Asia/Shanghai
hwclock --systohc
mkdir -p /root/aws-ipi/logs && cd /root/aws-ipi/

curl -sLO https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-inst.sh
curl -sLO https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-uninst.sh

# Add variables to the script
chmod 777 /root/aws-ipi/aws-ipi-inst.sh aws-ipi-uninst.sh
vim /root/aws-ipi/aws-ipi-inst.sh
vim /root/aws-ipi/aws-ipi-uninst.sh

crontab -e
# Scheduled installation and uninstallation of OpenShift IPI
30 7 * * 1 /bin/bash /root/aws-ipi/aws-ipi-inst.sh >> /root/aws-ipi/logs/inst_`date '+\%m-\%d-\%Y'`.log 2>&1
00 21 * * 3 /bin/bash /root/aws-ipi/aws-ipi-uninst.sh >> /root/aws-ipi/logs/uninst_`date '+\%m-\%d-\%Y'`.log 2>&1
30 7 * * 4 /bin/bash /root/aws-ipi/aws-ipi-inst.sh >> /root/aws-ipi/logs/inst_`date '+\%m-\%d-\%Y'`.log 2>&1
00 21 * * 5 /bin/bash /root/aws-ipi/aws-ipi-uninst.sh >> /root/aws-ipi/logs/uninst_`date '+\%m-\%d-\%Y'`.log 2>&1
```
