## 1. Change the certificate expiration time before the master node
~~~
[root@bastion ~]# echo -e "NAMESPACE\tNAME\tEXPIRY" && oc get secrets -A -o go-template='{{range .items}}{{if eq .type "kubernetes.io/tls"}}{{.metadata.namespace}}{{" "}}{{.metadata.name}}{{" "}}{{index .data "tls.crt"}}{{"\n"}}{{end}}{{end}}' | while read namespace name cert; do echo -en "$namespace\t$name\t"; echo $cert | base64 -d | openssl x509 -noout -enddate; done | column -t
NAMESPACE       NAME    EXPIRY
openshift-apiserver-operator                      openshift-apiserver-operator-serving-cert           notAfter=Mar  28  08:35:37  2025  GMT
openshift-apiserver                               etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-apiserver                               serving-cert                                        notAfter=Mar  28  08:35:39  2025  GMT
openshift-authentication-operator                 serving-cert                                        notAfter=Mar  28  08:35:39  2025  GMT
openshift-authentication                          v4-0-config-system-serving-cert                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-cloud-credential-operator               cloud-credential-operator-serving-cert              notAfter=Mar  28  08:35:43  2025  GMT
openshift-cluster-machine-approver                machine-approver-tls                                notAfter=Mar  28  08:35:49  2025  GMT
openshift-cluster-node-tuning-operator            node-tuning-operator-tls                            notAfter=Mar  28  08:35:37  2025  GMT
openshift-cluster-samples-operator                samples-operator-tls                                notAfter=Mar  28  09:57:51  2025  GMT
openshift-cluster-storage-operator                cluster-storage-operator-serving-cert               notAfter=Mar  28  08:35:44  2025  GMT
openshift-cluster-storage-operator                csi-snapshot-webhook-secret                         notAfter=Mar  28  08:35:42  2025  GMT
openshift-cluster-storage-operator                serving-cert                                        notAfter=Mar  28  08:35:50  2025  GMT
openshift-cluster-version                         cluster-version-operator-serving-cert               notAfter=Mar  28  08:35:38  2025  GMT
openshift-config-managed                          kube-controller-manager-client-cert-key             notAfter=Apr  28  08:35:31  2023  GMT
openshift-config-managed                          kube-scheduler-client-cert-key                      notAfter=Apr  28  08:35:41  2023  GMT
openshift-config-operator                         config-operator-serving-cert                        notAfter=Mar  28  08:35:50  2025  GMT
openshift-config                                  etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-config                                  etcd-metric-client                                  notAfter=Mar  26  08:19:25  2033  GMT
openshift-config                                  etcd-metric-signer                                  notAfter=Mar  26  08:19:25  2033  GMT
openshift-config                                  etcd-signer                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-console-operator                        serving-cert                                        notAfter=Mar  28  10:00:31  2025  GMT
openshift-console                                 console-serving-cert                                notAfter=Mar  28  10:00:39  2025  GMT
openshift-controller-manager-operator             openshift-controller-manager-operator-serving-cert  notAfter=Mar  28  08:35:48  2025  GMT
openshift-controller-manager                      serving-cert                                        notAfter=Mar  28  08:35:41  2025  GMT
openshift-dns-operator                            metrics-tls                                         notAfter=Mar  28  08:35:44  2025  GMT
openshift-dns                                     dns-default-metrics-tls                             notAfter=Mar  28  08:36:28  2025  GMT
openshift-etcd-operator                           etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-etcd-operator                           etcd-operator-serving-cert                          notAfter=Mar  28  08:35:48  2025  GMT
openshift-etcd                                    etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-etcd                                    etcd-peer-master01.ocp4.example.com                 notAfter=Mar  28  09:55:31  2026  GMT
openshift-etcd                                    etcd-peer-master02.ocp4.example.com                 notAfter=Mar  28  08:35:32  2026  GMT
openshift-etcd                                    etcd-peer-master03.ocp4.example.com                 notAfter=Mar  28  08:35:33  2026  GMT
openshift-etcd                                    etcd-serving-master01.ocp4.example.com              notAfter=Mar  28  09:55:31  2026  GMT
openshift-etcd                                    etcd-serving-master02.ocp4.example.com              notAfter=Mar  28  08:35:31  2026  GMT
openshift-etcd                                    etcd-serving-master03.ocp4.example.com              notAfter=Mar  28  08:35:33  2026  GMT
openshift-etcd                                    etcd-serving-metrics-master01.ocp4.example.com      notAfter=Mar  28  09:55:30  2026  GMT
openshift-etcd                                    etcd-serving-metrics-master02.ocp4.example.com      notAfter=Mar  28  08:35:31  2026  GMT
openshift-etcd                                    etcd-serving-metrics-master03.ocp4.example.com      notAfter=Mar  28  08:35:33  2026  GMT
openshift-etcd                                    serving-cert                                        notAfter=Mar  28  08:35:50  2025  GMT
openshift-image-registry                          image-registry-operator-tls                         notAfter=Mar  28  08:35:40  2025  GMT
openshift-image-registry                          image-registry-tls                                  notAfter=Mar  28  10:17:55  2025  GMT
openshift-ingress-operator                        metrics-tls                                         notAfter=Mar  28  08:35:49  2025  GMT
openshift-ingress-operator                        router-ca                                           notAfter=Mar  28  08:36:40  2025  GMT
openshift-ingress                                 router-certs-default                                notAfter=Mar  28  08:36:41  2025  GMT
openshift-ingress                                 router-metrics-certs-default                        notAfter=Mar  28  08:36:40  2025  GMT
openshift-insights                                openshift-insights-serving-cert                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-apiserver-operator                 aggregator-client-signer                            notAfter=Apr  29  02:09:16  2023  GMT
openshift-kube-apiserver-operator                 kube-apiserver-operator-serving-cert                notAfter=Mar  28  08:35:41  2025  GMT
openshift-kube-apiserver-operator                 kube-apiserver-to-kubelet-signer                    notAfter=Mar  28  06:57:13  2024  GMT
openshift-kube-apiserver-operator                 kube-control-plane-signer                           notAfter=Mar  28  06:57:12  2024  GMT
openshift-kube-apiserver-operator                 loadbalancer-serving-signer                         notAfter=Mar  26  06:57:09  2033  GMT
openshift-kube-apiserver-operator                 localhost-recovery-serving-signer                   notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver-operator                 localhost-serving-signer                            notAfter=Mar  26  06:57:09  2033  GMT
openshift-kube-apiserver-operator                 node-system-admin-client                            notAfter=Jul  27  08:35:37  2023  GMT
openshift-kube-apiserver-operator                 node-system-admin-signer                            notAfter=Mar  28  08:35:25  2024  GMT
openshift-kube-apiserver-operator                 service-network-serving-signer                      notAfter=Mar  26  06:57:09  2033  GMT
openshift-kube-apiserver                          aggregator-client                                   notAfter=Apr  29  02:09:16  2023  GMT
openshift-kube-apiserver                          check-endpoints-client-cert-key                     notAfter=Apr  28  08:35:44  2023  GMT
openshift-kube-apiserver                          control-plane-node-admin-client-cert-key            notAfter=Apr  28  08:35:45  2023  GMT
openshift-kube-apiserver                          etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-10                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-11                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-12                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-15                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-16                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-17                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-18                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-19                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-8                                       notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-9                                       notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          external-loadbalancer-serving-certkey               notAfter=Apr  28  08:35:34  2023  GMT
openshift-kube-apiserver                          internal-loadbalancer-serving-certkey               notAfter=Apr  28  08:35:47  2023  GMT
openshift-kube-apiserver                          kubelet-client                                      notAfter=Apr  28  08:35:34  2023  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey                  notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-10               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-11               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-12               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-15               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-16               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-17               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-18               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-19               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-8                notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-9                notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-serving-cert-certkey                      notAfter=Apr  28  08:35:33  2023  GMT
openshift-kube-apiserver                          service-network-serving-certkey                     notAfter=Apr  28  08:35:33  2023  GMT
openshift-kube-controller-manager-operator        csr-signer                                          notAfter=Apr  29  02:29:15  2023  GMT
openshift-kube-controller-manager-operator        csr-signer-signer                                   notAfter=May  29  02:09:12  2023  GMT
openshift-kube-controller-manager-operator        kube-controller-manager-operator-serving-cert       notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-controller-manager                 csr-signer                                          notAfter=Apr  29  02:29:15  2023  GMT
openshift-kube-controller-manager                 kube-controller-manager-client-cert-key             notAfter=Apr  28  08:35:31  2023  GMT
openshift-kube-controller-manager                 serving-cert                                        notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-10                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-11                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-12                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-13                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-8                                      notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-9                                      notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-scheduler-operator                 kube-scheduler-operator-serving-cert                notAfter=Mar  28  08:35:44  2025  GMT
openshift-kube-scheduler                          kube-scheduler-client-cert-key                      notAfter=Apr  28  08:35:41  2023  GMT
openshift-kube-scheduler                          serving-cert                                        notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-10                                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-11                                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-12                                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-8                                      notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-9                                      notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-storage-version-migrator-operator  serving-cert                                        notAfter=Mar  28  08:35:45  2025  GMT
openshift-machine-api                             cluster-autoscaler-operator-cert                    notAfter=Mar  28  08:35:46  2025  GMT
openshift-machine-api                             cluster-baremetal-operator-tls                      notAfter=Mar  28  08:35:37  2025  GMT
openshift-machine-api                             cluster-baremetal-webhook-server-cert               notAfter=Mar  28  08:35:46  2025  GMT
openshift-machine-api                             machine-api-controllers-tls                         notAfter=Mar  28  08:35:46  2025  GMT
openshift-machine-api                             machine-api-operator-tls                            notAfter=Mar  28  08:35:39  2025  GMT
openshift-machine-api                             machine-api-operator-webhook-cert                   notAfter=Mar  28  08:35:37  2025  GMT
openshift-machine-config-operator                 proxy-tls                                           notAfter=Mar  28  08:35:48  2025  GMT
openshift-marketplace                             marketplace-operator-metrics                        notAfter=Mar  28  08:35:37  2025  GMT
openshift-monitoring                              alertmanager-main-tls                               notAfter=Mar  28  10:11:16  2025  GMT
openshift-monitoring                              cluster-monitoring-operator-tls                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-monitoring                              grafana-tls                                         notAfter=Mar  28  10:11:17  2025  GMT
openshift-monitoring                              kube-state-metrics-tls                              notAfter=Mar  28  08:36:05  2025  GMT
openshift-monitoring                              node-exporter-tls                                   notAfter=Mar  28  08:36:05  2025  GMT
openshift-monitoring                              openshift-state-metrics-tls                         notAfter=Mar  28  08:36:05  2025  GMT
openshift-monitoring                              prometheus-adapter-tls                              notAfter=Mar  28  08:36:05  2025  GMT
openshift-monitoring                              prometheus-k8s-thanos-sidecar-tls                   notAfter=Mar  28  10:11:20  2025  GMT
openshift-monitoring                              prometheus-k8s-tls                                  notAfter=Mar  28  10:11:20  2025  GMT
openshift-monitoring                              prometheus-operator-tls                             notAfter=Mar  28  08:35:51  2025  GMT
openshift-monitoring                              thanos-querier-tls                                  notAfter=Mar  28  08:36:05  2025  GMT
openshift-multus                                  metrics-daemon-secret                               notAfter=Mar  28  08:35:47  2025  GMT
openshift-multus                                  multus-admission-controller-secret                  notAfter=Mar  28  08:35:44  2025  GMT
openshift-oauth-apiserver                         etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-oauth-apiserver                         serving-cert                                        notAfter=Mar  28  08:35:39  2025  GMT
openshift-operator-lifecycle-manager              catalog-operator-serving-cert                       notAfter=Mar  28  08:35:37  2025  GMT
openshift-operator-lifecycle-manager              olm-operator-serving-cert                           notAfter=Mar  28  08:35:46  2025  GMT
openshift-operator-lifecycle-manager              packageserver-service-cert                          notAfter=Mar  27  08:36:17  2025  GMT
openshift-operator-lifecycle-manager              pprof-cert                                          notAfter=Mar  31  04:00:04  2023  GMT
openshift-sdn                                     sdn-controller-metrics-certs                        notAfter=Mar  28  08:35:47  2025  GMT
openshift-sdn                                     sdn-metrics-certs                                   notAfter=Mar  28  08:35:42  2025  GMT
openshift-service-ca-operator                     serving-cert                                        notAfter=Mar  28  08:35:41  2025  GMT
openshift-service-ca                              signing-key                                         notAfter=May  27  08:35:28  2025  GMT
~~~

