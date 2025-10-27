# Monitoring

If you want your clusters to be monitored by the [CloudNativePG Grafana Dashboard](https://github.com/cloudnative-pg/grafana-dashboards)
you can add the [Prometheus](https://github.com/prometheus-operator/prometheus-operator) & [Grafana](https://github.com/grafana/grafana-operator) operators and the dashboard by running the [setup.sh](./setup.sh).

## Setup
```bash
# Monitoring setup for the learning environment you setup earlier, by default two-regions (eu, us)
./setup.sh
```

You can easily customize this by providing your own list of region names as
arguments.

```bash
# Monitoring setup for custom environment with 'it' and 'de' regions, simulating Italy and Germany
./setup.sh it de

# Monitoring setup for a single-region environment
./setup.sh local
```

## Accessing the dashboard
After you run the [setup.sh](./setup.sh) you can access the dashboard by forwarding the Grafana port.
You will find the concrete commands in the [setup.sh](./setup.sh) output, e.g.
```bash
# Forwarding the Grafana port for the default two-region environment (eu, us)
kubectl port-forward service/grafana-service 3000:3000 -n grafana --context kind-k8s-eu
kubectl port-forward service/grafana-service 3001:3000 -n grafana --context kind-k8s-us
```
You can then connect to the Grafana GUI using the forwarded port, e.g., http://localhost:3000.
The default password for the user `admin` is `admin`. You will be prompted to change the password on the first login.

Find the dashboard under `Home > Dashboards > grafana > CloudNativePG`

![dashboard](image.png)

## PodMonitor
In order to have Prometheus scrape your Pod Metrics you have to create a `PodMonitor` as described in the [documentation](https://cloudnative-pg.io/documentation/current/monitoring/#creating-a-podmonitor)