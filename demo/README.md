# CloudNativePG Demo: Distributed Topology

This guide provides step-by-step instructions for setting up a PostgreSQL
database across one or more regions in the playground, using the
[CloudNativePG distributed topology feature](https://cloudnative-pg.io/documentation/current/replica_cluster/#distributed-topology).
Object stores are employed to synchronise the primary cluster with the
secondary (Disaster Recovery) cluster through the
[Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/).

## Architecture

The demo supports any number of regions (defaulting to `eu` and `us`).
For the default two-region setup:

- **Primary PostgreSQL cluster (`pg-eu`)**: Three instances running in the
  `k8s-eu` Kubernetes cluster (one primary and two replicas).
- **Disaster Recovery (passive) PostgreSQL cluster (`pg-us`)**: Three replicas
  (one designated primary and two cascading replicas) running in the `k8s-us`
  Kubernetes cluster.

When more than one region is used, the clusters form a circular replica chain.
Each cluster streams from its predecessor, and the primary (first region) wraps
around to the last. For example, with `eu us apj`:

| Cluster | Streams from (source) |
|---------|-----------------------|
| `pg-eu` (primary) | `pg-apj` (dormant until demotion) |
| `pg-us` | `pg-eu` |
| `pg-apj` | `pg-us` |

Normal state:

```
pg-eu (primary) ◄── pg-us ◄── pg-apj
     └──────────────────────────────┘ (wrap-around, dormant)
```

Switching over to `pg-us` is a declarative two-step operation: the former
primary (`pg-eu`) is demoted and produces a `demotionToken`, which is then
applied together with a `promotionToken` to `pg-us`. Every cluster has a
valid streaming path after the switchover:

```
pg-us (primary) ◄── pg-apj ◄── pg-eu
```

See the [CloudNativePG documentation on distributed topology](https://cloudnative-pg.io/docs/current/replica_cluster#distributed-topology)
for the full switchover procedure.

Each cluster also holds `ObjectStore` and `externalClusters` entries for
**all** regions, so any streaming path after a switchover has access to
every WAL archive.

## Prerequisites

To follow this demonstration, ensure the following are installed on your system:

1. **CNPG Playground**: Refer to the [installation guide](../README.md) for
  setup instructions. If you intend to use Prometheus together with the Grafana
  dashboards, make sure that you also deploy the [monitoring](../monitoring/)
  environment.

2. **`cmctl` (cert-manager CLI)**: Required for secure communication between
  the operator and the `barman-cloud` plugin, which is used for backup and
  recovery with RustFS object stores.
  Follow the [official `cmctl` installation guide](https://cert-manager.io/docs/reference/cmctl/#installation).
  For detailed guidance, refer to the official
  [`cert-manager` installation documentation](https://cert-manager.io/docs/installation/).

## Deployment

Once the CNPG Playground is installed, deploy the PostgreSQL clusters across
the regions using:

```bash
./demo/setup.sh
```

This deploys to the default regions (`eu` and `us`). To target specific
regions, pass them as arguments:

```bash
./demo/setup.sh eu us apj
```

> [!NOTE]
> When regions are auto-detected (no arguments given), they are sorted
> alphabetically. The circular replication chain is built in that order,
> with the first region becoming the primary. If you need a specific primary
> or a particular streaming order, pass the regions explicitly on the
> command line.

This process takes a few minutes to complete.
It installs the latest version of CloudNativePG, cert-manager, and the
[Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/),
followed by the deployment of the PostgreSQL clusters.

### Options

| Variable | Default | Description |
|----------|---------|-------------|
| `LEGACY=true` | `false` | Use the legacy in-tree Barman Cloud code instead of the Barman Cloud Plugin |
| `TRUNK=true` | `false` | Deploy from the `main` branch of both CloudNativePG and the Barman Cloud Plugin |
| `DRY_RUN=true` | `false` | Print the generated YAML to stdout without applying it |
| `OUTPUT_DIR=<path>` | _(unset)_ | Save the generated YAML to `<path>/<region>.yaml` (one file per region) and apply it |
| `DRY_RUN=true OUTPUT_DIR=<path>` | | Save the generated YAML to files only, without applying |
| `POSTGRESQL_IMAGE=<image>` | `ghcr.io/cloudnative-pg/postgresql:18-standard-trixie` | PostgreSQL image used in plugin mode |
| `POSTGRESQL_LEGACY_IMAGE=<image>` | `ghcr.io/cloudnative-pg/postgresql:18-system-trixie` | PostgreSQL image used in legacy mode |
| `K8S_CONTEXT_PREFIX` | `kind-` | Prefix of kubectl context names; override when targeting non-Kind clusters |
| `K8S_NAME` | `k8s-` | Base name of clusters in kubectl context names |
| `DEBUG=true` | `false` | Enable shell trace output (`set -x`) for debugging |

The last two variables are useful when deploying the demo against existing
Kubernetes clusters rather than the Kind clusters created by
`scripts/setup.sh`.
For example, if your contexts are named `eu` and `us`, set both to empty
strings: `K8S_CONTEXT_PREFIX="" K8S_NAME="" ./demo/setup.sh eu us`.

### Template customisation

`demo/setup.sh` renders YAML from the fragments in `demo/templates/` using
`envsubst`. You can replace the entire directory or override individual
fragments without modifying the repository.

| Variable | Description |
|----------|-------------|
| `TEMPLATES_DIR=<path>` | Replace the whole templates directory with your own |
| `CLUSTER_TEMPLATE=<file>` | Override `cluster.yaml` only |
| `BOOTSTRAP_INITDB_TEMPLATE=<file>` | Override `bootstrap-initdb.yaml` |
| `BOOTSTRAP_RECOVERY_TEMPLATE=<file>` | Override `bootstrap-recovery.yaml` |
| `CLUSTER_PLUGIN_PARAMS_TEMPLATE=<file>` | Override `cluster-plugin-params.yaml` |
| `REPLICA_SECTION_TEMPLATE=<file>` | Override `replica-section.yaml` |
| `EXTERNAL_CLUSTER_PLUGIN_TEMPLATE=<file>` | Override `external-cluster-plugin.yaml` |
| `SCHEDULEDBACKUP_PLUGIN_TEMPLATE=<file>` | Override `scheduledbackup-plugin.yaml` |
| `OBJECTSTORE_TEMPLATE=<file>` | Override `objectstore.yaml` |
| `PODMONITOR_TEMPLATE=<file>` | Override `podmonitor.yaml` |

Legacy-mode equivalents (used with `LEGACY=true`):

| Variable | Description |
|----------|-------------|
| `CLUSTER_LEGACY_PARAMS_TEMPLATE=<file>` | Override `legacy/cluster-legacy-params.yaml` |
| `EXTERNAL_CLUSTER_LEGACY_TEMPLATE=<file>` | Override `legacy/external-cluster-legacy.yaml` |
| `SCHEDULEDBACKUP_LEGACY_TEMPLATE=<file>` | Override `legacy/scheduledbackup-legacy.yaml` |

Examples:

```bash
# Use a completely custom templates directory
TEMPLATES_DIR=/path/to/my-templates ./demo/setup.sh

# Override only the Cluster fragment, keep everything else
CLUSTER_TEMPLATE=/path/to/my-cluster.yaml ./demo/setup.sh

# Preview the result of your custom template without applying
DRY_RUN=true CLUSTER_TEMPLATE=/path/to/my-cluster.yaml ./demo/setup.sh
```

Examples:

```bash
# Legacy in-tree Barman backup
LEGACY=true ./demo/setup.sh

# Deploy from main branch
TRUNK=true ./demo/setup.sh

# Preview generated YAML without applying
DRY_RUN=true ./demo/setup.sh

# Save generated YAML to files and apply
OUTPUT_DIR=/tmp/demo-yaml ./demo/setup.sh

# Save to files only, no kubectl apply
DRY_RUN=true OUTPUT_DIR=/tmp/demo-yaml ./demo/setup.sh
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
the CNPG Playground. As with `setup.sh`, you can pass explicit region names:

```bash
./demo/teardown.sh eu us apj
```

For a detailed understanding of the teardown process, refer to the
[`teardown.sh` script](teardown.sh).