## 2.Change the master node time to two days before the etcd-peer-<master··> certificate is about to expire. During the waiting process, it was found that all certificates of ocp were gradually updated,
~~~
[root@bastion ~]# ssh core@master<01~03>.ocp4.example.com "sudo date -s 2026/03/26" 
[root@bastion ~]# ssh core@master<-1~03>.ocp4.example.com "sudo date -s 2026/03/26"

- because the route ca certificate and node-kubeconfig certificate have expired, it is impossible to log in to the cluster, so you need to copy the kubeconfig generated in the ocp installation directory to the master node and log in to the cluster.
[root@bastion ~]# oc login -u admin https://api.ocp4.example.com:6443
The server is using an invalid certificate: x509: certificate has expired or is not yet valid: current time 2023-03-31T03:17:20Z is before 2026-03-26T00:00:09Z
[root@master01 ~]# oc login -u admin https://api.ocp4.example.com:6443
Unable to connect to the server: EOF

[root@master01 ~]# export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
[root@master01 ~]# oc get node
error: You must be logged in to the server (Unauthorized)

[root@master01 ~]# export KUBECONFIG=/home/core/kubeconfig 

[root@master01 ~]# oc get no
NAME                        STATUS     ROLES                AGE      VERSION
master01.ocp4.example.com   NotReady   master               2y362d   v1.23.5+3afdacb
master02.ocp4.example.com   NotReady   master               2y362d   v1.23.5+3afdacb
master03.ocp4.example.com   NotReady   master               2y362d   v1.23.5+3afdacb
worker01.ocp4.example.com   NotReady   worker               2y362d   v1.23.5+3afdacb
worker02.ocp4.example.com   NotReady   worker               2y362d   v1.23.5+3afdacb
worker03.ocp4.example.com   NotReady   worker,worker-rhel   2y362d   v1.23.12+a57ef08

