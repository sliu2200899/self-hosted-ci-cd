#!/usr/bin/env bash
#
# Install Argo CD. Idempotent: re-running reconciles the manifests.
#
# See doc/07-argocd.md for what this sets up and why.
#
# Usage:
#   ./scripts/10-install-argocd.sh

set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.1}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"

MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Context: $(kubectl config current-context)"
echo "==> Installing Argo CD ${ARGOCD_VERSION} into ${ARGOCD_NS}"

kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -

# Server-side apply is required, not a preference. Client-side apply stores the
# whole manifest in a last-applied-configuration annotation, and the
# applicationsets CRD schema exceeds the 262144-byte annotation limit:
#   "metadata.annotations: Too long: may not be more than 262144 bytes"
kubectl apply --server-side --force-conflicts -n "${ARGOCD_NS}" -f "${MANIFEST}"

echo "==> Waiting for Argo CD to become ready (this pulls several images)"
# The server is the last thing to come up; waiting on it implies the rest.
kubectl -n "${ARGOCD_NS}" rollout status deploy/argocd-repo-server --timeout=5m
kubectl -n "${ARGOCD_NS}" rollout status deploy/argocd-server --timeout=5m

echo
echo "==> Argo CD is up:"
kubectl -n "${ARGOCD_NS}" get pods

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
