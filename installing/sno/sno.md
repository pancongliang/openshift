
### Setting Environment Variables
~~~
export OCP_VERSION=4.14.20
export ARCH=x86_64
export CLUSTER_NAME="sno"
export BASE_DOMAIN="copan.com"
export SNO_IP="10.72.94.209"
export SNO_GW="10.72.94.254"
export SNO_NETMASK="255.255.255.0"
export SNO_DNS="10.74.251.171"
export SNO_DISK="/dev/sda"
export SNO_INTERFACE="ens192"

export SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"
export PULL_SECRET_PATH="$HOME/pull-secret"
export CLIENT_OS_ARCH=mac    #mac/mac-arm64/linux
~~~

### Download oc cli and install tools, and download ISO
~~~
curl -s -k https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_VERSION/openshift-client-$CLIENT_OS_ARCH.tar.gz -o oc.tar.gz

curl -s -k https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_VERSION/openshift-install-$CLIENT_OS_ARCH.tar.gz -o openshift-install-$CLIENT_OS_ARCH.tar.gz
tar zxf oc.tar.gz
tar zxvf openshift-install-$CLIENT_OS_ARCH.tar.gz
chmod +x openshift-install oc

ISO_URL=$(./openshift-install coreos print-stream-json | grep location | grep $ARCH | grep iso | cut -d\" -f4)
curl -L $ISO_URL -o rhcos-live.iso
~~~

### Prepare the install-config.yaml file
~~~
cat << EOF > install-config.yaml 
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- name: worker
  replicas: 0 
controlPlane:
  name: master
  replicas: 1 
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
  none: {}
bootstrapInPlace:
  installationDisk: $SNO_DISK
pullSecret: '$(cat $PULL_SECRET_PATH)' 
sshKey: |
  $(cat $SSH_KEY_PATH)
EOF
~~~

### Generate ignition file
~~~
mkdir ocp
cp install-config.yaml ocp
./openshift-install --dir=ocp create single-node-ignition-config
alias coreos-installer='podman run --privileged --pull always --rm -v /dev:/dev -v /run/udev:/run/udev -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release'
openshift-install --dir=ocp create single-node-ignition-config
~~~

### Embed ignition data into RHCOS ISO
~~~
coreos-installer iso ignition embed -fi ocp/bootstrap-in-place-for-live-iso.ign rhcos-live.iso
coreos-installer iso kargs modify -a "ip=$SNO_IP::$SNO_GW:$SNO_NETMASK:$CLUSTER_NAME.$BASE_DOMAIN:$SNO_INTERFACE:off:$SNO_DNS" rhcos-live.iso
~~~

### Mount the ISO boot and check the installation progress in the PC client
~~~
./openshift-install --dir=ocp wait-for install-complete
~~~

### After the second boot, correct the hostname and DNS settings.
If the provided DNS does not have reverse domain name resolution, correct the hostname and DNS settings after the second startup.
~~~
cat << EOF > /etc/dnsmasq.d/single-node.conf
address=/apps.$CLUSTER_NAME.$BASE_DOMAIN/$SNO_IP
address=/api-int.$CLUSTER_NAME.$BASE_DOMAIN/$SNO_IP
address=/api.$CLUSTER_NAME.$BASE_DOMAIN/$SNO_IP
EOF

systemctl enable dnsmasq
systemctl restart dnsmasq

cat << EOF > /etc/NetworkManager/dispatcher.d/forcedns
export IP="$SNO_IP"
export BASE_RESOLV_CONF=/run/NetworkManager/resolv.conf
if [ "$2" = "dhcp4-change" ] || [ "$2" = "dhcp6-change" ] || [ "$2" = "up" ] || [ "$2" = "connectivity-change" ]; then
    if ! grep -q "$IP" /etc/resolv.conf; then
      export TMP_FILE=$(mktemp /etc/forcedns_resolv.conf.XXXXXX)
      cp  $BASE_RESOLV_CONF $TMP_FILE
      chmod --reference=$BASE_RESOLV_CONF $TMP_FILE
      sed -i -e "s/$CLUSTER_NAME.$BASE_DOMAIN//" \
      -e "s/search /& $CLUSTER_NAME.$BASE_DOMAIN /" \
      -e "0,/nameserver/s/nameserver/& $IP\n&/" $TMP_FILE
      mv $TMP_FILE /etc/resolv.conf
    fi
fi
EOF

chmod 755 /etc/NetworkManager/dispatcher.d/forcedns
~~~

### Log in to the cluster using kubeconfig
~~~
export KUBECONFIG=ocp/auth/kubeconfig
oc get nodes
oc get co
~~~