- Restart the kubelet service on all nodes
[root@master01 ~]# oc get csr | grep Pending
···
[root@master01 ~]# oc get csr -o name | xargs oc adm certificate approve
···
[root@master01 ~]# oc get node
NAME                        STATUS     ROLES                AGE      VERSION
master01.ocp4.example.com   Ready      master               2y362d   v1.23.5+3afdacb
master02.ocp4.example.com   Ready      master               2y362d   v1.23.5+3afdacb
master03.ocp4.example.com   Ready      master               2y362d   v1.23.5+3afdacb
worker01.ocp4.example.com   Ready      worker               2y362d   v1.23.5+3afdacb
worker02.ocp4.example.com   Ready      worker               2y362d   v1.23.5+3afdacb
worker03.ocp4.example.com   Ready      worker,worker-rhel   2y362d   v1.23.12+a57ef08

[root@master01 ~]# cat /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig | grep client-certificate-data | cut -f2 -d : | tr -d ' ' | base64 -d | openssl x509 -text -out - | grep Validity -A2
        Validity
            Not Before: Mar 26 00:00:12 2026 GMT
            Not After : Jul 24 00:00:13 2026 GMT

- At this time, the certificate will be updated gradually, but after waiting for a while, it is found that individual certificates will not be automatically updated.
(Except for router ca related certificates, because the certificate needs to be updated manually and does not support automatic update)
[root@master01 ~]#  echo -e "NAMESPACE\tNAME\tEXPIRY" && oc get secrets -A -o go-template='{{range .items}}{{if eq .type "kubernetes.io/tls"}}{{.metadata.namespace}}{{" "}}{{.metadata.name}}{{" "}}{{index .data "tls.crt"}}{{"\n"}}{{end}}{{end}}' | while read namespace name cert; do echo -en "$namespace\t$name\t"; echo $cert | base64 -d | openssl x509 -noout -enddate; done | column -t
NAMESPACE       NAME    EXPIRY
openshift-apiserver-operator                      openshift-apiserver-operator-serving-cert           notAfter=Mar  25  00:18:26  2028  GMT
openshift-apiserver                               etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-apiserver                               serving-cert                                        notAfter=Mar  25  00:18:29  2028  GMT
openshift-authentication-operator                 serving-cert                                        notAfter=Mar  25  00:18:28  2028  GMT
openshift-authentication                          v4-0-config-system-serving-cert                     notAfter=Mar  25  00:18:27  2028  GMT
openshift-cloud-credential-operator               cloud-credential-operator-serving-cert              notAfter=Mar  25  00:18:28  2028  GMT
openshift-cluster-machine-approver                machine-approver-tls                                notAfter=Mar  25  00:18:34  2028  GMT
openshift-cluster-node-tuning-operator            node-tuning-operator-tls                            notAfter=Mar  25  00:18:31  2028  GMT
openshift-cluster-samples-operator                samples-operator-tls                                notAfter=Mar  25  00:18:35  2028  GMT
openshift-cluster-storage-operator                cluster-storage-operator-serving-cert               notAfter=Mar  25  00:18:30  2028  GMT
openshift-cluster-storage-operator                csi-snapshot-webhook-secret                         notAfter=Mar  25  00:18:31  2028  GMT
openshift-cluster-storage-operator                serving-cert                                        notAfter=Mar  25  00:18:34  2028  GMT
openshift-cluster-version                         cluster-version-operator-serving-cert               notAfter=Mar  25  00:18:29  2028  GMT
openshift-config-managed                          kube-controller-manager-client-cert-key             notAfter=Apr  25  00:00:19  2026  GMT
openshift-config-managed                          kube-scheduler-client-cert-key                      notAfter=Apr  25  00:00:11  2026  GMT
openshift-config-operator                         config-operator-serving-cert                        notAfter=Mar  25  00:18:29  2028  GMT
openshift-config                                  etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-config                                  etcd-metric-client                                  notAfter=Mar  26  08:19:25  2033  GMT
openshift-config                                  etcd-metric-signer                                  notAfter=Mar  26  08:19:25  2033  GMT
openshift-config                                  etcd-signer                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-console-operator                        serving-cert                                        notAfter=Mar  25  00:18:31  2028  GMT
openshift-console                                 console-serving-cert                                notAfter=Mar  25  00:18:33  2028  GMT
openshift-controller-manager-operator             openshift-controller-manager-operator-serving-cert  notAfter=Mar  25  00:18:30  2028  GMT
openshift-controller-manager                      serving-cert                                        notAfter=Mar  25  00:18:27  2028  GMT
openshift-dns-operator                            metrics-tls                                         notAfter=Mar  25  00:18:29  2028  GMT
openshift-dns                                     dns-default-metrics-tls                             notAfter=Mar  25  00:18:27  2028  GMT
openshift-etcd-operator                           etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-etcd-operator                           etcd-operator-serving-cert                          notAfter=Mar  25  00:18:32  2028  GMT
openshift-etcd                                    etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-etcd                                    etcd-peer-master01.ocp4.example.com                 notAfter=Mar  25  00:18:46  2029  GMT
openshift-etcd                                    etcd-peer-master02.ocp4.example.com                 notAfter=Mar  25  00:18:48  2029  GMT
openshift-etcd                                    etcd-peer-master03.ocp4.example.com                 notAfter=Mar  25  00:18:50  2029  GMT
openshift-etcd                                    etcd-serving-master01.ocp4.example.com              notAfter=Mar  25  00:18:46  2029  GMT
openshift-etcd                                    etcd-serving-master02.ocp4.example.com              notAfter=Mar  25  00:18:48  2029  GMT
openshift-etcd                                    etcd-serving-master03.ocp4.example.com              notAfter=Mar  25  00:18:50  2029  GMT
openshift-etcd                                    etcd-serving-metrics-master01.ocp4.example.com      notAfter=Mar  25  00:18:47  2029  GMT
openshift-etcd                                    etcd-serving-metrics-master02.ocp4.example.com      notAfter=Mar  25  00:18:49  2029  GMT
openshift-etcd                                    etcd-serving-metrics-master03.ocp4.example.com      notAfter=Mar  25  00:18:50  2029  GMT
openshift-etcd                                    serving-cert                                        notAfter=Mar  25  00:18:27  2028  GMT
openshift-image-registry                          image-registry-operator-tls                         notAfter=Mar  25  00:18:32  2028  GMT
openshift-image-registry                          image-registry-tls                                  notAfter=Mar  25  00:18:30  2028  GMT
openshift-ingress-operator                        metrics-tls                                         notAfter=Mar  25  00:18:29  2028  GMT
openshift-ingress-operator                        router-ca                                           notAfter=Mar  28  08:36:40  2025  GMT
openshift-ingress                                 router-certs-default                                notAfter=Mar  28  08:36:41  2025  GMT
openshift-ingress                                 router-metrics-certs-default                        notAfter=Mar  25  00:18:34  2028  GMT
openshift-insights                                openshift-insights-serving-cert                     notAfter=Mar  25  00:18:30  2028  GMT
openshift-kube-apiserver-operator                 aggregator-client-signer                            notAfter=Apr  25  00:00:07  2026  GMT
openshift-kube-apiserver-operator                 kube-apiserver-operator-serving-cert                notAfter=Mar  25  00:18:31  2028  GMT
openshift-kube-apiserver-operator                 kube-apiserver-to-kubelet-signer                    notAfter=Mar  26  00:00:11  2027  GMT
openshift-kube-apiserver-operator                 kube-control-plane-signer                           notAfter=May  25  00:00:11  2026  GMT
openshift-kube-apiserver-operator                 loadbalancer-serving-signer                         notAfter=Mar  26  06:57:09  2033  GMT
openshift-kube-apiserver-operator                 localhost-recovery-serving-signer                   notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver-operator                 localhost-serving-signer                            notAfter=Mar  26  06:57:09  2033  GMT
openshift-kube-apiserver-operator                 node-system-admin-client                            notAfter=Jul  24  00:00:13  2026  GMT
openshift-kube-apiserver-operator                 node-system-admin-signer                            notAfter=Mar  26  00:00:08  2027  GMT
openshift-kube-apiserver-operator                 service-network-serving-signer                      notAfter=Mar  26  06:57:09  2033  GMT
openshift-kube-apiserver                          aggregator-client                                   notAfter=Apr  25  00:00:09  2026  GMT
openshift-kube-apiserver                          check-endpoints-client-cert-key                     notAfter=Apr  25  00:00:15  2026  GMT
openshift-kube-apiserver                          control-plane-node-admin-client-cert-key            notAfter=Apr  25  00:00:10  2026  GMT
openshift-kube-apiserver                          etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-10                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-11                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-12                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-15                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-16                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-17                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-18                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-19                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-20                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-21                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-22                                      notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-8                                       notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          etcd-client-9                                       notAfter=Mar  26  08:19:24  2033  GMT
openshift-kube-apiserver                          external-loadbalancer-serving-certkey               notAfter=Apr  25  00:00:10  2026  GMT
openshift-kube-apiserver                          internal-loadbalancer-serving-certkey               notAfter=Apr  25  00:00:10  2026  GMT
openshift-kube-apiserver                          kubelet-client                                      notAfter=Apr  25  00:00:18  2026  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey                  notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-10               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-11               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-12               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-15               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-16               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-17               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-18               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-19               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-20               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-21               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-22               notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-8                notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-recovery-serving-certkey-9                notAfter=Mar  26  08:35:27  2033  GMT
openshift-kube-apiserver                          localhost-serving-cert-certkey                      notAfter=Apr  25  00:00:11  2026  GMT
openshift-kube-apiserver                          service-network-serving-certkey                     notAfter=Apr  25  00:00:10  2026  GMT
openshift-kube-controller-manager-operator        csr-signer                                          notAfter=Apr  25  00:00:07  2026  GMT
openshift-kube-controller-manager-operator        csr-signer-signer                                   notAfter=May  25  00:00:04  2026  GMT
openshift-kube-controller-manager-operator        kube-controller-manager-operator-serving-cert       notAfter=Mar  25  00:18:32  2028  GMT
openshift-kube-controller-manager                 csr-signer                                          notAfter=Apr  25  00:00:07  2026  GMT
openshift-kube-controller-manager                 kube-controller-manager-client-cert-key             notAfter=Apr  25  00:00:19  2026  GMT
openshift-kube-controller-manager                 serving-cert                                        notAfter=Mar  25  00:18:28  2028  GMT
openshift-kube-controller-manager                 serving-cert-10                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-11                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-12                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-13                                     notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-14                                     notAfter=Mar  25  00:18:28  2028  GMT
openshift-kube-controller-manager                 serving-cert-15                                     notAfter=Mar  25  00:18:28  2028  GMT
openshift-kube-controller-manager                 serving-cert-8                                      notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-controller-manager                 serving-cert-9                                      notAfter=Mar  28  08:35:42  2025  GMT
openshift-kube-scheduler-operator                 kube-scheduler-operator-serving-cert                notAfter=Mar  25  00:18:29  2028  GMT
openshift-kube-scheduler                          kube-scheduler-client-cert-key                      notAfter=Apr  25  00:00:11  2026  GMT
openshift-kube-scheduler                          serving-cert                                        notAfter=Mar  25  00:18:31  2028  GMT
openshift-kube-scheduler                          serving-cert-10                                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-11                                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-12                                     notAfter=Mar  28  08:35:37  2025  GMT
openshift-kube-scheduler                          serving-cert-13                                     notAfter=Mar  25  00:18:31  2028  GMT
openshift-kube-scheduler                          serving-cert-14                                     notAfter=Mar  25  00:18:31  2028  GMT
openshift-kube-storage-version-migrator-operator  serving-cert                                        notAfter=Mar  25  00:18:28  2028  GMT
openshift-machine-api                             cluster-autoscaler-operator-cert                    notAfter=Mar  25  00:18:36  2028  GMT
openshift-machine-api                             cluster-baremetal-operator-tls                      notAfter=Mar  25  00:18:36  2028  GMT
openshift-machine-api                             cluster-baremetal-webhook-server-cert               notAfter=Mar  25  00:18:28  2028  GMT
openshift-machine-api                             machine-api-controllers-tls                         notAfter=Mar  25  00:18:31  2028  GMT
openshift-machine-api                             machine-api-operator-tls                            notAfter=Mar  25  00:18:30  2028  GMT
openshift-machine-api                             machine-api-operator-webhook-cert                   notAfter=Mar  25  00:18:32  2028  GMT
openshift-machine-config-operator                 proxy-tls                                           notAfter=Mar  25  00:18:34  2028  GMT
openshift-marketplace                             marketplace-operator-metrics                        notAfter=Mar  25  00:18:28  2028  GMT
openshift-monitoring                              alertmanager-main-tls                               notAfter=Mar  25  00:18:30  2028  GMT
openshift-monitoring                              cluster-monitoring-operator-tls                     notAfter=Mar  25  00:18:35  2028  GMT
openshift-monitoring                              grafana-tls                                         notAfter=Mar  25  00:18:28  2028  GMT
openshift-monitoring                              kube-state-metrics-tls                              notAfter=Mar  25  00:18:29  2028  GMT
openshift-monitoring                              node-exporter-tls                                   notAfter=Mar  25  00:18:34  2028  GMT
openshift-monitoring                              openshift-state-metrics-tls                         notAfter=Mar  25  00:18:30  2028  GMT
openshift-monitoring                              prometheus-adapter-tls                              notAfter=Mar  25  00:18:29  2028  GMT
openshift-monitoring                              prometheus-k8s-thanos-sidecar-tls                   notAfter=Mar  25  00:18:27  2028  GMT
openshift-monitoring                              prometheus-k8s-tls                                  notAfter=Mar  25  00:18:30  2028  GMT
openshift-monitoring                              prometheus-operator-tls                             notAfter=Mar  25  00:18:33  2028  GMT
openshift-monitoring                              thanos-querier-tls                                  notAfter=Mar  25  00:18:33  2028  GMT
openshift-multus                                  metrics-daemon-secret                               notAfter=Mar  25  00:18:28  2028  GMT
openshift-multus                                  multus-admission-controller-secret                  notAfter=Mar  25  00:18:32  2028  GMT
openshift-oauth-apiserver                         etcd-client                                         notAfter=Mar  26  08:19:24  2033  GMT
openshift-oauth-apiserver                         serving-cert                                        notAfter=Mar  25  00:18:28  2028  GMT
openshift-operator-lifecycle-manager              catalog-operator-serving-cert                       notAfter=Mar  25  00:18:28  2028  GMT
openshift-operator-lifecycle-manager              olm-operator-serving-cert                           notAfter=Mar  25  00:18:36  2028  GMT
openshift-operator-lifecycle-manager              packageserver-service-cert                          notAfter=Mar  24  00:17:02  2028  GMT
openshift-operator-lifecycle-manager              pprof-cert                                          notAfter=Mar  26  01:24:39  2026  GMT
openshift-sdn                                     sdn-controller-metrics-certs                        notAfter=Mar  25  00:18:33  2028  GMT
openshift-sdn                                     sdn-metrics-certs                                   notAfter=Mar  25  00:18:27  2028  GMT
openshift-service-ca-operator                     serving-cert                                        notAfter=Mar  25  00:18:36  2028  GMT
openshift-service-ca                              signing-key                                         notAfter=May  24  00:18:44  2028  GMT

