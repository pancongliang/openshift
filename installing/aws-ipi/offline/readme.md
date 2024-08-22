
## Installing a cluster on AWS in a restricted network

### Download AWS IPI script

```
mkdir aws-ipi && cd aws-ipi
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/aws-ipi/offline/00-dl-script.sh | sh
```


### Change variable parameters
```
vim 01-set-params.sh
source 01-set-params.sh
```


### Create AWS Environment

#### Install AWS CLI(Mac or Linux) and Create VPC, Subnet, IG, Route Table, SG, Endpoint, PHZ, EC2 instance
```
source 02-create-aws-res.sh
```

#### Access EC2 instance(Bastion)
```
./ocp-bastion.sh
```


### Installation preparation 

#### Install the mirror registry and mirroring ocp release image on the bastion machine and create the install-config
```
source 01-set-params.sh && source 03-inst-pre.sh
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

```
INFO Waiting up to 40m0s (until 6:08PM UTC) for the cluster at https://api.ocp.copan-test.com:6443 to initialize... 
```


### Create record and Configure cluster DNS

#### Open a second terminal session
```
./ocp-bastion.sh
```

#### Create record and Configure cluster DNS
```
source 01-set-params.sh && source 04-post-inst-cfg.sh
```


### Wait for the OCP cluster installation to complete

```
cat $INSTALL/.openshift_install.log
time="2024-04-28T11:10:48Z" level=debug msg="Cluster is initialized"
time="2024-04-28T11:10:48Z" level=info msg="Checking to see if there is a route at openshift-console/console..."
time="2024-04-28T11:10:48Z" level=debug msg="Route found in openshift-console namespace: console"
time="2024-04-28T11:10:48Z" level=debug msg="OpenShift console route is admitted"
time="2024-04-28T11:10:48Z" level=info msg="Install complete!"
···
```

```
oc get node
oc get mcp
oc get co | grep -v '.True.*False.*False'
```


### Uninstall the OCP cluster and delete the configured AWS infrastructure

#### Uninstall the OCP cluster
```
openshift-install destroy cluster --dir $INSTALL --log-level info
```

#### delete the configured AWS infrastructure
```
source 01-set-params.sh && source 00-del-aws-res.sh
```
