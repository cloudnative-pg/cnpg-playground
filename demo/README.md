# CloudNativePG Demo: Distributed Topology

This guide provides step-by-step instructions for setting up a PostgreSQL
database across two regions in the playground, using the
[CloudNativePG distributed topology feature](https://cloudnative-pg.io/documentation/current/replica_cluster/#distributed-topology).
Object stores are employed to synchronise the primary cluster with the
secondary (Disaster Recovery) cluster through the
[Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/).

## Architecture

- **Primary PostgreSQL cluster (`pg-eu`)**: Three instances running in the
  `k8s-eu` Kubernetes cluster (one primary and two replicas).
- **Disaster Recovery (passive) PostgreSQL cluster (`pg-us`)**: Three replicas
  (one designated primary and two cascading replicas) running in the `k8s-us`
  Kubernetes cluster.

## Prerequisites

To follow this demonstration, ensure the following are installed on your system:

1. **CNPG Playground**: Refer to the [installation guide](../README.md) for
  setup instructions. If you intend to use Prometheus together with the Grafana
  dashboards, make sure that you also deploy the [monitoring](../monitoring/)
  environment.

2. **`cmctl` (cert-manager CLI)**: Required for secure communication between
  the operator and the `barman-cloud` plugin, which is used for backup and
  recovery with MinIO object stores.
  Follow the [official `cmctl` installation guide](https://cert-manager.io/docs/reference/cmctl/#installation).
  For detailed guidance, refer to the official
  [`cert-manager` installation documentation](https://cert-manager.io/docs/installation/).

## Deployment

Once the CNPG Playground is installed, deploy the PostgreSQL clusters across
the two regions using:

```bash
./demo/setup.sh
```

This process takes a few minutes to complete.
It installs the latest version of CloudNativePG, cert-manager, and the
[Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/),
followed by the deployment of the two PostgreSQL clusters.

If you prefer to deploy a version of the clusters that uses the legacy in-tree
Barman Cloud code instead of the Barman Cloud Plugin, simply run:

```sh
LEGACY=true ./demo/setup.sh
```

To deploy from the latest `main` branch of both CloudNativePG and the Barman
Cloud plugin, use:

```bash
TRUNK=true ./demo/setup.sh
```

For a detailed understanding of the deployment process, refer to the
[`setup.sh` script](setup.sh).

## Teardown

If you need to clean up or restart the demonstration, remove the created
objects using:

```bash
./demo/teardown.sh
```

This enables you to recreate the demonstration database without reinstalling
the CNPG Playground.

For a detailed understanding of the teardown process, refer to the
[`teardown.sh` script](teardown.sh).