- At this time, many cluster operators have errors, and many pods cannot be started, and even the apiserver and etcd pods of individual nodes are not normal
[root@master01 ~]# oc get co | grep -v '.True.*False.*False'
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE    MESSAGE
authentication                             4.10.20   False       False         True       2y360d   APIServicesAvailable: "oauth.openshift.io.v1" is not ready: an attempt failed with statusCode = 503, err = the server is currently unable to handle the request...
image-registry                             4.10.20   True        False         True       2y361d   ImagePrunerDegraded: Job has reached the specified backoff limit
ingress                                    4.10.20   False       True          True       73m      The "default" ingress controller reports Available=False: IngressControllerUnavailable: One or more status conditions indicate unavailable: DeploymentAvailable=False (DeploymentUnavailable: The deployment has Available status condition set to False (reason: MinimumReplicasUnavailable) with message: Deployment does not have minimum availability.)
kube-apiserver                             4.10.20   True        True          True       2y362d   StaticPodsDegraded: pod/kube-apiserver-master02.ocp4.example.com container "kube-apiserver-check-endpoints" is waiting: CrashLoopBackOff: back-off 5m0s restarting failed container=kube-apiserver-check-endpoints pod=kube-apiserver-master02.ocp4.example.com_openshift-kube-apiserver(170ecb1eee72d4e7f8a9f27b69b01541)
 
