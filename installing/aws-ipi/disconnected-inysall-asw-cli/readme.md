
## Disconnected Install on AWS

### Create AWS Environment


```

### Setup Quay Mirror Registry and Mirror Release image



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

Open another terminal to the jumpbox and run:

```bash
oc edit dnses.config/cluster
```

In the editor, under `spec`, remove the `privateZone` stanza. It should look similar to this:

```yaml
oc patch dnses.config.openshift.io/cluster --type=merge --patch='{"spec": {"privateZone": null}}'

or

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
