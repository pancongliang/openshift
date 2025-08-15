
### 1. Configure Haproxy health monitoring logs
~~~
sed -i 's/^#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
sed -i 's/^#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf

cat <<EOF >/etc/rsyslog.d/haproxy.conf
local2.*    /var/log/haproxy.log
EOF

$ vim /etc/haproxy/haproxy.cfg
···
defaults
  retries                 3
  timeout check           10s
···
listen default-ingress-router-80
  bind 10.184.134.128:80
  mode tcp
  balance source
  option  log-health-checks
  option  tcp-check
  server     worker01.ocp.example.com 10.184.134.67:80 check inter 1s
  server     worker02.ocp.example.com 10.184.134.114:80 check inter 10s
  server     worker03.ocp.example.com 10.184.134.50:80 check inter 5s
  
listen default-ingress-router-443
  bind 10.184.134.128:443
  mode tcp
  balance source
  option  log-health-checks
  option  tcp-check
  server     worker01.ocp.example.com 10.184.134.67:443 check inter 1s
  server     worker02.ocp.example.com 10.184.134.114:443 check inter 10s
  server     worker03.ocp.example.com 10.184.134.50:443 check inter 5s

systemctl restart rsyslog
systemctl restart haproxy
~~~

### 2. create scripts to monitor cluster status
~~~
cat monitor-ocp.sh
#!/bin/bash

LOG_FILE="ocp_status.log"

echo "==== Monitoring started at $(date) ====" >> "$LOG_FILE"

while true; do
    TS=$(date '+%Y-%m-%d %H:%M:%S')

    echo "=== $TS Pod Status ===" >> "$LOG_FILE"
    oc get po -o wide -n openshift-ingress >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    echo "=== $TS Node Status ===" >> "$LOG_FILE"
    oc get node >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    echo "=== $TS Cluster Operator Status ===" >> "$LOG_FILE"
    oc get co >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    sleep 1
done

bash monitor-ocp.sh &
~~~

### 3. Upgrade the cluster (4.16 -> 4.17) after setting different inter values for the nodes
~~~
$ vim /etc/haproxy/haproxy.cfg
···
defaults
  retries                 3
  timeout check           10s
···
listen default-ingress-router-80
  bind 10.184.134.128:80
  mode tcp
  balance source
  option  log-health-checks
  option  tcp-check
  server     worker01.ocp.example.com 10.184.134.67:80 check inter 1s
  server     worker02.ocp.example.com 10.184.134.114:80 check inter 10s
  server     worker03.ocp.example.com 10.184.134.50:80 check inter 5s
  
listen default-ingress-router-443
  bind 10.184.134.128:443
  mode tcp
  balance source
  option  log-health-checks
  option  tcp-check
  server     worker01.ocp.example.com 10.184.134.67:443 check inter 1s
  server     worker02.ocp.example.com 10.184.134.114:443 check inter 10s
  server     worker03.ocp.example.com 10.184.134.50:443 check inter 5s

systemctl restart haproxy

$ oc get po -o wide -n openshift-ingress
NAME                              READY   STATUS    RESTARTS   AGE    IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running   0          96m    10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   1/1     Running   0          106m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-788b8cf574-zcbw8   1/1     Running   0          101m   10.184.134.50    worker03.ocp.example.com   <none>           <none>  

# upgrade cluster
~~~

### 4. During the OCP upgrade, the ingress pod restarted. Check the haproxy disconnection detection log
#### worker03 service interruption duration: 51s
~~~
$ grep -v 'Connect from' /var/log/haproxy.log | grep worker03
Aug 15 04:31:43 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:31:44 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 2ms, status: 3/3 UP.
Aug 15 04:50:49 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 04:50:50 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 04:50:54 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 04:50:55 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 04:50:59 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 04:50:59 localhost haproxy[12761]: Server default-ingress-router-80/worker03.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 04:51:00 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 04:51:00 localhost haproxy[12761]: Server default-ingress-router-443/worker03.ocp.example.com is DOWN. 2 active and 0 backup servers left. 19 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 04:51:34 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 04:51:35 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 04:51:39 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:51:39 localhost haproxy[12761]: Server default-ingress-router-80/worker03.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
Aug 15 04:51:40 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:51:40 localhost haproxy[12761]: Server default-ingress-router-443/worker03.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.

$ grep -E '=== 2025-08-15 04:50:[0-5][0-9] Pod Status ===' ocp_status.log -A5
=== 2025-08-15 04:50:03 Pod Status ===
NAME                              READY   STATUS        RESTARTS   AGE    IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running       0          99m    10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   1/1     Running       0          109m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-788b8cf574-zcbw8   1/1     Terminating   0          104m   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    0/1     Pending       0          0s     <none>           <none>                     <none>           <none>

