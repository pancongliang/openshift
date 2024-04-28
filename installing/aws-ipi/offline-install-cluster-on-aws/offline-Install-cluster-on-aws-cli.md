
## Installing a cluster on AWS in a restricted network

### Download AWS IPI script

```
mkdir ocp-scrept && cd ocp-scrept
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

### Installation preparation 

#### Install the image registry and image release image on the bastion machine and create the install-config
```
source 01-set-parameter.sh && source 03-install-pre.sh
```

#### If the mirroring fails, rerun the following command
```
oc-mirror --config=${IMAGE_SET_CONFIGURATION_PATH}/imageset-config.yaml docker://${HOSTNAME}:8443 --dest-skip-tls
```


### Create OCP cluster

#### Run the installer to create cluster
```
openshift-install create cluster --dir $INSTALL --log-level=info
```

#### Once this entry is seen in the installation log execute script 04-final-setting.sh

```bash
INFO Waiting up to 40m0s (until 6:08PM UTC) for the cluster at https://api.ocp.copan-test.com:6443 to initialize... 
```

### Create record and Configure cluster DNS

#### Open another terminal session
```bash
./ocp-bastion.sh

source ocp-bastion.sh
source 01-set-parameter.sh && source 04-final-setting.sh
```

### Wait for the OCP cluster installation to complete

```bash
cat $INSTALL/.openshift_install.log
time="2024-04-28T11:10:48Z" level=debug msg="Cluster is initialized"
time="2024-04-28T11:10:48Z" level=info msg="Checking to see if there is a route at openshift-console/console..."
time="2024-04-28T11:10:48Z" level=debug msg="Route found in openshift-console namespace: console"
time="2024-04-28T11:10:48Z" level=debug msg="OpenShift console route is admitted"
time="2024-04-28T11:10:48Z" level=info msg="Install complete!"
···
```

```bash
oc get node
oc get mcp
oc get co | grep -v '.True.*False.*False'
```

### Uninstall the OCP cluster and delete the configured AWS infrastructure

#### Uninstall the OCP cluster
```bash
openshift-install destroy cluster --dir $INSTALL --log-level info
```

#### delete the configured AWS infrastructure
```bash
source 01-set-parameter.sh && source 00-del-aws-res.sh
```
