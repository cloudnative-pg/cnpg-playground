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

## PodMonitor

To enable Prometheus to scrape metrics from your PostgreSQL pods, you must
create a `PodMonitor` resource as described in the
[documentation](https://cloudnative-pg.io/documentation/current/monitoring/#creating-a-podmonitor).

