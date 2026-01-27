#!/bin/bash
set -e

# ---------------------------------------------------
# GitOps App Scaffold Script
#
# Usage:
#   ./scripts/bootstrap-app.sh <app-name>
#
# Example:
#   ./scripts/bootstrap-app.sh poc-apache-arrow
#
# Creates:
#   apps/<app>/base
#   apps/<app>/overlays/dev
#   apps/<app>/overlays/qa
#   apps/<app>/overlays/prod
# ---------------------------------------------------

APP_NAME=$1

if [ -z "$APP_NAME" ]; then
  echo "Usage: ./scripts/bootstrap-app.sh <app-name>"
  echo "Example: ./scripts/bootstrap-app.sh poc-apache-arrow"
  exit 1
fi

# Force lowercase for DNS + Kubernetes safety
APP_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')

APP_DIR="apps/$APP_LOWER"

# Prevent overwriting existing apps
if [ -d "$APP_DIR" ]; then
  echo "[Error] App '$APP_LOWER' already exists at: $APP_DIR"
  exit 1
fi

echo "Bootstrapping GitOps structure for: $APP_LOWER"

# ---------------------------------------------------
# Create folder structure
# ---------------------------------------------------
mkdir -p \
  $APP_DIR/base \
  $APP_DIR/overlays/dev \
  $APP_DIR/overlays/qa \
  $APP_DIR/overlays/prod

# ---------------------------------------------------
# BASE FILES (matches mock-api-service standard)
# ---------------------------------------------------

echo "Creating base manifests..."

cat <<EOF > $APP_DIR/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_LOWER
  labels:
    app: $APP_LOWER
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_LOWER
  template:
    metadata:
      labels:
        app: $APP_LOWER
    spec:
      imagePullSecrets:
        - name: ghcr-creds
      containers:
        - name: $APP_LOWER
          image: ghcr.io/syntaxnow-labs/$APP_LOWER:latest
          ports:
            - containerPort: 9090
EOF

cat <<EOF > $APP_DIR/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: $APP_LOWER
spec:
  type: ClusterIP
  selector:
    app: $APP_LOWER
  ports:
    - port: 80
      targetPort: 9090
EOF

cat <<EOF > $APP_DIR/base/kustomization.yaml
resources:
  - deployment.yaml
  - service.yaml
EOF

# ---------------------------------------------------
# OVERLAYS (DEV + QA + PROD)
# Same structure as mock-api-service dev overlay
# ---------------------------------------------------

echo "Creating overlays (dev, qa, prod)..."

for ENV in dev qa prod; do

  OVERLAY_DIR="$APP_DIR/overlays/$ENV"

  # Domain naming convention
  if [ "$ENV" = "prod" ]; then
    DOMAIN="${APP_LOWER}.syntaxnow.com"
  else
    DOMAIN="${APP_LOWER}-${ENV}.syntaxnow.com"
  fi

  TLS_SECRET="${APP_LOWER}-tls-cert"

  echo "   → Overlay: $ENV ($DOMAIN)"

  # -------------------------------
  # patch-image.yaml (CI updates this)
  # -------------------------------
  cat <<EOF > $OVERLAY_DIR/patch-image.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_LOWER
spec:
  template:
    spec:
      containers:
        - name: $APP_LOWER
          image: "ghcr.io/syntaxnow-labs/$APP_LOWER:$ENV-latest"
EOF

  # -------------------------------
  # values-env.yaml (runtime config placeholder)
  # -------------------------------
  cat <<EOF > $OVERLAY_DIR/values-$ENV.yaml
APP_ENV: $ENV
EOF

  # -------------------------------
  # ingress.yaml (matches your dev ingress style)
  # -------------------------------
  cat <<EOF > $OVERLAY_DIR/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_LOWER-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/acme-http01-edit-in-place: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
      - $DOMAIN
    secretName: $TLS_SECRET
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $APP_LOWER
            port:
              number: 80
EOF

  # -------------------------------
  # kustomization.yaml (configMapGenerator + patch)
  # -------------------------------
  cat <<EOF > $OVERLAY_DIR/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - ingress.yaml

configMapGenerator:
  - name: ${APP_LOWER}-config
    behavior: create
    files:
      - values-$ENV.yaml

patches:
  - path: patch-image.yaml
EOF

done

# ---------------------------------------------------
# Done
# ---------------------------------------------------

echo ""
echo "GitOps scaffold created successfully!"
echo ""
echo "📌 App created at:"
echo "   $APP_DIR"
echo ""
echo "Next steps:"
echo "  git add apps/$APP_LOWER"
echo "  git commit -m \"Add GitOps scaffold for $APP_LOWER\""
echo "  git push"
echo ""
