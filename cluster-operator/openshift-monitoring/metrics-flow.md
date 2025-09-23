
### CLI(oc adm top) Flow:


```text
Notes:
- Metrics Server → serves real-time metrics for `oc adm top pod` and `oc adm top node`
- Metrics Server: https://github.com/openshift/kubernetes-metrics-server/blob/main/README.md

 ┌───────────────────────────┐
 │       oc adm top pod      │
 └─────────────┬─────────────┘
               │
               ▼
 ┌───────────────────────────┐
 │      Kube API Server      │
 └─────────────┬─────────────┘
               │
       ┌───────┴────────┐
       │  Metrics Server│  
       └───────┬────────┘
               │ scrape_interval: 15s
               ▼
 ┌─────────────────────────────┐
 │      Kubelet/cAdvisor       │
 │ (Node-level & Pod-level)    │
 │ Collects CPU/memory metrics │
 └─────────────────────────────┘
```



### Prometheus Query Flow:

```text
Notes:
- Pod CPU/Memory metrics → collected by **kubelet/cAdvisor** on each Node
- Pod status info (phase, replicas) → collected by **kube-state-metrics**
- Node-level metrics (CPU load, disk, network) → collected by **node-exporter**
- OpenShift-specific object metrics → collected by **openshift-state-metrics**


 ┌───────────────────────────┐
 │       PromQL Query        │
 └─────────────┬─────────────┘
               │
               ▼
 ┌───────────────────────────┐
 │      Kube API Server      │
 └─────────────┬─────────────┘
               │
               ▼
 ┌───────────────────────────┐
 │      Prometheus Pod       │
 │   (prometheus-k8s-0/1)    │
 └─────────────┬─────────────┘
               │ scrape_interval: 30s
               ▼
 ┌──────────────────┬────────────────────┬──────────────────┬─────────────────────────┐
 │ kubelet/cAdvisor │ kube-state-metrics │ node-exporter    │ openshift-state-metrics │
 │  (Pod CPU/mem &  │  (K8s object       │  (Node-level     │ (OpenShift-specific     │
 │   Node summary)  │   status info)     │   metrics)       │   resource metrics)     │
 └──────────────────┴────────────────────┴──────────────────┴─────────────────────────┘
```
