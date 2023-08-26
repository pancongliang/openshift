#!/bin/bash
cat << EOF > 6_manually_install_on_each_nod.sh
curl http://$BASTION_IP:8080/pre/bootstrap-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/bootstrap-install-2.sh

curl http://$BASTION_IP:8080/pre/master01-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/master01-install-2.sh

curl http://$BASTION_IP:8080/pre/master02-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/master02-install-2.sh

curl http://$BASTION_IP:8080/pre/master03-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/master03-install-2.sh

curl http://$BASTION_IP:8080/pre/worker01-install-2.sh
curl http://$BASTION_IP:8080/pre/worker01-install-2.sh

curl http://$BASTION_IP:8080/pre/worker02-set-ip-1.sh
curl http://$BASTION_IP:8080/pre/worker02-install-2.sh
EOF

cat 6_manually_install_on_each_nod.sh
