
### 1. Configure Haproxy health monitoring logs
~~~
sed -i 's/^#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
sed -i 's/^#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf

cat <<EOF >/etc/rsyslog.d/haproxy.conf
local2.*    /var/log/haproxy.log
EOF

$ vim /etc/haproxy/haproxy.cfg
global
  log         127.0.0.1 local2
  pidfile     /var/run/haproxy.pid
  maxconn     4000
  daemon

defaults
  mode                    http
  log                     global
  option                  dontlognull
  option http-server-close
  option                  redispatch
  retries                 3
  timeout http-request    10s
  timeout queue           1m
  timeout connect         10s
  timeout client          1m
  timeout server          1m
  timeout http-keep-alive 10s
  timeout check           10s
  maxconn                 3000
···
listen default-ingress-router-health-check
  mode http
  option httpchk GET /healthz/ready
  option log-health-checks
  http-check expect status 200
  timeout check 5s 
  server worker01.ocp.example.com 10.184.134.229:1936 check inter 10s fall 2 rise 2 
  server worker02.ocp.example.com 10.184.134.54:1936 check inter 10s fall 2 rise 2
  server worker03.ocp.example.com 10.184.134.134:1936 check inter 10s fall 2 rise 2

systemctl restart rsyslog
systemctl restart haproxy
~~~

### 2. create scripts to monitor cluster status
~~~
cat health.sh
#!/bin/bash
URLS=("http://10.184.134.54:1936/healthz/ready"
      "http://10.184.134.229:1936/healthz/ready")

APPURLS=("http://hello-openshift-test.apps.ocp.example.com"
      "http://hello-openshift-test.apps.ocp.example.com"
      "http://hello-openshift-test.apps.ocp.example.com"
      "http://hello-openshift-test.apps.ocp.example.com"
      "http://hello-openshift-test.apps.ocp.example.com")

while true; do
  timestamp=$(date +"[%y/%m/%d %H:%M:%S.%3N]")
  echo "---------------------- $timestamp Monitor Health Status ----------------------"
  echo "=== Openshift Router Pods ===" 
  oc get po -o wide -n openshift-ingress
  echo
  echo "=== Router Ports ==="
  nc -zv 10.184.134.54 80 2>&1 | grep -q 'Connected' && echo "10.184.134.54:80 UP" || echo "10.184.134.54:80 DOWN"
  nc -zv 10.184.134.229 80 2>&1 | grep -q 'Connected' && echo "10.184.134.229:80 UP" || echo "10.184.134.229:80 DOWN"
  echo
  echo "=== HTTP Health Checks ==="
   for url in "${URLS[@]}"; do
    status=$(curl -o /dev/null -s -w "%{http_code}" --max-time 1 "$url")
    timestamp=$(date +"[%y/%m/%d %H:%M:%S.%3N]") 
    echo "$timestamp $url Status Code: $status"
  done
  echo
  echo "=== HAProxy 80 Port Health Checks ==="
  grep -E '(Health check|Server) .*default-ingress-router-80' /var/log/haproxy.log | tail -n 10
  echo
  echo "=== HAProxy Http Health Check Logs ==="
  grep -v Connect /var/log/haproxy.log | tail -n 10
  echo
  echo "=== APP Health Checks ==="
  for url in "${APPURLS[@]}"; do
    status=$(curl -o /dev/null -s -w "%{http_code}" --max-time 1 "$url")
    timestamp=$(date +"[%y/%m/%d %H:%M:%S.%3N]") 
    echo "$timestamp $url Status Code: $status"
  done
  echo "-------------------------------------------------------------------------------"
  echo
  sleep 0.5
done

bash monitor-ocp.sh &
~~~

