[![CloudNativePG](./logo/cloudnativepg.png)](https://cloudnative-pg.io/)

# Local Learning Environment for CloudNativePG

Welcome to **`cnpg-playground`**, a local learning environment designed for
learning and experimenting with CloudNativePG using Docker and Kind.

## Prerequisites

Ensure you have the latest available versions of the following tools installed
on a Unix-based system:

- [Docker](https://www.docker.com/)
- [Git](https://git-scm.com/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [The `cnpg` plugin for `kubectl`](https://cloudnative-pg.io/documentation/current/kubectl-plugin/)
- [Kind](https://kind.sigs.k8s.io/)

You don’t need superuser privileges to run the scripts, but elevated
permissions may be required to install the prerequisites.

### Additional Tools

For an improved experience with the CNPG Playground, it’s recommended to
install the following tools:

- **[`curl`](https://curl.se/)**: Command-line tool for data transfer.
- **[`jq`](https://jqlang.github.io/jq/)**: JSON processor for handling API
  outputs.
- **[`stern`](https://github.com/stern/stern)**: Multi-pod log tailing tool.
- **[`kubectx`](https://github.com/ahmetb/kubectx)**: Kubernetes context
  switcher.

Recommended `kubectl` plugins:

- **[`view-secret`](https://github.com/elsesiy/kubectl-view-secret)**: Decodes
  Kubernetes secrets.
- **[`view-cert`](https://github.com/lmolas/kubectl-view-cert)**: Inspects TLS
  certificates.

These tools streamline working with the CNPG Playground.

## Local Environment Overview

This environment emulates a two-region infrastructure (EU and US), with each
region containing:

- An object storage service powered by [MinIO](https://min.io/) containers
- A Kubernetes cluster, deployed using [Kind](https://kind.sigs.k8s.io/),
  consisting of:

    - One control plane node
    - One node for infrastructure components
    - One node for applications
    - Three nodes dedicated to PostgreSQL

The architecture is illustrated in the diagram below:

![Local Environment Architecture](images/cnpg-playground-architecture.png)

## Setting Up the Learning Environment

To set up the environment, simply run the following script:

```bash
./scripts/setup.sh
```

## Connecting to the Kubernetes Clusters

To configure and interact with both Kubernetes clusters during the learning
process, you will need to connect to them.

The **setup** script provides detailed instructions for accessing the clusters.
If you need to view the connection details again after the setup, you can
retrieve them by running:

```bash
./scripts/info.sh
```

## Inspecting Nodes in a Kubernetes Cluster

To inspect the nodes in a Kubernetes cluster, you can use the following
command:

```bash
kubectl get nodes
```

For example, when connected to the `k8s-eu` cluster, this command will display
output similar to:

```console
NAME                   STATUS   ROLES           AGE     VERSION
k8s-eu-control-plane   Ready    control-plane   10m     v1.33.0
k8s-eu-worker          Ready    infra           9m58s   v1.33.0
k8s-eu-worker2         Ready    app             9m58s   v1.33.0
k8s-eu-worker3         Ready    postgres        9m58s   v1.33.0
k8s-eu-worker4         Ready    postgres        9m58s   v1.33.0
k8s-eu-worker5         Ready    postgres        9m58s   v1.33.0
```

In this example:
- The control plane node (`k8s-eu-control-plane`) manages the cluster.
- Worker nodes have different roles, such as `infra` for infrastructure, `app`
  for application workloads, and `postgres` for PostgreSQL databases. Each node
  runs Kubernetes version `v1.33.0`.

## Demonstration with CNPG Playground

The **CNPG Playground** offers a great environment for exploring the
**CloudNativePG operator** and the broader concept of running PostgreSQL on
Kubernetes.
It allows you to create custom scenarios and demo environments with ease.

To help you get started, we've included a demo scenario that showcases the
[**distributed topology** feature](https://cloudnative-pg.io/documentation/current/replica_cluster/).
This walkthrough guides you through deploying a **PostgreSQL cluster
distributed across two regions** within the playground. The symmetric
architecture also includes **continuous backup** using the
[Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/).

For complete instructions and supporting resources, refer to the [demo
folder](./demo/README.md).

## Installing CloudNativePG on the Control Plane

If you plan to use the CNPG Playground without the demo mentioned earlier,
you’ll need to install CloudNativePG manually.

To install the latest stable version of the CloudNativePG operator on the
control plane nodes in both Kubernetes clusters, execute the following
commands:

```bash
for region in eu us; do
   kubectl cnpg install generate --control-plane | \
      kubectl --context kind-k8s-${region} apply -f - --server-side

   kubectl --context kind-k8s-${region} rollout status deployment \
      -n cnpg-system cnpg-controller-manager
done
```

These commands will deploy the CloudNativePG operator with server-side apply on
both the `kind-k8s-eu` and `kind-k8s-us` clusters.

Ensure that you have the latest version of the `cnpg` plugin installed on your
local machine.

## Cleaning up the Learning Environment

When you're ready to clean up and remove all resources from the learning
environment, run the following script to tear down the containers and
associated resources:

```bash
./scripts/teardown.sh
```

This will safely destroy all running containers and return your environment to
its initial state.

## Single Kubernetes Cluster Setup

In some situations, you may prefer to have a single Kubernetes cluster
playground without the object store. To create such a cluster, run the
following command:

```sh
kind create cluster --config k8s/kind-cluster.yaml
```

Then, run:

```sh
kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=
```

The result is the following:

```console
$ kubectl get nodes
NAME                 STATUS   ROLES           AGE   VERSION
cnpg-control-plane   Ready    control-plane   22m   v1.33.0
cnpg-worker          Ready    infra           22m   v1.33.0
cnpg-worker2         Ready    app             22m   v1.33.0
cnpg-worker3         Ready    postgres        22m   v1.33.0
cnpg-worker4         Ready    postgres        22m   v1.33.0
cnpg-worker5         Ready    postgres        22m   v1.33.0
```

## Nix Flakes

Do you use Nix flakes? If you do, this package have a configured
dev shell that can be used with:

```
nix develop .
```

## Using Linux or WSL2

You may need:

```
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

More information in the [relative ticket comment](https://github.com/kubernetes-sigs/kind/issues/3423#issuecomment-1872074526).

## Using Rancher Desktop

You may need to follow the instructions [in the Rancher Desktop
Guide](https://docs.rancherdesktop.io/how-to-guides/increasing-open-file-limit/)
to increase the open file limit.

```
provision:
- mode: system
  script: |
    #!/bin/sh
    cat <<'EOF' > /etc/security/limits.d/rancher-desktop.conf
    * soft     nofile         82920
    * hard     nofile         82920
    EOF
    sysctl -w vm.max_map_count=262144
    sysctl fs.inotify.max_user_watches=524288
    sysctl fs.inotify.max_user_instances=512
```
