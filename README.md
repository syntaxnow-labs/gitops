# GitOps
Declarative Kubernetes deployment repository for all applications managed by ArgoCD. This repo stores manifests, Kustomize overlays, and environment configurations that define the desired state of the cluster. Git becomes the single source of truth — any change merged here is automatically applied to the cluster via ArgoCD.

ArgoCD continuously watches this repo and automatically syncs changes to the cluster.

## 📦 What lives inside this repo?
gitops/
  apps/
    <app-name>/
      deployment.yaml        → Base deployment
      kustomization.yaml     → Kustomize definition
      values-dev.yaml        → Environment overrides
  clusters/
    vm2/
      apps.yaml              → List of apps deployed to VM2 cluster
      kustomization.yaml     → Cluster-level configuration

**apps**/

Each application gets its own folder with manifest templates.

**clusters**/

Defines which apps belong to which cluster/environment.

## 🚀 GitOps Workflow

 1. Developer pushes code → CI builds container → image goes to GHCR
 2. CI updates this GitOps repo with the new image tag
 3. ArgoCD detects the change
 4. ArgoCD applies the new version to the cluster
 5. Your app is deployed — no kubectl needed
Git is the source of truth.
ArgoCD handles the automation.

## 🔗 ArgoCD Setup
ArgoCD points to:
```sh
gitops/clusters/vm2
```
Where cluster apps and configurations are defined.

## 🔒 Secrets Policy

This repo must NOT contain:
 - Kubernetes Secrets in plain YAML
 - Access tokens
 - Certificates
 - Private keys

All sensitive values must be stored using:
 - External Secrets Operator
 - SOPS
 - Vault
 - Sealed Secrets

## 🛠 Tools Used

 - **ArgoCD** for continuous delivery
 - **Kustomize** for configuration management
 - **GitHub Actions** for automated image builds + GitOps updates
 - **GHCR** for container registry

## GitOps App Bootstrap Script

The `scripts/bootstrap-app.sh` script is used to scaffold a new application structure inside the GitOps repository.
It automatically creates the standard folder layout under `apps/<app-name>/` including base manifests and environment overlays (dev, qa, prod).

The generated templates include Kubernetes Deployment, Service, Ingress, Kustomization files, and an image patch file that CI/CD workflows can later update with the correct container tag.

This script ensures every new service follows the same GitOps conventions and prevents manual YAML copy/paste errors.

Example usage:

```bash

chmod +x scripts/bootstrap-app.sh
./scripts/bootstrap-app.sh poc-apache-arrow

```

## 🤝 Contribution

Any change to cluster state must be done through a pull request.
Once merged, ArgoCD will sync automatically.
