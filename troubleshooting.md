# GitOps + ArgoCD Troubleshooting Guide

This document provides a **step-by-step debugging flow** for issues in a
Kubernetes + ArgoCD GitOps cluster.

------------------------------------------------------------------------

# 1. Check ArgoCD Application Status

List all apps:

``` bash
kubectl get applications -n argocd
```

Describe a specific app:

``` bash
kubectl describe application <app-name> -n argocd
```

Example:

``` bash
kubectl describe application oneplatform-prod -n argocd
```

Look for:

-   OutOfSync
-   Degraded
-   Missing resources
-   Validation errors

------------------------------------------------------------------------

# 2. Check ApplicationSet Status

List ApplicationSets:

``` bash
kubectl get applicationsets -n argocd
```

Describe one:

``` bash
kubectl describe applicationset <name> -n argocd
```

Example:

``` bash
kubectl describe applicationset vm-0656-prod-apps -n argocd
```

Common issue:

-   Duplicate app names
-   Missing overlays

------------------------------------------------------------------------

# 3. Check Pods for the Application

List pods:

``` bash
kubectl get pods -n default
```

Filter by app:

``` bash
kubectl get pods -n default | grep oneplatform
```

If pod is not Running:

-   CrashLoopBackOff
-   ImagePullBackOff
-   Pending

------------------------------------------------------------------------

# 4. View Pod Logs

Get logs:

``` bash
kubectl logs <pod-name> -n default
```

Follow logs live:

``` bash
kubectl logs -f <pod-name> -n default
```

Deployment logs (recommended):

``` bash
kubectl logs deploy/<deployment-name> -n default
```

Example:

``` bash
kubectl logs deploy/poc-apache-arrow -n default
```

Previous crash logs:

``` bash
kubectl logs <pod-name> -n default --previous
```

------------------------------------------------------------------------

# 5. Describe Pod Events

Pod events show real failure reasons:

``` bash
kubectl describe pod <pod-name> -n default
```

Look for:

-   Port mismatch
-   Probe failures
-   Mount issues
-   Image errors

------------------------------------------------------------------------

# 6. Check Service Connectivity

List services:

``` bash
kubectl get svc -n default
```

Check endpoints:

``` bash
kubectl get endpoints <service-name> -n default
```

Example:

``` bash
kubectl get endpoints oneplatform -n default
```

If endpoints are empty → pods not connected.

------------------------------------------------------------------------

# 7. Debug Inside Cluster (Curl Test)

Run temporary curl pod:

``` bash
kubectl run curl-debug --rm -it --image=curlimages/curl -- sh
```

Test service DNS:

``` bash
curl -v http://oneplatform.default.svc.cluster.local
```

Test direct pod IP:

``` bash
curl -v http://10.42.x.x:9090
```

If curl fails:

-   App not listening
-   Wrong containerPort
-   Wrong targetPort

------------------------------------------------------------------------

# 8. Ingress Troubleshooting (503 Bad Gateway)

List ingresses:

``` bash
kubectl get ingress -n default
```

Describe ingress:

``` bash
kubectl describe ingress <name> -n default
```

Example:

``` bash
kubectl describe ingress oneplatform-ingress -n default
```

Common causes of 503:

-   Service targetPort mismatch
-   App running on different port
-   No endpoints

------------------------------------------------------------------------

# 9. Check Ingress Controller Logs

If ingress is failing:

``` bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
```

This reveals routing + upstream errors.

------------------------------------------------------------------------

# 10. Restart an Application

Restart deployment:

``` bash
kubectl rollout restart deployment <app-name> -n default
```

Restart all deployments in namespace:

``` bash
kubectl rollout restart deployment -n default
```

------------------------------------------------------------------------

# 11. Remove an Application (Testing)

Delete Argo application:

``` bash
kubectl delete application <app-name>-prod -n argocd
```

Delete Kubernetes resources:

``` bash
kubectl delete all -l app=<app-name> -n default
```

------------------------------------------------------------------------

# Golden Debugging Flow (Fast)

When something fails:

1.  ArgoCD status\
2.  Pod status\
3.  Logs\
4.  Service endpoints\
5.  Curl inside cluster\
6.  Ingress rules\
7.  Ingress controller logs

------------------------------------------------------------------------

# Most Common Real Issue

### Port mismatch:

Frontend expects:

-   containerPort: 80

Backend expects:

-   containerPort: 9090 or 8080

Service must match targetPort correctly.

------------------------------------------------------------------------