$ grep -E '=== 2025-08-15 04:50:[0-5][0-9] Pod Status ===' ocp_status.log -A5
=== 2025-08-15 04:50:28 Pod Status ===
NAME                              READY   STATUS        RESTARTS   AGE    IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running       0          100m   10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   1/1     Running       0          110m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-788b8cf574-zcbw8   1/1     Terminating   0          105m   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    0/1     Pending       0          25s    <none>           <none>                     <none>           <none>

$ grep -E '=== 2025-08-15 04:51:[0-5][0-9] Pod Status ===' ocp_status.log -A5
=== 2025-08-15 04:51:20 Pod Status ===
NAME                              READY   STATUS        RESTARTS   AGE    IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running       0          101m   10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   1/1     Running       0          110m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-788b8cf574-zcbw8   0/1     Terminating   0          105m   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    0/1     Pending       0          77s    <none>           <none>                     <none>           <none>

=== 2025-08-15 04:51:32 Pod Status ===
NAME                              READY   STATUS    RESTARTS   AGE    IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running   0          101m   10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   1/1     Running   0          111m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    0/1     Running   0          90s    10.184.134.50    worker03.ocp.example.com   <none>           <none>

=== 2025-08-15 04:51:34 Pod Status ===
NAME                              READY   STATUS    RESTARTS   AGE    IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running   0          101m   10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   1/1     Running   0          111m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    1/1     Running   0          91s    10.184.134.50    worker03.ocp.example.com   <none>           <none>
~~~

#### worker02 service interruption duration: 60s
~~~
$ grep -v 'Connect from' /var/log/haproxy.log | grep worker02
Aug 15 04:31:46 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:31:48 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:52:49 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 04:52:56 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 04:52:59 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 04:53:06 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 04:53:09 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 04:53:09 localhost haproxy[12761]: Server default-ingress-router-443/worker02.ocp.example.com is DOWN. 2 active and 0 backup servers left. 1 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 04:53:16 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 04:53:16 localhost haproxy[12761]: Server default-ingress-router-80/worker02.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 04:53:36 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 04:53:39 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 04:53:46 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:53:46 localhost haproxy[12761]: Server default-ingress-router-80/worker02.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
Aug 15 04:53:49 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:53:49 localhost haproxy[12761]: Server default-ingress-router-443/worker02.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.

$ grep -E '=== 2025-08-15 04:52:[0-5][0-9] Pod Status ===' ocp_status.log -A5
=== 2025-08-15 04:52:03 Pod Status ===
NAME                              READY   STATUS        RESTARTS   AGE    IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running       0          101m   10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   1/1     Terminating   0          111m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp    0/1     Pending       0          0s     <none>           <none>                     <none>           <none>
router-default-97f4559c7-hl2w2    1/1     Running       0          2m     10.184.134.50    worker03.ocp.example.com   <none>           <none>

=== 2025-08-15 04:52:27 Pod Status ===
NAME                              READY   STATUS        RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running       0          102m    10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-788b8cf574-dqssp   0/1     Terminating   0          112m    10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp    0/1     Pending       0          24s     <none>           <none>                     <none>           <none>
router-default-97f4559c7-hl2w2    1/1     Running       0          2m24s   10.184.134.50    worker03.ocp.example.com   <none>           <none>

$ grep -E '=== 2025-08-15 04:53:[0-5][0-9] Pod Status ===' ocp_status.log -A5
=== 2025-08-15 04:53:29 Pod Status ===
NAME                              READY   STATUS              RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running             0          103m    10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp    0/1     ContainerCreating   0          86s     10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    1/1     Running             0          3m26s   10.184.134.50    worker03.ocp.example.com   <none>           <none>

=== 2025-08-15 04:53:32 Pod Status ===
NAME                              READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Running   0          103m    10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp    1/1     Running   0          89s     10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    1/1     Running   0          3m29s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
~~~

#### worker01 service interruption duration: 5s
~~~
$ grep -v 'Connect from' /var/log/haproxy.log | grep worker01
Aug 15 04:31:39 localhost haproxy[12706]: Health check for server default-ingress-router-80/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:31:39 localhost haproxy[12706]: Health check for server default-ingress-router-443/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:31:40 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:31:41 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:54:46 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 04:54:46 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 04:54:47 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 04:54:47 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 04:54:48 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 04:54:48 localhost haproxy[12761]: Server default-ingress-router-80/worker01.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 04:54:48 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 04:54:48 localhost haproxy[12761]: Server default-ingress-router-443/worker01.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 04:54:50 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 04:54:50 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 04:54:51 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:54:51 localhost haproxy[12761]: Server default-ingress-router-80/worker01.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
Aug 15 04:54:51 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 04:54:51 localhost haproxy[12761]: Server default-ingress-router-443/worker01.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.

