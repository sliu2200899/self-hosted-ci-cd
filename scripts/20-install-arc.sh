#!/usr/bin/env bash
#
# Install Actions Runner Controller and the `arc-rdev` runner scale set.
#
# Idempotent: uses `helm upgrade --install`, so re-running reconciles rather than
# failing. See doc/03-arc-runners.md for what each piece does.
#
# Usage:
#   export GH_PAT=ghp_xxxxxxxxxxxx     # classic PAT, `repo` scope
#   ./scripts/20-install-arc.sh

set -euo pipefail

ARC_VERSION="${ARC_VERSION:-0.14.2}"
CONTROLLER_NS="${CONTROLLER_NS:-arc-systems}"
RUNNER_NS="${RUNNER_NS:-arc-runners}"
RUNNER_SET_NAME="${RUNNER_SET_NAME:-arc-rdev}"
SECRET_NAME="${SECRET_NAME:-arc-github-token}"

CHART_BASE="oci://ghcr.io/actions/actions-runner-controller-charts"
VALUES_FILE="$(dirname "$0")/../platform/arc/values-runner-set.yaml"

if [[ -z "${GH_PAT:-}" ]]; then
  echo "ERROR: GH_PAT is not set. Create a classic PAT with 'repo' scope and export it." >&2
  exit 1
fi

echo "==> Context: $(kubectl config current-context)"

echo "==> Installing ARC controller ${ARC_VERSION} into ${CONTROLLER_NS}"
helm upgrade --install arc \
  "${CHART_BASE}/gha-runner-scale-set-controller" \
  --version "${ARC_VERSION}" \
  --namespace "${CONTROLLER_NS}" \
  --create-namespace \
  --wait

echo "==> Creating namespace ${RUNNER_NS} and PAT secret ${SECRET_NAME}"
kubectl create namespace "${RUNNER_NS}" --dry-run=client -o yaml | kubectl apply -f -

# Recreate rather than patch so a rotated PAT actually takes effect.
kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${RUNNER_NS}" \
  --from-literal=github_token="${GH_PAT}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing runner scale set ${RUNNER_SET_NAME} into ${RUNNER_NS}"
helm upgrade --install "${RUNNER_SET_NAME}" \
  "${CHART_BASE}/gha-runner-scale-set" \
  --version "${ARC_VERSION}" \
  --namespace "${RUNNER_NS}" \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --wait

echo
echo "==> Done. Verifying:"
kubectl -n "${CONTROLLER_NS}" get pods
kubectl -n "${RUNNER_NS}" get pods
echo
echo "The listener pod above should be Running. Confirm the runner also appears at:"
echo "  https://github.com/sliu2200899/self-hosted-ci-cd/settings/actions/runners"
