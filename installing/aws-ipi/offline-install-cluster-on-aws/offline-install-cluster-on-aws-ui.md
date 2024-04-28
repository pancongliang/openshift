
# Disconnected Install on AWS

## Create AWS Environment

### Create VPC

For this example, we'll use the name `copan-dc1` for resources related to this vpc.

Go to
[https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#vpcs:](https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#vpcs:)

Click "Create VPC"

- For "Resources to create", select "VPC, subnets, etc."
- For "Name tag auto-generation", enter `copan-dc1`
- Change "Availability Zones" to 1.
- Expand "Customize AZs" and change availability zone to `ap-northeast-1a`
- Ensure "Number of public subnets" is set to 1
- Expand "Customize public subnets CIDR blocks" and enter `10.0.0.0/24`
- Ensure "Number of private subnets" is set to 1
- Expand "Customize private subnets CIDR blocks" and enter `10.0.1.0/24`
- Ensure "NAT gateways" is set to None
- Ensure VPC endpoints is set to "S3 Gateway"
- Under "DNS options", check both

  - Enable DNS hostnames
  - Enable DNS resolution

Click "Create VPC"

Make a note of your VPC ID, such as `vpc-0554d61964eba9fa4`.

You will need this to filter resources in AWS later.

### Create security group for VPC

Go to
[https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#securityGroups:](https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#securityGroups:)

Click "Create security group"

- For "Name", use `copan-dc1-sg`
- For "Description", use `External SSH and all internal traffic`
- For "VPC", select `copan-dc1-vpc`
- Under Inbound Rules, click "Add rule"
  - Type: SSH
  - Source: 0.0.0.0/0
- Under Inbound Rules, click "Add rule"
  - Type: All traffic
  - Source: 10.0.0.0/16
- Under Outbound Rules, click "Add rule"
  - Type: All traffic
  - Destination: 0.0.0.0/0
- Under Tags, click "Add new tag"
  - Key: Name
  - Value: copan-dc1-sg

### Create ec2 endpoint in VPC

Go to
[https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#Endpoints:](https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#Endpoints:)

Click "Create endpoint"

- For "Name tag", use `copan-dc1-vpce-ec2`
- For "Service category", select "AWS services"
- Enter "ec2" in the "Filter services" search box
- Select the service "com.amazonaws.ap-northeast-1.ec2"
- For "VPC", select your VPC
- Under "VPC", expand "Additional settings" and ensure "Enable DNS name" is checked.
- In "Subnets", check Availability Zone "ap-northeast-1a"
- In "Subnets", for the "ap-northeast-1a" AZ, select your private subnet
- In "Security groups", check the `copan-dc1-sg` group
- In "Policy", ensure "Full access" is checked

Click "Create endpoint"

### Create ELB endpoint in VPC

Go to
[https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#Endpoints:](https://console.aws.amazon.com/vpc/home?region=ap-northeast-1#Endpoints:)

Click "Create endpoint"

- For "Name tag", use `copan-dc1-vpce-elb`
- For "Service category", select "AWS services"
- Enter "load" in the "Filter services" search box
- Select the service "com.amazonaws.ap-northeast-1.elasticloadbalancing"
- For "VPC", select your VPC
- Under "VPC", expand "Additional settings" and ensure "Enable DNS name" is checked.
- In "Subnets", check Availability Zone "ap-northeast-1a"
- In "Subnets", for the "ap-northeast-1a" AZ, select your private subnet
- In "Security groups", check the `copan-dc1-sg` group
- In "Policy", ensure "Full access" is checked

Click "Create endpoint"

### Create a Route 53 private hosted zone for your VPC

Go to
[https://console.aws.amazon.com/route53/v2/hostedzones](https://console.aws.amazon.com/route53/v2/hostedzones)

Click "Create hosted zone"

- For domain name, enter `copan-dc1.copan-test.com`
- Change the Type to "Private hosted zone"
- In the "Region" box, select ap-northeast-1 region
- In the VPC ID box, select the vpc you created above

Click "Create hosted zone"

**Note:** Expand the "Hosted zone details" section and record the "Hosted zone ID"
`Z10124192ZYQ7PDC4IW9S`

## Setup bastion EC2 instance in VPC

### Create bastion instance

Go to
[https://console.aws.amazon.com/ec2/v2/home?region=ap-northeast-1#Instances:v=3](https://console.aws.amazon.com/ec2/v2/home?region=ap-northeast-1#Instances:v=3)

Click "Launch instances"

- Step 1: Choose an Amazon Machine Image (AMI)
  - Search for "Red Hat"
  - Under "Red Hat Enterprise Linux 8 (HVM), SSD Volume Type" ensure "64-bit (x86)" is selected
  - Click "Select" for "Red Hat Enterprise Linux 8 (HVM), SSD Volume Type"
- Step 2: Choose an instance type
  - Select "t3.large"
  - Click "Next: Configure Instance Details"
- Step 3: Configure Instance Details
  - For "Network", select your VPC
  - For "Subnet", select your public subnet
  - For "Auto-assign Public IP", select "Enable"
  - Click "Next: Add Storage"
- Step 4: Add Storage
  - For the Root volume, change size to "100"
  - Click "Next: Add Tags"
- Step 5: Add Tags
  - Click "Add Tag"
  - Set Key to "Name"
  - Set Value to `copan-bastion`
  - Click "Next: Configure Security Group"
- Step 6: Configure Security Group
  - Select "Select an existing security group"
  - Select the security group named `copan-dc1-sg1`
  - Click "Review and Launch"
- Step 7: Review Instance Launch
  - Click "Launch"
- Dialog box "Select an exiting key pair or create a new key pair"
  - If you already have a key pair stored:
    - Select the key pair name
    - Check the box acknowledging you have access to the private key file
    - Click "Launch Instance"
  - If you do not have a key pair stored:
    - Select "Create a new key pair"
    - For "Key pair type", select RSA
    - For "Key pair name", enter `copan-dc1-vpc-keypair`
    - Click "Download Key Pair" and save the `.pem` file
    - Click "Launch Instance"

Click "View Instances"

Find your instance by the name you gave it in the tag "Name".

Wait for it to be in the state "Running".

### SSH into bastion

```bash
ssh -i private-key.pem ec2-user@1.2.3.4
```

### Install required utilities

```bash
sudo yum -y install bind-utils jq podman zip
```

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

### Install the oc-mirror command

```bash
curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
sudo tar -xvf oc-mirror.tar.gz -C /usr/local/bin/ && sudo chmod a+x /usr/local/bin/oc-mirror
sudo rm -rf oc-mirror.tar.gz
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
mkdir "$HOME/.aws"
vi "$HOME/.aws/credentials"
```

The credentials file should look like this:

```bash
[default]
aws_access_key_id = AKI...
aws_secret_access_key = QjX...
```

## Setup Quay Mirror Registry

### Install a quay mirror registry instance

```bash
curl -L -o mirror.tgz https://developers.redhat.com/content-gateway/file/pub/openshift-v4/clients/mirror-registry/1.0/mirror-registry.tar.gz
tar xf mirror.tgz
sudo ./mirror-registry install -v --quayHostname $HOSTNAME | tee quay-install.log
sudo rm -f *.tar mirror-registry mirror.tgz
```

### Extract quay password from install log

```bash
grep -oP "init, \K[^)]+" quay-install.log | tee quay_creds
```

### Add the quay mirror registry CA to the system trust store

```bash
sudo cp /etc/quay-install/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract
trust list | grep -C 2 "$HOSTNAME"
```

You should see output similar to this:

```yaml
pkcs11:id=%08%1C%EC%B8%7A%0E%25%AE%62%DA%51%64%F9%0A%55%C5%B5%D1%4B%71;type=cert
  type: certificate
  label: ip-10-0-0-223.ap-northeast-1.compute.internal
  trust: anchor
  category: authority
```

### Download your OpenShift installation pull secret

- Go to:
  - [https://console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret)
- Select “Copy pull secret”.
- In your bastion, run

    ```bash
    vi $HOME/pull-secret
    ```

### Login to your mirror registry

Login to your mirror registry and Save the PULL_SECRET file either as $XDG_RUNTIME_DIR/containers/auth.json

```bash
podman login -u init -p $(cat quay_creds) $HOSTNAME:8443
podman login -u init -p $(cat quay_creds) --authfile $HOME/pull-secret $HOSTNAME:8443
cat $HOME/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
```

### Mirror the OCP image repository

Run:

```bash
export OCP_RELEASE_VERSION="4.14.16"
export OCP_RELEASE_CHANNEL="$(echo $OCP_RELEASE_VERSION | cut -d. -f1,2)"

cat << EOF > $HOME/imageset-config.yaml
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
 registry:
   imageURL: $HOSTNAME:8443/mirror/metadata
   skipTLS: false
mirror:
  platform:
    channels:
      - name: stable-${OCP_RELEASE_CHANNEL}
        minVersion: ${OCP_RELEASE_VERSION}
        maxVersion: ${OCP_RELEASE_VERSION}
        shortestPath: true
EOF

oc mirror --config=$HOME/imageset-config.yaml docker://$HOSTNAME:8443 --dest-skip-tls
```


## Prepare to create OCP cluster

### Generate SSH key for cluster nodes

```bash
ssh-keygen -N '' -f $HOME/.ssh/id_rsa
```

### Set variable parameters

```bash
export INSTALL="$HOME/ocp-install"
mkdir -p "$INSTALL"

export BASE_DOMAIN=copan-test.com
export CLUSTER_NAME=ocp
export REGION=ap-northeast-1
export ZONE=ap-northeast-1a
export VPC_NAME=copan-dc1-vpc
export VPC_NAME_RESET=$(echo $VPC_NAME | sed 's/-vpc//')
export PRIVATE_SUBNET=$(aws ec2 describe-subnets --region $REGION --filters "Name=tag:Name,Values=$VPC_NAME_RESET-subnet-private1-$ZONE" | jq -r '.Subnets[0].SubnetId')

export HOSTED_ZONE_NAME=copan-test.com
export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $HOSTED_ZONE_NAME --max-items 1 | jq -r '.HostedZones[0].Id' | sed 's#/hostedzone/##')

export SSH_PUB_STR="$(cat ${HOME}/.ssh/id_rsa.pub)"
export AUTH_VALUE=$(jq -r ".auths[\"$HOSTNAME:8443\"].auth" $HOME/pull-secret)

sudo cp "/etc/quay-install/quay-rootCA/rootCA.pem" "/etc/quay-install/quay-rootCA/rootCA.pem.bak"
sudo sed -i 's/^/  /' /etc/quay-install/quay-rootCA/rootCA.pem.bak
export export REGISTRY_CA_CERT_FORMAT="$(cat /etc/quay-install/quay-rootCA/rootCA.pem.bak)"
```

### Create install-config.yaml
```yaml
cat << EOF > $INSTALL/install-config.yaml
apiVersion: v1
baseDomain: $BASE_DOMAIN
credentialsMode: Passthrough
controlPlane:   
  hyperthreading: Enabled 
  name: master
  platform:
    aws:
      zones:
      - $ZONE
      rootVolume:
        iops: 4000
        size: 500
        type: io1 
      metadataService:
        authentication: Optional 
      type: m6i.xlarge
  replicas: 3
compute: 
- hyperthreading: Enabled 
  name: worker
  platform:
    aws:
      rootVolume:
        iops: 2000
        size: 500
        type: io1 
      metadataService:
        authentication: Optional 
      type: c5.4xlarge
      zones:
      - $ZONE
  replicas: 3
metadata:
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes 
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $REGION
    subnets: 
    - $PRIVATE_SUBNET
    hostedZone: $HOSTED_ZONE_ID
fips: false
publish: Internal
pullSecret: '{"auths":{"$HOSTNAME:8443": {"auth": "$AUTH_VALUE","email": "test@redhat.com"}}}'
sshKey: '${SSH_PUB_STR}'
additionalTrustBundle: | 
${REGISTRY_CA_CERT_FORMAT}
imageContentSources: 
- mirrors:
  - $HOSTNAME:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- mirrors:
  - $HOSTNAME:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
EOF
```

### Backup your install-config.yaml file

The `install-config.yaml` file will be deleted during cluster creation. Create a backup
to use if you need to reinstall the cluster or to verify how the cluster was created.

```bash
cp "$INSTALL/install-config.yaml" "$HOME/install.yaml.bak"
```

## Create OCP cluster

### Set up an alias to run oc with the new cluster credentials

```bash
echo export KUBECONFIG=$HOME/$INSTALL/auth/kubeconfig >> $HOME/.bash_profile
source $HOME/.bash_profile
```

### Run the installer to create your cluster

```bash
./openshift-install create cluster --dir $INSTALL --log-level=info
```

Once you see this entry on the install logs:

```bash
INFO Waiting up to 40m0s (until 6:08PM UTC) for the cluster at https://api.ocp.copan-test.com:6443 to initialize... 
```

You will need to complete the "Configure cluster DNS" steps below before the 40 minutes are up
or the install will fail.

If you don't have your VPC ID, find it before starting the install to help ensure you
can quickly complete the cluster DNS configuration.

### Configure cluster DNS

In the installer output, once the bootstrap node has been destroyed, you should see a
line like this in the log:

```bash
INFO Waiting up to 40m0s (until 6:08PM UTC) for the cluster at https://api.ocp.copan-test.com:6443 to initialize... 
```

Once this appears, go to
[https://console.aws.amazon.com/ec2/v2/home?region=ap-northeast-1#LoadBalancers:sort=loadBalancerName](https://console.aws.amazon.com/ec2/v2/home?region=ap-northeast-1#LoadBalancers:sort=loadBalancerName)

In the search box, enter your VPC ID, such as `vpc-0a35f5fee30dfd101`, to view just the
load balancers in your VPC.

Or can also view it with the command
```bash
export VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=$VPC_NAME" | jq -r '.Vpcs[0].VpcId')
aws elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].DNSName"
```

Watch for a load balancer whose Type is `classic`. This load balancer will have a Name that is a
long hexidecimal value. Its DNS name will start with `internal-` followed by the Name.

When you see this load balancer (note that it will not have a "State"), follow these steps:

Make a note of the load balancer's name. You'll need to select it from a list in a following step.

Open another terminal to the bastion and run:

```bash
oc edit dnses.config/cluster
```

In the editor, under `spec`, remove the `privateZone` stanza. It should look similar to this:

```yaml
apiVersion: config.openshift.io/v1
kind: DNS
metadata:
  creationTimestamp: "2022-03-07T14:37:25Z"
  generation: 2
  name: cluster
  resourceVersion: "24778"
  uid: 200759e9-3f21-4cb3-8802-ac1221e6ebf9
spec:
  baseDomain: ocp.copan-test.com
status: {}
```

Save your changes.

Go to
[https://console.aws.amazon.com/route53/v2/hostedzones#](https://console.aws.amazon.com/route53/v2/hostedzones#)

Click on the hosted zone you created for your VPC. In this example, its name would be `copan-test.com`

Click "Create record"

- For "Record name", enter `*.apps`
- For "Record type", ensure `A - Routes traffic to an IPv4 address and some AWS resources` is selected..
- For "Value", click the toggle to enable "Alias"
  - For "Choose endpoint", select `Alias to Application and Classic Load Balancer`
  - For "Choose region", select `Asia Pacific (Tokyo)`
  - For "Choose load balancer", select your internal load balancer. Note: Its name in
    this list will be prefixed with `dualstack.`. For example:
    `dualstack.internal-a82826d7a9ba94672b25d211de36ad2c-829981290.ap-northeast-1.elb.amazonaws.com`

Click "Create Record"

Go back to watching the logs from the `openshift-install` command.

The install should complete successfully.

### (Optional) Monitor cluster initialization

In the installer output, once the installer is waiting for bootstrapping to complete,
you'll see a line like this in the output:

```bash
INFO Waiting up to 30m0s for bootstrapping to complete...
```

You can find the IP addresses of the master nodes by running:

```bash
$ oc get node
NAME                                            STATUS   ROLES                  AGE   VERSION
ip-10-0-1-199.ap-northeast-1.compute.internal   Ready    worker                 28m   v1.27.10+c79e5e2
ip-10-0-1-30.ap-northeast-1.compute.internal    Ready    worker                 29m   v1.27.10+c79e5e2
ip-10-0-1-6.ap-northeast-1.compute.internal     Ready    control-plane,master   44m   v1.27.10+c79e5e2
ip-10-0-1-84.ap-northeast-1.compute.internal    Ready    control-plane,master   44m   v1.27.10+c79e5e2
ip-10-0-1-85.ap-northeast-1.compute.internal    Ready    control-plane,master   44m   v1.27.10+c79e5e2
ip-10-0-1-88.ap-northeast-1.compute.internal    Ready    worker                 28m   v1.27.10+c79e5e2

$ oc get co | grep -v '.True.*False.*False'
```


## Configure the OCP cluster after installation

### Disable the default OperatorHub sources

```bash
oc patch OperatorHub cluster --type json \
    -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
```

### Enables auto-completion
```bash
sudo oc completion bash >> /etc/bash_completion.d/oc_completion
```
