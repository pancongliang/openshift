
## Disconnected Install on AWS

### Download the script and install and configure infrastructure services through the script

```
sudo mkdir $OCP-SCRIPT&& cd $OCP-SCRIPT
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/offline-install-cluster-on-aws/00-download-script.sh | sh
```

### Change variable parameters
```
vim 01-set-parameter.sh
source 01-set-parameter.sh
```

### Create AWS Environment

#### Install AWS CLI(Mac or Linux) and Create VPC, SG, EC2/ELB Endpoint, PHZ, EC2 instance
```
source 02-set-aws.sh
```

#### Access EC2 instance(Bastion)
```
source ocp-bastion.sh
```

### Install the image registry and image release image on the bastion machine and create the install-config
```
source 01-set-parameter.sh && source 03-install-pre.sh
```

### Create OCP cluster

#### Run the installer to create cluster
```
sudo openshift-install create cluster --dir $INSTALL --log-level=info
```

#### Once this entry is seen in the installation log execute script 04-final-setting.sh

```bash
INFO Waiting up to 40m0s (until 6:08PM UTC) for the cluster at https://api.ocp.copan-test.com:6443 to initialize... 
```

### Create record and Configure cluster DNS

```bash
source ocp-bastion.sh
source 01-set-parameter.sh && source 04-final-setting.sh
```
