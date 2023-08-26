#!/bin/bash
cat << EOF > 6_manually_install_on_each_nod.sh
curl http://$BASTION_IP:8080/pre/bootstrap-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/bootstrap-installer-2.sh

curl http://$BASTION_IP:8080/pre/master01-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/master01-installer-2.sh

curl http://$BASTION_IP:8080/pre/master02-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/master02-installer-2.sh

curl http://$BASTION_IP:8080/pre/master03-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/master03-installer-2.sh

curl http://$BASTION_IP:8080/pre/worker01-installer-2.sh
curl http://$BASTION_IP:8080/pre/worker01-installer-2.sh

curl http://$BASTION_IP:8080/pre/worker02-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/worker02-installer-2.sh
EOF

cat 6_manually_install_on_each_nod.sh