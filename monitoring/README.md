# Monitoring

This directory enables monitoring of your CloudNativePG clusters using the official
[CloudNativePG Grafana Dashboard](https://github.com/cloudnative-pg/grafana-dashboards).
The included script installs both the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
and the [Grafana Operator](https://github.com/grafana/grafana-operator),
and deploys the dashboard on top of your existing playground environment.

---

## Setup

To install monitoring components for the environment you previously created (by
default consisting of two regions: `eu` and `us`), simply run:

```bash
./setup.sh
```

You may also specify one or more region names to match a customised setup:

```bash
# Monitoring setup for clusters named 'it' and 'de'
./setup.sh it de

# Monitoring setup for a single-region environment
./setup.sh local
```

The script will automatically deploy Prometheus, Grafana, and the CloudNativePG dashboard in each region provided.

---

## Accessing the Dashboard

Once installation completes, you can access Grafana via port forwarding.
The `setup.sh` script prints the exact commands needed.
For the default two-region environment, they look similar to:

```bash
kubectl port-forward service/grafana-service 3001:3000 -n grafana --context kind-k8s-eu
kubectl port-forward service/grafana-service 3002:3000 -n grafana --context kind-k8s-us
```

After forwarding the port, open your browser at:

```
http://localhost:3001
```

Log in using:

- **Username:** `admin`
- **Password:** `admin`

Grafana will prompt you to choose a new password at first login.


You can find the dashboard under `Home > Dashboards > grafana > CloudNativePG`.

![dashboard](image.png)

> **Note:** Grafana Live is disabled (`max_connections: 0`) to prevent
> WebSocket connection buildup that can exhaust kubectl port-forward
> streams and cause timeout errors. This means real-time dashboard
> streaming is unavailable, but all other Grafana features work normally
> when accessed via port-forward.

## CloudNativePG Grafana Dashboard

[CloudNativePG provides a default dashboard](https://cloudnative-pg.io/docs/devel/quickstart#grafana-dashboard) for Grafana in the dedicated [`grafana-dashboards` repository](https://github.com/cloudnative-pg/grafana-dashboards). The CNPG Playground monitoring `setup.sh` automatically installs the CNPG dashboard into grafana. You can also download the file [grafana-dashboard.json](https://github.com/cloudnative-pg/grafana-dashboards/blob/main/charts/cluster/grafana-dashboard.json) and manually import it via the GUI (menu: Dashboards > New > Import). 

### Dependencies

The CNPG Playground monitoring `setup.sh` also installs and configures the dependencies of this dashboard:

1. `node-exporter`: Node-level metrics (CPU, memory, disk, network at the host level)
2. `kube-state-metrics`: Kubernetes object metrics (pods, deployments, resource requests/limits)
3. Kubelet/cAdvisor Metrics (via `/metrics/cadvisor`): Container-level metrics (CPU, memory, network, disk I/O)
4. Canonical **Kubernetes recording rules from [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)**, which pre-compute common aggregations used by the CloudNativePG dashboard such as `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate` and `node_namespace_pod_container:container_memory_working_set_bytes` and `namespace_cpu:kube_pod_container_resource_requests:sum`

## PodMonitor

To enable Prometheus to scrape metrics from your PostgreSQL pods, you must
create a `PodMonitor` resource as described in the
[documentation](https://cloudnative-pg.io/documentation/current/monitoring/#creating-a-podmonitor).
 
 If a monitoring stack is running, then `demo/setup.sh` will automatically create PodMonitors.
