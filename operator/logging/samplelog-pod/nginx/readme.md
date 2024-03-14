### Create nginx pod using configmap and secret
~~~
oc new-project test

oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nginx/nginx-test.yaml

export ROUTE=$(oc get route nginx -n test -o jsonpath='{"http://"}{.spec.host}{"\n"}')

curl -s -u admin:password ${ROUTE}
~~~
~~~
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to Nginx!</title>
</head>
<body>
  <h1>Hello, World!</h1>
  <p>This HTML content is served by Nginx from a ConfigMap.</p>
</body>
</html>
~~~

~~~

$ oc new-project test
$ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/samplelog-pod/nginx/nginx-test.yaml
$ oc rsh nginx-6886cb4c86-z9fdt

sh-4.4$ cat /etc/nginx/.htpasswd/auth 
admin:$apr1$F7BhrRe3$/HOkMSHlIQXNBNXz5cThJ.

sh-4.4$ cat /etc/nginx/nginx.conf
events {
    worker_connections  1024;
}

http {
    server {
        listen 8080;
        server_name localhost;

        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;

            auth_basic "Restricted Access";
            auth_basic_user_file /etc/nginx/.htpasswd/auth;
        }
    }
}

sh-4.4$ cat /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to Nginx!</title>
</head>
<body>
  <h1>Hello, World!</h1>
  <p>This HTML content is served by Nginx from a ConfigMap.</p>
</body>
</html>

$ export ROUTE=$(oc get route nginx -n test -o jsonpath='{"http://"}{.spec.host}{"\n"}')
$ curl -s -u admin:password ${ROUTE}
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to Nginx!</title>
</head>
<body>
  <h1>Hello, World!</h1>
  <p>This HTML content is served by Nginx from a ConfigMap.</p>
</body>
</html>

$ oc get po -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP             NODE                        
nginx-6886cb4c86-z9fdt   1/1     Running   0          13m   10.131.1.206   worker-0.ocp4.example.com

oc get po -n openshift-ingress -o wide
NAME                             READY   STATUS    RESTARTS    AGE   IP             NODE 
router-default-7c9f575ff-6brth   1/1     Running   0           30m   10.72.94.246   worker-0.ocp4.example.com
router-default-7c9f575ff-k9b6d   1/1     Running   3           8d    10.72.94.247   worker-1.ocp4.example.com

$ ssh core@master-0.ocp4.example.com sudo shutdown -h now
$ ssh core@master-1.ocp4.example.com sudo shutdown -h now
$ ssh core@master-2.ocp4.example.com sudo shutdown -h now

$ oc get node
Unable to connect to the server: EOF

$ ssh core@worker-0.ocp4.example.com
[root@worker-0 ~]# crictl ps |grep 3413429d5b1cc
3413429d5b1cc 8d990e08937e299ce1d9e629e4df86ef824744e9c9d2057a8883553650d25ba9 27 minutes ago  Running nginx 0 1ca11b6db2d21 nginx-6886cb4c86-z9fdt
[root@worker-0 ~]# crictl exec -it 3413429d5b1cc /bin/bash
bash-4.4$ cat /etc/nginx/.htpasswd/auth
admin:$apr1$F7BhrRe3$/HOkMSHlIQXNBNXz5cThJ.

bash-4.4$ cat /etc/nginx/nginx.conf
events {
    worker_connections  1024;
}

http {
    server {
        listen 8080;
        server_name localhost;

        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;

            auth_basic "Restricted Access";
            auth_basic_user_file /etc/nginx/.htpasswd/auth;
        }
    }
}

bash-4.4$ cat /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to Nginx!</title>
</head>
<body>
  <h1>Hello, World!</h1>
  <p>This HTML content is served by Nginx from a ConfigMap.</p>
</body>
</html>

[root@bastion copan]#  curl -s -u admin:password http://nginx-copan.apps.ocp4.example.com    
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to Nginx!</title>
</head>
<body>
  <h1>Hello, World!</h1>
  <p>This HTML content is served by Nginx from a ConfigMap.</p>
</body>
</html>
