# Installing a cluster quickly on AWS

## Download pull-secret
[Download pull-secret](https://cloud.redhat.com/openshift/install/metal/installer-provisioned)


### Install oc command

```bash
curl -L -o oc.tgz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
tar xf oc.tgz
sudo mv oc kubectl /usr/bin
rm oc.tgz README.md
```

### Install the openshift-install command

```bash
export OCP_RELEASE_VERSION="4.14.16"
curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_RELEASE_VERSION/openshift-install-linux.tar.gz
sudo tar xvf openshift-install-linux.tar.gz
sudo rm -rf openshift-install-linux.tar.gz README.md
```

### Install AWS CLI

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
sudo rm -rf aws awscliv2.zip
```

### Store your AWS credentials

```bash
cat << EOF > "$HOME/.aws/credentials"
[default]
aws_access_key_id = AKI···
aws_secret_access_key = KiG···
EOF
```

### Generate SSH key for cluster nodes

```bash
ssh-keygen -N '' -f $HOME/.ssh/id_rsa
```

## Create OCP cluster

### Create install-config.yaml
```bash
export INSTALL="$HOME/ocp-install"
mkdir -p "$INSTALL"

./openshift-install create install-config --dir "$INSTALL"

? SSH Public Key /home/admin/.ssh/id_rsa.pub
? Platform: aws
? Region: eu-west-1
? Base Domain: example.com
? Cluster Name: ocp4
? Pull Secret: *************
```

### Run the installer to create your cluster

```bash
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

```bash
alias oc="oc --kubeconfig=$INSTALL/auth/kubeconfig"
echo alias oc=\"oc --kubeconfig=$INSTALL/auth/kubeconfig\" >> $HOME/.bash_profile

oc get node

oc get co
```
