[![CloudNativePG](./logo/cloudnativepg.png)](https://cloudnative-pg.io/)

# Local Learning Environment for CloudNativePG

Welcome to **`cnpg-playground`**, a local learning environment designed for
learning and experimenting with CloudNativePG using Docker and Kind.

## Prerequisites

Ensure you have the following tools installed on a Unix-based system:

- [Docker](https://www.docker.com/)  
- [Git](https://git-scm.com/)  
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)  
- [Kind](https://kind.sigs.k8s.io/)

You don’t need superuser privileges to run the scripts, but elevated
permissions may be required to install the prerequisites.

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
k8s-eu-control-plane   Ready    control-plane   10m     v1.31.0
k8s-eu-worker          Ready    infra           9m58s   v1.31.0
k8s-eu-worker2         Ready    app             9m58s   v1.31.0
k8s-eu-worker3         Ready    postgres        9m58s   v1.31.0
k8s-eu-worker4         Ready    postgres        9m58s   v1.31.0
k8s-eu-worker5         Ready    postgres        9m58s   v1.31.0
```

In this example:
- The control plane node (`k8s-eu-control-plane`) manages the cluster.
- Worker nodes have different roles, such as `infra` for infrastructure, `app`
  for application workloads, and `postgres` for PostgreSQL databases. Each node
  runs Kubernetes version `v1.31.0`.

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
