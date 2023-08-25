#!/bin/bash
cat << EOF > 7_manually_install_on_each_nod.sh
curl http://$BASTION_IP:8080/bootstrap-set-ip-1.sh | bash
curl http://$BASTION_IP:8080/bootstrap-installer-2.sh | bash

curl http://$BASTION_IP:8080/master01-set-ip-1.sh | bash
curl http://$BASTION_IP:8080/master01-installer-2.sh | bash

curl http://$BASTION_IP:8080/master02-set-ip-1.sh | bash
curl http://$BASTION_IP:8080/master02-installer-2.sh | bash

curl http://$BASTION_IP:8080/master03-set-ip-1.sh | bash
curl http://$BASTION_IP:8080/master03-installer-2.sh | bash

curl http://$BASTION_IP:8080/worker01-installer-2.sh | bash
curl http://$BASTION_IP:8080/worker01-installer-2.sh | bash

curl http://$BASTION_IP:8080/worker02-set-ip-1.sh | bash
curl http://$BASTION_IP:8080/worker02-installer-2.sh | bash
EOF

ls $INSTALL_DIR/