$ grep -E '=== 2025-08-15 04:54:[0-5][0-9] Pod Status ===' ocp_status.log -A5
=== 2025-08-15 04:54:02 Pod Status ===
NAME                              READY   STATUS        RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   1/1     Terminating   0          103m    10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp    1/1     Running       0          119s    10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    1/1     Running       0          3m59s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb    0/1     Pending       0          1s      <none>           <none>                     <none>           <none>

=== 2025-08-15 04:54:25 Pod Status ===
NAME                              READY   STATUS        RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-788b8cf574-bk95c   0/1     Terminating   0          104m    10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp    1/1     Running       0          2m22s   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2    1/1     Running       0          4m22s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb    0/1     Pending       0          24s     <none>           <none>                     <none>           <none>

=== 2025-08-15 04:54:52 Pod Status ===
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-frpvp   1/1     Running   0          2m49s   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2   1/1     Running   0          4m49s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Running   0          51s     10.184.134.67    worker01.ocp.example.com   <none>           <none>
~~~

### 5. During the OCP upgrade, the node restarted. Check the haproxy disconnection detection log.
#### upgrade reboot: worker03
~~~
$ grep -v 'Connect from' /var/log/haproxy.log | grep worker03
Aug 15 05:07:49 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 05:07:50 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 05:07:54 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 05:07:55 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 05:07:59 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:07:59 localhost haproxy[12761]: Server default-ingress-router-80/worker03.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 05:08:00 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:08:00 localhost haproxy[12761]: Server default-ingress-router-443/worker03.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 05:11:00 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 5000ms, status: 0/2 DOWN.
Aug 15 05:11:04 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 5000ms, status: 0/2 DOWN.
Aug 15 05:11:18 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 3109ms, status: 0/2 DOWN.
Aug 15 05:11:19 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:11:49 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 05:11:53 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 05:11:54 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 05:11:54 localhost haproxy[12761]: Server default-ingress-router-80/worker03.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
Aug 15 05:11:58 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker03.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 05:11:58 localhost haproxy[12761]: Server default-ingress-router-443/worker03.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue

$ grep -E '=== 2025-08-15 05:07:[0-5][0-9] Pod Status ===' ocp_status.log -A14
=== 2025-08-15 05:07:04 Pod Status ===
NAME                             READY   STATUS        RESTARTS   AGE   IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   0/1     Pending       0          1s    <none>           <none>                     <none>           <none>
router-default-97f4559c7-frpvp   1/1     Running       0          15m   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hl2w2   1/1     Terminating   0          17m   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Running       0          13m   10.184.134.67    worker01.ocp.example.com   <none>           <none>

=== 2025-08-15 05:07:04 Node Status ===
NAME                       STATUS                     ROLES                  AGE   VERSION
master01.ocp.example.com   Ready                      control-plane,master   19d   v1.29.14+a6b193c
master02.ocp.example.com   Ready                      control-plane,master   19d   v1.29.14+a6b193c
master03.ocp.example.com   Ready                      control-plane,master   19d   v1.29.14+a6b193c
worker01.ocp.example.com   Ready                      worker                 19d   v1.29.14+a6b193c
worker02.ocp.example.com   Ready                      worker                 19d   v1.29.14+a6b193c
worker03.ocp.example.com   Ready,SchedulingDisabled   worker                 19d   v1.29.14+a6b193c

$ grep -E '=== 2025-08-15 05:11:[0-5][0-9] Pod Status ===' ocp_status.log -A14
=== 2025-08-15 05:11:50 Pod Status ===
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   0/1     Running   0          4m47s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp   1/1     Running   0          19m     10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Running   0          17m     10.184.134.67    worker01.ocp.example.com   <none>           <none>

=== 2025-08-15 05:11:51 Pod Status ===
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   1/1     Running   0          4m48s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp   1/1     Running   0          19m     10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Running   0          17m     10.184.134.67    worker01.ocp.example.com   <none>           <none>

=== 2025-08-15 05:11:51 Node Status ===
NAME                       STATUS                        ROLES                  AGE   VERSION
master01.ocp.example.com   NotReady,SchedulingDisabled   control-plane,master   19d   v1.29.14+a6b193c
master02.ocp.example.com   Ready                         control-plane,master   19d   v1.29.14+a6b193c
master03.ocp.example.com   Ready                         control-plane,master   19d   v1.29.14+a6b193c
worker01.ocp.example.com   Ready                         worker                 19d   v1.29.14+a6b193c
worker02.ocp.example.com   Ready                         worker                 19d   v1.29.14+a6b193c
worker03.ocp.example.com   Ready                         worker                 19d   v1.30.14
~~~

