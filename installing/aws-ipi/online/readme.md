## Installing a cluster quickly on AWS

### Installing

#### Setting Environment Variables
```
curl -sLO https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-inst.sh

vim aws-ipi-inst.sh
```

#### Grant sudo password-free permissions
~~~
sudo visudo
root            ALL = (ALL) ALL
user1           ALL=(ALL) NOPASSWD: ALL
~~~

#### Installing a cluster quickly on AWS(Client Mac or RHEL:)

```
bash aws-ipi-inst.sh
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

#### Setting Environment Variables
```
curl -sLO https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online/aws-ipi-uninst.sh

vim aws-ipi-uninst.sh
```

#### Uninstalling a cluster on AWS
```
bash aws-ipi-uninst.sh
```

### Optional

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
bash aws-inst-bastion.sh

ssh ocp-bastion.sh
# Run one by one 
ls
inst-ocp-tool.sh ocp-login.sh inst-registry.sh
```
