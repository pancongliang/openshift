#!/bin/bash
cat << EOF > $OCP_INSTALL_DIR/bootstrap-set-ip-1.sh
nmcli con mod $NODE_NETWORK_WIRED_CONNECTION ipv4.addresses $BOOTSTRAP_IP/$NETMASK ipv4.gateway $GATEWAY_IP ipv4.dns $DNS_IP ipv4.method manual connection.autoconnect yes
sudo systemctl restart NetworkManager
EOF

cat << EOF > $OCP_INSTALL_DIR/master01-set-ip-1.sh
nmcli con mod $NODE_NETWORK_WIRED_CONNECTION ipv4.addresses $MASTER01_IP/$NETMASK ipv4.gateway $GATEWAY_IP ipv4.dns $DNS_IP ipv4.method manual connection.autoconnect yes
sudo systemctl restart NetworkManager
EOF

cat << EOF > $OCP_INSTALL_DIR/master02-set-ip-1.sh
nmcli con mod $NODE_NETWORK_WIRED_CONNECTION ipv4.addresses $MASTER02_IP/$NETMASK ipv4.gateway $GATEWAY_IP ipv4.dns $DNS_IP ipv4.method manual connection.autoconnect yes
sudo systemctl restart NetworkManager
EOF

cat << EOF > $OCP_INSTALL_DIR/master03-set-ip-1.sh
nmcli con mod $NODE_NETWORK_WIRED_CONNECTION ipv4.addresses $MASTER03_IP/$NETMASK ipv4.gateway $GATEWAY_IP ipv4.dns $DNS_IP ipv4.method manual connection.autoconnect yes
sudo systemctl restart NetworkManager
EOF

cat << EOF > $OCP_INSTALL_DIR/worker01-set-ip-1.sh
nmcli con mod $NODE_NETWORK_WIRED_CONNECTION ipv4.addresses $WORKER01_IP/$NETMASK ipv4.gateway $GATEWAY_IP ipv4.dns $DNS_IP ipv4.method manual connection.autoconnect yes
sudo systemctl restart NetworkManager
EOF

cat << EOF > $OCP_INSTALL_DIR/worker02-set-ip-1.sh
nmcli con mod $NODE_NETWORK_WIRED_CONNECTION ipv4.addresses $WORKER02_IP/$NETMASK ipv4.gateway $GATEWAY_IP ipv4.dns $DNS_IP ipv4.method manual connection.autoconnect yes
sudo systemctl restart NetworkManager
EOF

cat << EOF > $OCP_INSTALL_DIR/bootstrap-installer-2.sh
sudo coreos-installer install --copy-network --ignition-url=http://$BASTION_IP:8080/pre/bootstrapbk.ign /dev/$NODE_DISK_PARTITION --insecure-ignition
EOF

cat << EOF > $OCP_INSTALL_DIR/master01-installer-2.sh
sudo coreos-installer install --copy-network --ignition-url=http://$BASTION_IP:8080/pre/master01.ign /dev/$NODE_DISK_PARTITION --insecure-ignition
EOF

cat << EOF > $OCP_INSTALL_DIR/master02-installer-2.sh
sudo coreos-installer install --copy-network --ignition-url=http://$BASTION_IP:8080/pre/master02.ign /dev/$NODE_DISK_PARTITION --insecure-ignition
EOF

cat << EOF > $OCP_INSTALL_DIR/master03-installer-2.sh
sudo coreos-installer install --copy-network --ignition-url=http://$BASTION_IP:8080/pre/master03.ign /dev/$NODE_DISK_PARTITION --insecure-ignition
EOF

cat << EOF > $OCP_INSTALL_DIR/worker01-installer-2.sh
sudo coreos-installer install --copy-network --ignition-url=http://$BASTION_IP:8080/pre/worker01.ign /dev/$NODE_DISK_PARTITION --insecure-ignition
EOF

cat << EOF > $OCP_INSTALL_DIR/worker02-installer-2.sh
sudo coreos-installer install --copy-network --ignition-url=http://$BASTION_IP:8080/pre/worker02.ign /dev/$NODE_DISK_PARTITION --insecure-ignition
EOF

ls $OCP_INSTALL_DIR/ | pwd
ls $OCP_INSTALL_DIR/
