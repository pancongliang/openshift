#!/bin/bash

for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "restart kubelet.service $Hostname"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo systemctl restart kubelet
done
