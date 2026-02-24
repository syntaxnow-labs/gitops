#!/bin/bash
set -e

# ===================================================
# GitOps App Bootstrap Script
#
# Purpose:
#   - Creates standard GitOps folder structure
#   - Generates base + overlays (dev/qa/prod)
#   - Optionally registers app into cluster env lists
#
# Usage:
#   ./scripts/bootstrap-app.sh <app-name> <app-type> <deploy-envs>
#
# Examples:
#   Scaffold only:
#     ./scripts/bootstrap-app.sh oneplatform frontend ""
#
#   Scaffold + enable in dev + prod:
#     ./scripts/bootstrap-app.sh oneplatform frontend "dev,prod"
# ===================================================

APP_NAME=$1
APP_TYPE=$2
DEPLOY_ENVS=$3
REQUIRES_SECRET=$4

# ---------------------------------------------------
# Step 0: Validate Inputs
# ---------------------------------------------------
if [ -z "$APP_NAME" ]; then
	echo "Missing app name"
	echo "Usage: ./scripts/bootstrap-app.sh <app-name> <backend|frontend> <deploy-envs>"
	exit 1
fi

# Default type = backend
if [ -z "$APP_TYPE" ]; then
	APP_TYPE="backend"
fi

if [[ "$APP_TYPE" != "backend" && "$APP_TYPE" != "frontend" ]]; then
	echo "Invalid app type: $APP_TYPE"
	echo "Allowed values: backend | frontend"
	exit 1
fi

if [ -z "$REQUIRES_SECRET" ]; then
	REQUIRES_SECRET="false"
fi

# Force lowercase (Kubernetes + DNS safe)
APP_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')
APP_DIR="apps/$APP_LOWER"

# Prevent overwriting existing apps
if [ -d "$APP_DIR" ]; then
	echo "[Error] App '$APP_LOWER' already exists at: $APP_DIR"
	exit 1
fi

# Determine container port
if [ "$APP_TYPE" = "frontend" ]; then
	CONTAINER_PORT=80
	REQUIRES_SECRET="false"
else
	CONTAINER_PORT=9090
fi

echo ""
echo "🚀 Bootstrapping GitOps App"
echo "-----------------------------------"
echo "App Name     : $APP_LOWER"
echo "App Type     : $APP_TYPE"
echo "ContainerPort: $CONTAINER_PORT"
echo "Deploy Envs  : ${DEPLOY_ENVS:-none}"
echo "-----------------------------------"
echo ""

# ---------------------------------------------------
#  Step 1: Create Folder Structure
# ---------------------------------------------------
mkdir -p \
	$APP_DIR/base \
	$APP_DIR/overlays/dev \
	$APP_DIR/overlays/qa \
	$APP_DIR/overlays/prod

# ---------------------------------------------------
#  Step 2: Generate BASE Manifests
# ---------------------------------------------------

echo "Creating base Kubernetes manifests..."

if [ "$REQUIRES_SECRET" = "true" ]; then
	SECRET_BLOCK="            - secretRef:
                name: ${APP_LOWER}-secrets"
else
	SECRET_BLOCK=""
fi

cat <<EOF >$APP_DIR/base/deployment.yaml
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
            - containerPort: $CONTAINER_PORT
          envFrom:
            - configMapRef:
                name: ${APP_LOWER}-config
$SECRET_BLOCK
EOF

cat <<EOF >$APP_DIR/base/service.yaml
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
      targetPort: $CONTAINER_PORT
EOF

cat <<EOF >$APP_DIR/base/kustomization.yaml
resources:
  - deployment.yaml
  - service.yaml
EOF

# ---------------------------------------------------
# Step 3: Generate OVERLAYS (dev/qa/prod)
# ---------------------------------------------------

echo "Creating overlays (dev, qa, prod)..."

for ENV in dev qa prod; do

	OVERLAY_DIR="$APP_DIR/overlays/$ENV"

	NAMESPACE="apps-$ENV"

	# Domain naming convention
	if [ "$ENV" = "prod" ]; then
		DOMAIN="${APP_LOWER}.syntaxnow.com"
	else
		DOMAIN="${APP_LOWER}-${ENV}.syntaxnow.com"
	fi

	TLS_SECRET="${APP_LOWER}-${ENV}-tls-cert"

	echo "Overlay  : $ENV"
	echo "Namespace: $NAMESPACE"
	echo "Domain   : $DOMAIN"

	# -------------------------------
	# Patch image file (updated by CI later)
	# -------------------------------
	cat <<EOF >$OVERLAY_DIR/patch-image.yaml
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
	cat <<EOF >$OVERLAY_DIR/values-$ENV.env
APP_NAME=$APP_LOWER
APP_ENV=$ENV
SPRING_PROFILES_ACTIVE=$ENV
EOF

	# -------------------------------
	# ExternalSecret
	# -------------------------------
	if [ "$REQUIRES_SECRET" = "true" ]; then
		cat <<EOF >$OVERLAY_DIR/secrets.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ${APP_LOWER}-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: oci-vault-store
    kind: ClusterSecretStore
  target:
    name: ${APP_LOWER}-secrets
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: ${APP_LOWER}-${ENV}
EOF
	fi

	# -------------------------------
	# ingress.yaml (matches your dev ingress style)
	# -------------------------------
	cat <<EOF >$OVERLAY_DIR/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_LOWER-ingress
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

	if [ "$REQUIRES_SECRET" = "true" ]; then
		SECRET_RESOURCE="  - secrets.yaml"
	else
		SECRET_RESOURCE=""
	fi

	cat <<EOF >$OVERLAY_DIR/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - ../../base
$SECRET_RESOURCE
  - ingress.yaml

configMapGenerator:
  - name: ${APP_LOWER}-config
    behavior: create
    envs:
      - values-$ENV.env

patches:
  - path: patch-image.yaml
EOF

done

# ---------------------------------------------------
# Step 4: Optional Cluster Registration
# ---------------------------------------------------
if [ -n "$DEPLOY_ENVS" ]; then
	echo ""
	echo "Registering app into cluster environments: $DEPLOY_ENVS"

	for ENV in $(echo "$DEPLOY_ENVS" | tr "," " "); do

		if [[ "$ENV" != "dev" && "$ENV" != "qa" && "$ENV" != "prod" ]]; then
			echo "Invalid environment: $ENV (allowed: dev, qa, prod)"
			exit 1
		fi

		FILE="clusters/vm-0656/apps-$ENV.yaml"
		echo "Enabling $APP_LOWER in $ENV ($FILE)"

		# Ensure file exists
		[ -f "$FILE" ] || echo "[]" >"$FILE"

		# Skip duplicates
		if grep -q "app: $APP_LOWER" "$FILE"; then
			echo "Already enabled"
			continue
		fi

		if grep -q "^\[\]$" "$FILE"; then
			echo "- app: $APP_LOWER" >"$FILE"
		else
			# Ensure file ends with a newline before appending
			sed -i -e '$a\' "$FILE"
			echo "- app: $APP_LOWER" >>"$FILE"
		fi

	done
else
	echo "No deploy environments selected → scaffold only (not deployed yet)."
fi

# ---------------------------------------------------
# Done
# ---------------------------------------------------

echo ""
echo "GitOps scaffold created successfully!"
echo "-----------------------------------"
echo "📌 App created at:  $APP_DIR"
echo ""
echo "Next steps:"
echo "  git add apps/$APP_LOWER"
echo "  git add clusters/vm-0656/apps-*.yaml"
echo "  git commit -m \"Add GitOps scaffold for $APP_LOWER\""
echo "  git push"
echo "-----------------------------------"
echo ""
