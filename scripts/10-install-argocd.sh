#!/usr/bin/env bash
#
# Install Argo CD via Helm. Idempotent: re-running reconciles the release.
#
# Helm rather than the raw manifests, to match how ARC is installed and so
# configuration lives in a values file instead of post-hoc kubectl patches.
#
# See doc/07-argocd.md for what this sets up and why.
#
# Usage:
#   ./scripts/10-install-argocd.sh

set -euo pipefail

# Chart version, NOT app version. Chart 10.3.3 ships Argo CD v3.5.1.
CHART_VERSION="${CHART_VERSION:-10.3.3}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
RELEASE="${RELEASE:-argocd}"

VALUES_FILE="$(dirname "$0")/../platform/argocd/values.yaml"

echo "==> Context: $(kubectl config current-context)"

echo "==> Adding the argo Helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

echo "==> Installing argo-cd chart ${CHART_VERSION} into ${ARGOCD_NS}"
helm upgrade --install "${RELEASE}" argo/argo-cd \
  --version "${CHART_VERSION}" \
  --namespace "${ARGOCD_NS}" \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --wait --timeout 10m

echo
echo "==> Argo CD is up:"
kubectl -n "${ARGOCD_NS}" get pods
echo
helm list -n "${ARGOCD_NS}"

cat <<'EOF'

Next:
  1. ./scripts/11-argocd-repo-key.sh    # deploy key so Argo CD can clone this repo
  2. ./scripts/30-bootstrap-app.sh      # create the sample-app Application

To reach the UI:
  kubectl -n argocd port-forward svc/argocd-server 8080:443
  open https://localhost:8080          # self-signed cert; expect a browser warning

Initial admin password:
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo

Change that password, then delete the Secret holding it:
  kubectl -n argocd delete secret argocd-initial-admin-secret
EOF
