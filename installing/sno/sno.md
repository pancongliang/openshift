### Generating the installation ISO with coreos-installer

* Install podman 
  ~~~
  # RHEL:
  yum install -y podman

  # MAC
  brew install podman
  podman machine init
  podman machine start
  ~~~
  
* Setting Environment Variables
  ~~~
  curl -O https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/sno/inst-sno.sh
  vim inst-sno.sh
  ~~~

* Generating the installation ISO with coreos-installer
  ~~~
  bash inst-sno.sh

  ls rhcos-live.iso
  ~~~

### Monitoring the cluster installation using openshift-install 

* Mount the CoreOS ISO and boot

* On the client host, monitor the installation by running the following command
  ~~~
  ./openshift-install --dir=ocp wait-for install-complete
  ~~~

* The server restarts several times while deploying the control plane.


### After the second boot, correct the hostname and DNS settings.
* If the provided DNS does not have reverse domain name resolution, correct the hostname and DNS settings after the second startup.
  ~~~
  export CLUSTER_NAME="sno"
  export BASE_DOMAIN="example.com"
  export SNO_IP="10.72.94.209"
  
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

### Verification
* After the installation is complete, check the environment by running the following command:
  ~~~
  export KUBECONFIG=ocp/auth/kubeconfig
  ./oc get nodes
  ./oc get co
  ~~~
