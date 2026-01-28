## GitOps Platform – SyntaxNow Labs

This repository is the central GitOps source of truth for deploying all SyntaxNow Labs applications into our Kubernetes (k3s) cluster using ArgoCD.

Once an application is registered here:

> Git Commit → ArgoCD Sync → Kubernetes Deployment Updated Automatically
---
## Repository Structure
```bash

gitops/
│
├── apps/                       # All application manifests (Kustomize)
│   ├── mock-api-service/
│   ├── oneplatform/
│   ├── poc-apache-arrow/
│   └── sample-react-app/
│
├── clusters/                   # Cluster-level ArgoCD control
│   └── vm-0656/
│       ├── root.yaml           # Root ArgoCD Application (one-time apply)
│       ├── apps-dev.yaml       # Apps enabled in dev
│       ├── apps-qa.yaml        # Apps enabled in qa
│       ├── apps-prod.yaml      # Apps enabled in prod
│       ├── apps-dev-appset.yaml
│       ├── apps-qa-appset.yaml
│       └── apps-prod-appset.yaml
│
└── scripts/
    └── bootstrap-app.sh        # Auto scaffold new GitOps apps

```
---
## GitOps Application Layout
Every app follows the same standard structure:
```bash

apps/<app-name>/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
│
└── overlays/
    ├── dev/
    │   ├── ingress.yaml
    │   ├── patch-image.yaml
    │   ├── values-dev.yaml
    │   └── kustomization.yaml
    │
    ├── qa/
    └── prod/

```
### Base
- Contains common Kubernetes manifests.

### Overlays
- Environment-specific configuration:
    - domain name 
    - ingress rules 
    - image patch updates 
    - config values
---
## Bootstrapping a New Application
To create a new GitOps scaffold automatically, we use:

Script: `bootstrap-app.sh`

#### **Usage**
```bash

./scripts/bootstrap-app.sh <app-name> <app-type> <deploy-envs>
```
### Example (Backend)
```bash

./scripts/bootstrap-app.sh poc-apache-arrow backend dev,qa
```
### Example (Frontend)
```bash

./scripts/bootstrap-app.sh oneplatform frontend dev,prod
```
## Script Arguments
| Argument    | Description                          |
| ----------- | ------------------------------------ |
| app-name    | Name of the app/repo                 |
| app-type    | `backend` or `frontend`              |
| deploy-envs | Optional environments: `dev,qa,prod` |

## Port Behavior
| Type     | Container Port |
| -------- | -------------- |
| backend  | 9090           |
| frontend | 80             |

**_Service always exposes:_**
```shell

port: 80
targetPort: containerPort
```
---
## Environment Registration

Apps are deployed only when registered in:
```shell

clusters/vm-0656/apps-dev.yaml
clusters/vm-0656/apps-qa.yaml
clusters/vm-0656/apps-prod.yaml
```
**_Example:_**
```yaml
- app: oneplatform
- app: mock-api-service
```
If an app is **_not listed_**, ArgoCD will ignore it.

---
## Automatic CD with ArgoCD ApplicationSets
Instead of managing every individual Argo Applications manually, we use ApplicationSets.

Each environment has one ApplicationSet:
- dev apps 
- qa apps 
- prod apps

**Example:**
```yaml
generators:
- list:
  elements: [...]
```
ArgoCD automatically creates one Application per enabled app.

---
## Root Bootstrap (One-Time Setup)
The only manual step required in the cluster is applying the root ArgoCD app:
```bash

kubectl apply -f clusters/vm-0656/root.yaml
```
After this:
- ArgoCD takes full control 
- Apps auto-sync from Git 
- No manual kubectl applies needed
---
## GitHub Actions Workflows
### 1. Bootstrap New App
Workflow:
- creates app folder structure 
- optionally enables environments 
- commits scaffold automatically 
- Run from GitHub Actions UI:
```css
Bootstrap GitOps App Structure
```
Inputs:
- app_name 
- app_type 
- deploy_envs (optional)
---
### 2. Build → Push → GitOps Image Update
CI pipeline:
- builds Docker image 
- pushes to GHCR 
- updates GitOps patch-image.yaml 
- ArgoCD syncs automatically
```shell

apps/<app>/overlays/<env>/patch-image.yaml
```
---
## Common Operations
### View All Applications
```bash

kubectl get applications -n argocd
```
### View ApplicationSets
```bash

kubectl get applicationsets -n argocd
```
### Restart an App
```bash

kubectl rollout restart deployment <app> -n default
```
### Logs & Debugging (Readhere [troubleshooting.md](troubleshooting.md))
### View Pods of an Application
```shell

kubectl get pods -n default
```
Example:
```shell

kubectl get pods -n default | grep oneplatform
```
### View Logs of a Running Pod
```shell

kubectl logs <pod-name> -n default
```
Example:
```shell

kubectl logs oneplatform-c4c6f84f7-fgz9k -n default
```
### Follow Logs (Live Streaming)
```shell
kubectl logs -f <pod-name> -n default
```
Example:
```shell
kubectl logs -f poc-apache-arrow-5479b9669f-vfxml -n default
```

### Delete an App Deployment
```bash

kubectl delete application <app>-prod -n argocd
```
(ArgoCD will recreate it unless removed from apps-prod.yaml)

---
## GitOps Rules
- Git is the source of truth 
- Never apply app YAML manually 
- Enable apps only via env lists 
- ArgoCD handles sync, prune, healing 
- Bootstrap script ensures consistency
---
## Conclusion
This GitOps platform provides:
- standardized Kubernetes deployment structure 
- automatic app onboarding 
- environment-based deployment control 
- full ArgoCD continuous delivery automation
---

