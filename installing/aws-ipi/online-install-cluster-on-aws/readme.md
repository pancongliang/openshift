## Installing a cluster quickly on AWS

### Install aws and oc command

```
export OCP_RELEASE="4.14.20"
export AWS_ACCESS_KEY_ID="AKIAQ2FLxxxxx"
export AWS_SECRET_ACCESS_KEY="KiGyRt5EyHJo+z9NWVawgxxxx"
mkdir -p $HOME/ocp-install

curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online-Install-cluster-on-aws/01-install-pre.sh
source 01-install-pre.sh
```


### Download pull-secret
Download [pull-secret](https://cloud.redhat.com/openshift/install/metal/installer-provisioned)

### Create install-config

```
openshift-install create install-config --dir $HOME/ocp-install

? SSH Public Key /home/admin/.ssh/id_rsa.pub
? Platform: aws
? Region: eu-west-1
? Base Domain: example.com
? Cluster Name: ocp4
? Pull Secret: *************
```

### Run the installer to create  cluster

```
openshift-install create cluster --dir $HOME/ocp-install --log-level=info
```

### Set up an alias to run oc with the new cluster credentials

```
alias oc="oc --kubeconfig=$INSTALL/auth/kubeconfig"
echo alias oc=\"oc --kubeconfig=$INSTALL/auth/kubeconfig\" >> $HOME/.bash_profile

oc get node

oc get co
```