#### upgrade reboot: worker02
~~~
$ grep -v 'Connect from' /var/log/haproxy.log | grep worker02
Aug 15 05:12:47 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 05:12:49 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 05:12:57 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 05:12:59 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 05:13:07 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:13:07 localhost haproxy[12761]: Server default-ingress-router-80/worker02.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 05:13:09 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:13:09 localhost haproxy[12761]: Server default-ingress-router-443/worker02.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 05:15:57 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 10001ms, status: 0/2 DOWN.
Aug 15 05:15:59 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 10001ms, status: 0/2 DOWN.
Aug 15 05:16:07 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:16:09 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 1ms, status: 0/2 DOWN.
Aug 15 05:16:37 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 05:16:39 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 05:16:47 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 05:16:47 localhost haproxy[12761]: Server default-ingress-router-80/worker02.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
Aug 15 05:16:49 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker02.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 05:16:49 localhost haproxy[12761]: Server default-ingress-router-443/worker02.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.

$ grep -E '=== 2025-08-15 05:12:[0-5][0-9] Pod Status ===' ocp_status.log -A14
=== 2025-08-15 05:11:58 Pod Status ===
NAME                             READY   STATUS        RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   1/1     Running       0          4m55s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-frpvp   1/1     Terminating   0          19m     10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-hpdbt   0/1     Pending       0          1s      <none>           <none>                     <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Running       0          17m     10.184.134.67    worker01.ocp.example.com   <none>           <none>

=== 2025-08-15 05:11:58 Node Status ===
NAME                       STATUS                        ROLES                  AGE   VERSION
master01.ocp.example.com   NotReady,SchedulingDisabled   control-plane,master   19d   v1.29.14+a6b193c
master02.ocp.example.com   Ready                         control-plane,master   19d   v1.29.14+a6b193c
master03.ocp.example.com   Ready                         control-plane,master   19d   v1.29.14+a6b193c
worker01.ocp.example.com   Ready                         worker                 19d   v1.29.14+a6b193c
worker02.ocp.example.com   Ready,SchedulingDisabled      worker                 19d   v1.29.14+a6b193c
worker03.ocp.example.com   Ready                         worker                 19d   v1.30.14

$ grep -E '=== 2025-08-15 05:16:[0-5][0-9] Pod Status ===' ocp_status.log -A14
=== 2025-08-15 05:16:35 Pod Status ===
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   1/1     Running   0          9m33s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-hpdbt   0/1     Running   0          4m39s   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Running   0          22m     10.184.134.67    worker01.ocp.example.com   <none>           <none>

=== 2025-08-15 05:16:37 Pod Status ===
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   1/1     Running   0          9m34s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-hpdbt   1/1     Running   0          4m40s   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Running   0          22m     10.184.134.67    worker01.ocp.example.com   <none>           <none>

=== 2025-08-15 05:16:37 Node Status ===
NAME                       STATUS                     ROLES                  AGE   VERSION
master01.ocp.example.com   Ready                      control-plane,master   19d   v1.30.14
master02.ocp.example.com   Ready,SchedulingDisabled   control-plane,master   19d   v1.29.14+a6b193c
master03.ocp.example.com   Ready                      control-plane,master   19d   v1.29.14+a6b193c
worker01.ocp.example.com   Ready                      worker                 19d   v1.29.14+a6b193c
worker02.ocp.example.com   Ready                      worker                 19d   v1.30.14
worker03.ocp.example.com   Ready                      worker                 19d   v1.30.14
~~~

