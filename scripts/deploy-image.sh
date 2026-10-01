#!/bin/bash
set -e
set -o pipefail

# ============================================================
# deploy-image.sh - Deploy to Azure AKS
# Eclipse Cargo Tracker - Jakarta EE Application
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$PROJECT_ROOT/kubernetes"
APP_NAME="cargo-tracker"
NAMESPACE="cargo-tracker"

echo "============================================================"
echo "  Deploy to Azure AKS - Eclipse Cargo Tracker"
echo "============================================================"
echo ""

# ---- Prompt for Azure details ----
read -rp "Enter Azure Resource Group name: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then
  echo "ERROR: Resource group cannot be empty."
  exit 1
fi

read -rp "Enter AKS Cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: AKS cluster name cannot be empty."
  exit 1
fi

read -rp "Enter full Docker image URI (e.g., myregistry.azurecr.io/cargo-tracker:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Image URI cannot be empty."
  exit 1
fi

# ---- Prompt for application-specific environment variables ----
echo ""
echo "---- Application Configuration ----"
echo "Press Enter to skip optional values and use defaults."
echo ""

read -rp "Enter GRAPH_TRAVERSAL_URL [http://localhost:8080/rest/graph-traversal/shortest-path]: " GRAPH_TRAVERSAL_URL_INPUT
GRAPH_TRAVERSAL_URL="${GRAPH_TRAVERSAL_URL_INPUT:-http://localhost:8080/rest/graph-traversal/shortest-path}"

# ---- Configure kubectl for AKS ----
echo ""
echo "Configuring kubectl for AKS cluster: $CLUSTER_NAME in resource group: $RESOURCE_GROUP"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo ""
echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to AKS cluster."; exit 1; }

# ---- Prepare manifest copies ----
echo ""
echo "Preparing Kubernetes manifests..."
DEPLOY_DIR="$(mktemp -d)"
cp -r "$K8S_DIR/"* "$DEPLOY_DIR/"

# ---- Replace placeholders in manifests ----
echo "Replacing placeholders in manifests..."
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{GRAPH_TRAVERSAL_URL}}|${GRAPH_TRAVERSAL_URL}|g" "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{NAMESPACE}}|${NAMESPACE}|g" "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{NAMESPACE}}|${NAMESPACE}|g" "$DEPLOY_DIR/service.yaml"
sed -i "s|{{NAMESPACE}}|${NAMESPACE}|g" "$DEPLOY_DIR/ingress.yaml"

# ---- Apply Kubernetes manifests ----
echo ""
echo "Applying Kubernetes manifests..."

echo "  [1/4] Applying namespace..."
kubectl apply -f "$DEPLOY_DIR/namespace.yaml"

echo "  [2/4] Applying deployment..."
kubectl apply -f "$DEPLOY_DIR/deployment.yaml"

echo "  [3/4] Applying service..."
kubectl apply -f "$DEPLOY_DIR/service.yaml"

echo "  [4/4] Applying ingress..."
kubectl apply -f "$DEPLOY_DIR/ingress.yaml"

# ---- Wait for rollout ----
echo ""
echo "Waiting for deployment rollout to complete..."
kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s

# ---- Verify resources ----
echo ""
echo "Verifying deployed resources..."
kubectl get pods,svc,ingress -n "$NAMESPACE"

# ---- Display application URL ----
echo ""
echo "Fetching application ingress URL..."
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
INGRESS_IP=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

echo ""
echo "============================================================"
echo "  Deployment completed successfully!"
echo ""
if [ -n "$INGRESS_HOST" ]; then
  echo "  Application URL: http://$INGRESS_HOST"
fi
if [ -n "$INGRESS_IP" ]; then
  echo "  Ingress IP:      $INGRESS_IP"
fi
echo ""
echo "  Namespace:  $NAMESPACE"
echo "  Image:      $IMAGE_URI"
echo "============================================================"
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"

# ---- Cleanup temp dir ----
rm -rf "$DEPLOY_DIR"
