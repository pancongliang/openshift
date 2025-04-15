#!/bin/bash

start_ip=100
end_ip=220
network="10.184.134"

for ip in $(seq $start_ip $end_ip); do
  ping -c 1 -W 1 $network.$ip &> /dev/null && echo "$network.$ip is up" || echo "$network.$ip is down"
done
