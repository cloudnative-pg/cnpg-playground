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

## Setting Up the Learning Environment

The environment simulates a two-region infrastructure (EU and US), each consisting of:

- Object storage, powered by [MinIO](https://min.io/) containers
- Kubernetes clusters, deployed with [Kind](https://kind.sigs.k8s.io/)

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
