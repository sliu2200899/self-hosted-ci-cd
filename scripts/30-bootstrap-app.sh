#!/usr/bin/env bash
#
# Create the sample-app Argo CD Application and wait for it to converge.
#
# This is the only manual step that points Argo CD at git. From here on,
# deployments happen because commits happen — never because someone ran kubectl.
#
# Usage:
#   ./scripts/30-bootstrap-app.sh

set -euo pipefail

ARGOCD_NS="${ARGOCD_NS:-argocd}"
APP_NAME="${APP_NAME:-sample-app}"
APP_NS="${APP_NS:-sample-app}"

MANIFEST="$(dirname "$0")/../platform/argocd/application.yaml"

echo "==> Applying Application from ${MANIFEST}"
kubectl apply -f "${MANIFEST}"

echo "==> Waiting for the first sync (Argo CD must clone, render, and apply)"
for i in $(seq 1 60); do
  sync=$(kubectl -n "${ARGOCD_NS}" get application "${APP_NAME}" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n "${ARGOCD_NS}" get application "${APP_NAME}" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  echo "    [${i}] sync=${sync:-<none>} health=${health:-<none>}"
  if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
    echo "==> Synced and Healthy"
    break
  fi
  sleep 5
done

echo
kubectl -n "${ARGOCD_NS}" get application "${APP_NAME}"
echo
kubectl -n "${APP_NS}" get deploy,pods,svc 2>/dev/null || echo "namespace ${APP_NS} not created yet"

cat <<'EOF'

If sync is stuck, the usual cause is the deploy key:

  kubectl -n argocd get application sample-app -o jsonpath='{.status.conditions}'
  kubectl -n argocd logs deploy/argocd-repo-server --tail=50

A permission/authentication error means the public key was never added to the
repo, or the Secret's `url` does not exactly match the Application's repoURL.
EOF
