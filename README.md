# gitops
Declarative Kubernetes deployment repository for all applications managed by ArgoCD. This repo stores manifests, Kustomize overlays, and environment configurations that define the desired state of the cluster. Git becomes the single source of truth — any change merged here is automatically applied to the cluster via ArgoCD.
