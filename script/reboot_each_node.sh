#!/bin/bash

for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "reboot node $Hostname"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo shutdown -r -t 3 &> /dev/null
done
