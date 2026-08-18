# CloudNativePG Demo: Distributed Topology

This guide provides step-by-step instructions for setting up a PostgreSQL
database across one or more regions in the playground, using the
[CloudNativePG distributed topology feature](https://cloudnative-pg.io/documentation/current/replica_cluster/#distributed-topology).
Object stores are employed to synchronise the primary cluster with the
secondary (Disaster Recovery) cluster through the
[Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/).

## Architecture

The demo supports any number of regions (defaulting to `eu` and `na`).
For the default two-region setup:

- **Primary PostgreSQL cluster (`pg-eu`)**: Three instances running in the
  `k8s-eu` Kubernetes cluster (one primary and two replicas).
- **Disaster Recovery (passive) PostgreSQL cluster (`pg-na`)**: Three replicas
  (one designated primary and two cascading replicas) running in the `k8s-na`
  Kubernetes cluster.

When more than one region is used, the clusters form a circular replica chain.
Each cluster streams from its predecessor, and the primary (first region) wraps
around to the last. For example, with `eu na apj`:

| Cluster | Streams from (source) |
|---------|-----------------------|
| `pg-eu` (primary) | `pg-apj` (dormant until demotion) |
| `pg-na` | `pg-eu` |
| `pg-apj` | `pg-na` |

Normal state:

```
pg-eu (primary) ◄── pg-na ◄── pg-apj
     └──────────────────────────────┘ (wrap-around, dormant)
```

Switching over to `pg-na` is a declarative two-step operation: the former
primary (`pg-eu`) is demoted and produces a `demotionToken`, which is then
applied together with a `promotionToken` to `pg-na`. Every cluster has a
valid streaming path after the switchover:

```
pg-na (primary) ◄── pg-apj ◄── pg-eu
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

3. **`helm`**: Only required when deploying with `KLIO=true`, since the
  [Klio Operator](https://github.com/cloudnative-pg/klio) is distributed as a
  Helm chart. Follow the
  [official Helm installation guide](https://helm.sh/docs/intro/install/).

## Deployment

Once the CNPG Playground is installed, deploy the PostgreSQL clusters across
the regions using:

```bash
./demo/setup.sh
```

This deploys to the default regions (`eu` and `na`). To target specific
regions, pass them as arguments:

```bash
./demo/setup.sh eu na apj
```

> [!NOTE]
> When regions are auto-detected (no arguments given), they are sorted
> alphabetically. The circular replication chain is built in that order,
> with the first region becoming the primary. If you need a specific primary
> or a particular streaming order, pass the regions explicitly on the
> command line.

This process takes a few minutes to complete.
It installs the latest version of CloudNativePG, cert-manager, the
[Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/), and a
[`ClusterImageCatalog`](https://github.com/cloudnative-pg/artifacts/tree/main/image-catalogs-extensions)
providing common extensions (pgvector, PostGIS, TimescaleDB, pgaudit,
wal2json, pg-crash), followed by the deployment of the PostgreSQL clusters.

### Options

| Variable | Default | Description |
|----------|---------|-------------|
| `LEGACY=true` | `false` | Use the legacy in-tree Barman Cloud code instead of the Barman Cloud Plugin |
| `TRUNK=true` | `false` | Deploy from the `main` branch of both CloudNativePG and the Barman Cloud Plugin |
| `KLIO=true` | `false` | Also protect the cluster with the [Klio Operator](https://cloudnative-pg.io/klio/), alongside the Barman Cloud Plugin. Has no effect together with `LEGACY=true` |
| `BARMAN_CLOUD_PLUGIN=false` | `true` | Disable the Barman Cloud Plugin. Only valid together with `KLIO=true` (so Klio protects the cluster on its own) and only supports a single region. Has no effect together with `LEGACY=true`: the Barman Cloud Plugin operator is deployed regardless of `LEGACY` (for parity with the non-Klio setup), even though a legacy-mode Cluster doesn't reference it |
| `REQUIREMENTS_ONLY=true` | `false` | Deploy only CloudNativePG, cert-manager, the Barman Cloud Plugin (unless `BARMAN_CLOUD_PLUGIN=false`), the Klio Operator (with `KLIO=true`), and the `ClusterImageCatalog`; skip ObjectStores/Clusters. A later plain run automatically detects and skips already-installed requirements |
| `IMAGE_CATALOG_URL=<url>` | [`catalog-minimal-trixie.yaml`](https://github.com/cloudnative-pg/artifacts/blob/main/image-catalogs-extensions/catalog-minimal-trixie.yaml) | `ClusterImageCatalog` manifest applied in every region |
| `IMAGE_CATALOG_NAME=<name>` | `postgresql-minimal-trixie` | Must match `metadata.name` in `IMAGE_CATALOG_URL`; referenced by the Cluster's `imageCatalogRef` (plugin mode) |
| `POSTGRESQL_VERSION=<major>` | `18` | PostgreSQL major version selected from the catalog, in plugin mode |
| `DRY_RUN=true` | `false` | Print the generated YAML to stdout without applying it |
| `OUTPUT_DIR=<path>` | _(unset)_ | Save the generated YAML to `<path>/<region>.yaml` (one file per region) and apply it |
| `DRY_RUN=true OUTPUT_DIR=<path>` | | Save the generated YAML to files only, without applying |
| `POSTGRESQL_LEGACY_IMAGE=<image>` | `ghcr.io/cloudnative-pg/postgresql:18-system-trixie` | PostgreSQL image used directly (`imageName`) in legacy mode; the catalog only ships minimal images, so legacy mode can't use `imageCatalogRef` |
| `K8S_CONTEXT_PREFIX` | `kind-` | Prefix of kubectl context names; override when targeting non-Kind clusters |
| `K8S_NAME` | `k8s-` | Base name of clusters in kubectl context names |
| `DEBUG=true` | `false` | Enable shell trace output (`set -x`) for debugging |

The last two variables are useful when deploying the demo against existing
Kubernetes clusters rather than the Kind clusters created by
`scripts/setup.sh`.
For example, if your contexts are named `eu` and `na`, set both to empty
strings: `K8S_CONTEXT_PREFIX="" K8S_NAME="" ./demo/setup.sh eu na`.

### Template customisation

`demo/setup.sh` renders YAML from the fragments in `demo/templates/` using
`envsubst`. You can replace the entire directory or override individual
fragments without modifying the repository.

| Variable | Description |
|----------|-------------|
| `TEMPLATES_DIR=<path>` | Replace the whole templates directory with your own |
| `CLUSTER_TEMPLATE=<file>` | Override `cluster.yaml` only |
| `STORAGE_TEMPLATE=<file>` | Override `storage.yaml` (shared by both modes) |
| `BOOTSTRAP_INITDB_TEMPLATE=<file>` | Override `bootstrap-initdb.yaml` |
| `BOOTSTRAP_RECOVERY_TEMPLATE=<file>` | Override `bootstrap-recovery.yaml` |
| `IMAGE_CATALOG_TEMPLATE=<file>` | Override `image-catalog.yaml` (plugin mode's `imageCatalogRef`) |
| `CLUSTER_PLUGIN_PARAMS_TEMPLATE=<file>` | Override `cluster-plugin-params.yaml` |
| `REPLICA_SECTION_TEMPLATE=<file>` | Override `replica-section.yaml` |
| `EXTERNAL_CLUSTER_PLUGIN_TEMPLATE=<file>` | Override `external-cluster-plugin.yaml` |
| `SCHEDULEDBACKUP_PLUGIN_TEMPLATE=<file>` | Override `scheduledbackup-plugin.yaml` |
| `OBJECTSTORE_TEMPLATE=<file>` | Override `objectstore.yaml` |
| `PODMONITOR_TEMPLATE=<file>` | Override `podmonitor.yaml` |
| `KLIO_SERVER_TEMPLATE=<file>` | Override `klio/server.yaml` (used with `KLIO=true`) |
| `KLIO_PLUGINCONFIG_TEMPLATE=<file>` | Override `klio/pluginconfiguration.yaml` (used with `KLIO=true`) |
| `KLIO_CLUSTER_PARAMS_TEMPLATE=<file>` | Override `klio/cluster-klio-params.yaml` (used with `KLIO=true`) |
| `KLIO_PG_HBA_TEMPLATE=<file>` | Override `klio/postgresql-pg-hba.yaml` (used with `KLIO=true`) |
| `SCHEDULEDBACKUP_KLIO_TEMPLATE=<file>` | Override `klio/scheduledbackup-klio.yaml` (used with `BARMAN_CLOUD_PLUGIN=false KLIO=true`) |

Legacy-mode equivalents (used with `LEGACY=true`):

| Variable | Description |
|----------|-------------|
| `CLUSTER_LEGACY_PARAMS_TEMPLATE=<file>` | Override `legacy/cluster-legacy-params.yaml` |
| `IMAGE_LEGACY_TEMPLATE=<file>` | Override `legacy/image-legacy.yaml` (legacy mode's `imageName`) |
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

## Klio

Passing `KLIO=true` also deploys the [Klio Operator](https://cloudnative-pg.io/klio/)
and attaches a `klio-${REGION}` Server to each region's cluster, alongside
the Barman Cloud Plugin by default:

```bash
KLIO=true ./demo/setup.sh
```

Add `BARMAN_CLOUD_PLUGIN=false` to have Klio protect the cluster on its own
(single region only):

```bash
BARMAN_CLOUD_PLUGIN=false KLIO=true ./demo/setup.sh local
```

`LEGACY=true` can't be combined with `KLIO=true`. In short:

| `LEGACY` | `KLIO` | `BARMAN_CLOUD_PLUGIN` | Result |
|----------|--------|----------|--------|
| `false` | `false` | `true` (default) | Barman Cloud Plugin only |
| `false` | `true` | `true` (default) | Barman Cloud Plugin **+** Klio |
| `false` | `true` | `false` | Klio only (single region) |
| `true` | *(ignored)* | *(ignored)* | Legacy in-tree Barman only |

Once deployed, take a backup with (adjust `--context` for your region):

```bash
kubectl cnpg backup pg-eu \
  --context kind-k8s-eu \
  --backup-target primary \
  --method plugin \
  --plugin-name klio.cnpg.io
```

### Restoring a backup

`demo/templates/klio/cluster-restore-klio.yaml` is a standalone example that
bootstraps a new `pg-${REGION}-restore` cluster from an existing backup.
Render and apply it manually once a backup exists:

```bash
REGION=local IMAGE_CATALOG_NAME=postgresql-minimal-trixie POSTGRESQL_VERSION=18 \
  envsubst '${REGION} ${IMAGE_CATALOG_NAME} ${POSTGRESQL_VERSION}' \
  < demo/templates/klio/cluster-restore-klio.yaml | kubectl --context kind-k8s-local apply -f -

kubectl --context kind-k8s-local wait --timeout 10m --for=condition=Ready cluster/pg-local-restore
```

Clean it up with:

```bash
kubectl --context kind-k8s-local delete cluster/pg-local-restore \
  pluginconfiguration/klio-pg-local-restore \
  certificate/pg-local-restore-klio-user \
  secret/pg-local-restore-klio-user
```

## Teardown

If you need to clean up or restart the demonstration, remove the created
objects using:

```bash
./demo/teardown.sh
```

This enables you to recreate the demonstration database without reinstalling
the CNPG Playground. As with `setup.sh`, you can pass explicit region names:

```bash
./demo/teardown.sh eu na apj
```

For a detailed understanding of the teardown process, refer to the
[`teardown.sh` script](teardown.sh).