#### upgrade reboot: worker01
~~~
$ grep -v 'Connect from' /var/log/haproxy.log | grep worker01
Aug 15 05:17:26 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 05:17:26 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 2/3 UP.
Aug 15 05:17:27 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 05:17:27 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 1/3 UP.
Aug 15 05:17:28 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:17:28 localhost haproxy[12761]: Server default-ingress-router-80/worker01.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 05:17:28 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 0ms, status: 0/2 DOWN.
Aug 15 05:17:28 localhost haproxy[12761]: Server default-ingress-router-443/worker01.ocp.example.com is DOWN. 2 active and 0 backup servers left. 0 sessions active, 0 requeued, 0 remaining in queue.
Aug 15 05:20:32 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 1001ms, status: 0/2 DOWN.
Aug 15 05:20:32 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 1001ms, status: 0/2 DOWN.
Aug 15 05:20:46 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "No route to host at initial connection step of tcp-check", check duration: 984ms, status: 0/2 DOWN.
Aug 15 05:20:48 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 1001ms, status: 0/2 DOWN.
Aug 15 05:20:52 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 676ms, status: 0/2 DOWN.
Aug 15 05:20:52 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 624ms, status: 0/2 DOWN.
Aug 15 05:21:01 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 1001ms, status: 0/2 DOWN.
Aug 15 05:21:01 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 timeout, info: " at initial connection step of tcp-check", check duration: 1001ms, status: 0/2 DOWN.
Aug 15 05:21:02 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 1ms, status: 0/2 DOWN.
Aug 15 05:21:02 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com failed, reason: Layer4 connection problem, info: "Connection refused at initial connection step of tcp-check", check duration: 1ms, status: 0/2 DOWN.
Aug 15 05:21:27 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 05:21:27 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 1/2 DOWN.
Aug 15 05:21:28 localhost haproxy[12761]: Health check for server default-ingress-router-443/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 05:21:28 localhost haproxy[12761]: Server default-ingress-router-443/worker01.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
Aug 15 05:21:28 localhost haproxy[12761]: Health check for server default-ingress-router-80/worker01.ocp.example.com succeeded, reason: Layer4 check passed, check duration: 0ms, status: 3/3 UP.
Aug 15 05:21:28 localhost haproxy[12761]: Server default-ingress-router-80/worker01.ocp.example.com is UP. 3 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.

$ grep -E '=== 2025-08-15 05:16:[0-5][0-9] Pod Status ===' ocp_status.log -A14
=== 2025-08-15 05:16:41 Pod Status ===
NAME                             READY   STATUS        RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   1/1     Running       0          9m38s   10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-bsllc   0/1     Pending       0          1s      <none>           <none>                     <none>           <none>
router-default-97f4559c7-hpdbt   1/1     Running       0          4m44s   10.184.134.114   worker02.ocp.example.com   <none>           <none>
router-default-97f4559c7-ssqzb   1/1     Terminating   0          22m     10.184.134.67    worker01.ocp.example.com   <none>           <none>

=== 2025-08-15 05:16:41 Node Status ===
NAME                       STATUS                     ROLES                  AGE   VERSION
master01.ocp.example.com   Ready                      control-plane,master   19d   v1.30.14
master02.ocp.example.com   Ready,SchedulingDisabled   control-plane,master   19d   v1.29.14+a6b193c
master03.ocp.example.com   Ready                      control-plane,master   19d   v1.29.14+a6b193c
worker01.ocp.example.com   Ready,SchedulingDisabled   worker                 19d   v1.29.14+a6b193c
worker02.ocp.example.com   Ready                      worker                 19d   v1.30.14
worker03.ocp.example.com   Ready                      worker                 19d   v1.30.14

$ grep -E '=== 2025-08-15 05:20:[0-5][0-9] Pod Status ===' ocp_status.log -A14
=== 2025-08-15 05:21:27 Pod Status ===
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   1/1     Running   0          14m     10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-bsllc   0/1     Running   0          4m47s   10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-97f4559c7-hpdbt   1/1     Running   0          9m30s   10.184.134.114   worker02.ocp.example.com   <none>           <none>

=== 2025-08-15 05:21:29 Pod Status ===
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                       NOMINATED NODE   READINESS GATES
router-default-97f4559c7-8krhf   1/1     Running   0          14m     10.184.134.50    worker03.ocp.example.com   <none>           <none>
router-default-97f4559c7-bsllc   1/1     Running   0          4m49s   10.184.134.67    worker01.ocp.example.com   <none>           <none>
router-default-97f4559c7-hpdbt   1/1     Running   0          9m32s   10.184.134.114   worker02.ocp.example.com   <none>           <none>

=== 2025-08-15 05:21:29 Node Status ===
NAME                       STATUS                     ROLES                  AGE   VERSION
master01.ocp.example.com   Ready                      control-plane,master   19d   v1.30.14
master02.ocp.example.com   Ready                      control-plane,master   19d   v1.30.14
master03.ocp.example.com   Ready,SchedulingDisabled   control-plane,master   19d   v1.29.14+a6b193c
worker01.ocp.example.com   Ready                      worker                 19d   v1.30.14
worker02.ocp.example.com   Ready                      worker                 19d   v1.30.14
worker03.ocp.example.com   Ready                      worker                 19d   v1.30.14
~~~

#### Backup log
~~~
cp /var/log/haproxy.log 4.16_upgrade_haproxy.log
cp ocp_status.log 4.16_upgrade_ocp_status.log
~~~