monitoring                                 4.10.20   False       True          True       64m      Rollout of the monitoring stack failed and is degraded. Please investigate the degraded status error.
 
openshift-apiserver                        4.10.20   False       False         False      90m      APIServicesAvailable: "apps.openshift.io.v1" is not ready: an attempt failed with statusCode = 503, err = the server is currently unable to handle the request...

service-ca                                 4.10.20   True        True          False      2y362d   Progressing: ...

[root@master01 ~]#  oc get po -n openshift-kube-apiserver | grep kube-apiserve
kube-apiserver-guard-master01.ocp4.example.com   1/1     Running     3          2y362d
kube-apiserver-guard-master02.ocp4.example.com   1/1     Running     1          2y362d
kube-apiserver-guard-master03.ocp4.example.com   1/1     Running     1          2y362d
kube-apiserver-master01.ocp4.example.com         5/5     Running     0          2y361d
kube-apiserver-master02.ocp4.example.com         4/5     Running     0          18s
kube-apiserver-master03.ocp4.example.com         5/5     Running     0          2y361d
~~~

## 3. After modifying the node time to the current time, execute the etcd recovery script, but the etcd/apiserver container reports an error, which makes it impossible to restore.
~~~

[root@master<01~03> ~]# sudo date -s "2023-03-31 05:47:14"
[root@worker<01~03> ~]# sudo date -s "2023-03-31 05:47:14"
    
