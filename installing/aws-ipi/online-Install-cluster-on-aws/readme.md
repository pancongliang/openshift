# Installing a cluster quickly on AWS

### Install aws and oc command

```
export OCP_RELEASE="4.14.20"
export AWS_ACCESS_KEY_ID="AKIAQ2FLxxxxx"
export AWS_SECRET_ACCESS_KEY="KiGyRt5EyHJo+z9NWVawgxxxx"
export INSTALL="$HOME/ocp-install"

curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/online-Install-cluster-on-aws/01-install-pre.sh
source 01-install-pre.sh
```

### Generate SSH key for cluster nodes

```
ssh-keygen -N '' -f $HOME/.ssh/id_rsa
```

## Download pull-secret
[Download pull-secret](https://cloud.redhat.com/openshift/install/metal/installer-provisioned)

### Create install-config

```
mkdir -p "$INSTALL"

./openshift-install create install-config --dir "$INSTALL"

? SSH Public Key /home/admin/.ssh/id_rsa.pub
? Platform: aws
? Region: eu-west-1
? Base Domain: example.com
? Cluster Name: ocp4
? Pull Secret: *************
```

### Run the installer to create  cluster

```
./openshift-install create cluster --dir $INSTALL --log-level=info

INFO Credentials loaded from the "default" profile in file "/home/admin/.aws/credentials" 
INFO Consuming Install Config from target directory 
INFO Creating infrastructure resources...         
INFO Waiting up to 20m0s for the Kubernetes API at https://api.ocp4.example.com:6443... 
INFO API v1.21.6+935ba91 up                       
INFO Waiting up to 30m0s for bootstrapping to complete... 
INFO Destroying the bootstrap resources...        
INFO Waiting up to 40m0s for the cluster at https://api.ocp4.example.com:6443 to initialize... 
INFO Waiting up to 10m0s for the openshift-console route to be created... 
INFO Install complete!                            
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/admin/.aws/pre/auth/kubeconfig' 
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.ocp4.example.com 
INFO Login to the console with user: "kubeadmin", and password: "hD5iw-kKgCU-f3IBR-QzKE3" 
INFO Time elapsed: 39m26s   
```

### Set up an alias to run oc with the new cluster credentials

```
alias oc="oc --kubeconfig=$INSTALL/auth/kubeconfig"
echo alias oc=\"oc --kubeconfig=$INSTALL/auth/kubeconfig\" >> $HOME/.bash_profile

oc get node

oc get co
```
