#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <HOSTNAME>"
  exit 1
fi

HOSTNAME=$1

ssh -i "$HOME/id_rsa" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i '$HOME/id_rsa' -A -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -W %h:%p core@$(oc get service -n openshift-ssh-bastion ssh-bastion -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')" core@$HOSTNAME 2>/dev/null
