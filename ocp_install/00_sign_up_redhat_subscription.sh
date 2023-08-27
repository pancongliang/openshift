#!/bin/bash
#######################################################

echo ====== Sign up for a Red Hat Subscription ======
read -p "Please input the OpenShift Version (for example 4.5.12):" OCP_VER
read -s -p "Please input the Red Hat Subscribe UserName:" SUB_USER
echo -e "\r"
read -s -p "Please input the Red Hat Subscribe Password:" SUB_PASSWD
echo -e "\r"

subscription-manager register --force --user ${SUB_USER} --password ${SUB_PASSWD}
subscription-manager refresh
subscription-manager list --available --matches '*OpenShift Container Platform,*' | grep "Pool ID"
read -p "Please input the Pool ID you got:" POOL_ID
subscription-manager attach --pool=${POOL_ID}