- kube-apiserver container log
W0331 05:52:30.490909      16 clientconn.go:1331] [core] grpc: addrConn.createTransport failed to connect to {10.74.251.61:2379 10.74.251.61 <nil> 0 <nil>}. Err: connection error: desc = "transport: authentication handshake failed: x509: certificate has expired or is not yet valid: current time 2023-03-31T05:52:30Z is before 2026-03-26T00:18:45Z". Reconnecting...
E0331 05:56:10.564420       1 leaderelection.go:330] error retrieving resource lock openshift-kube-apiserver/cert-regeneration-controller-lock: Get "https://localhost:6443/api/v1/namespaces/openshift-kube-apiserver/configmaps/cert-regeneration-controller-lock?timeout=1m47s": dial tcp [::1]:6443: connect: connection refused

- etcd container log
{"level":"warn","ts":"2023-03-31T05:55:26.342Z","caller":"rafthttp/probing_status.go:68","msg":"prober detected unhealthy status","round-tripper-name":"ROUND_TRIPPER_RAFT_MESSAGE","remote-peer-id":"18176d0976f2223e","rtt":"15.701311ms","error":"x509: certificate has expired or is not yet valid: current time 2023-03-31T05:55:26Z is before 2026-03-26T00:18:47Z"}
{"level":"warn","ts":"2023-03-31T05:55:53.324Z","caller":"embed/config_logging.go:169","msg":"rejected connection","remote-addr":"10.74.253.133:38434","server-name":"","error":"remote error: tls: bad certificate"}

[root@master01 backup]# sudo -E /usr/local/bin/cluster-restore.sh /home/core/backup

[root@master01 ~]# crictl ps -a | grep kube-apiserver
b556b010c3c7a  12713350f0cb8e91b4e3b710624f17cbe547aa58abde483affb75619f56c8f87                                                         54 seconds ago     Exited    kube-apiserver   9  523bcb40364f
[root@master01 ~]# crictl logs b556b010c3c7a
W0331 06:09:36.506638      16 clientconn.go:1331] [core] grpc: addrConn.createTransport failed to connect to {10.74.251.61:2379 10.74.251.61 <nil> 0 <nil>}. Err: connection error: desc = "transport: authentication handshake failed: x509: certificate has expired or is not yet valid: current time 2023-03-31T06:09:36Z is before 2026-03-26T00:18:45Z". Reconnecting...
W0331 06:09:37.025299      16 clientconn.go:1331] [core] grpc: addrConn.createTransport failed to connect to {10.74.253.133:2379 10.74.253.133 <nil> 0 <nil>}. Err: connection error: desc = "transport: Error while dialing dial tcp 10.74.253.133:2379: connect: connection refused". Reconnecting...

[root@master01 backup]# crictl ps -a | grep etcd
1b1981574955a       d9a894cf8f2712af891b38b72885c4c9d3fd3e8185a3467a2f5e9c91554607cb                                                         10 minutes ago           Running             etcd                                          0                   e9d9ad0136e7c

[root@master01 backup]# crictl logs fca273c29698f
{"level":"warn","ts":"2023-03-31T06:16:07.931Z","caller":"embed/config_logging.go:169","msg":"rejected connection","remote-addr":"10.74.253.133:37704","server-name":"","error":"remote error: tls: bad certificate"}
{"level":"warn","ts":"2023-03-31T06:16:10.302Z","caller":"embed/config_logging.go:169","msg":"rejected connection","remote-addr":"10.74.251.61:50586","server-name":"","error":"EOF"}
~~~






