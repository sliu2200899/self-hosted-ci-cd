#!/usr/bin/env bash
#
# Give Argo CD a read-only SSH deploy key so it can clone this private repo.
#
# A deploy key is scoped to exactly one repository and, left read-only, cannot
# write anything — considerably less authority to leave sitting in a cluster
# than a `repo`-scoped PAT, which grants read/write to every repo you own.
#
# The private key is generated OUTSIDE the repo (~/.ssh) so it can never be
# committed by accident. Idempotent: an existing key is reused.
#
# Usage:
#   ./scripts/11-argocd-repo-key.sh

set -euo pipefail

ARGOCD_NS="${ARGOCD_NS:-argocd}"
REPO_URL="${REPO_URL:-git@github.com:sliu2200899/self-hosted-ci-cd.git}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/argocd-self-hosted-ci-cd}"
SECRET_NAME="${SECRET_NAME:-repo-self-hosted-ci-cd}"

if [[ ! -f "${KEY_PATH}" ]]; then
  echo "==> Generating deploy key at ${KEY_PATH}"
  ssh-keygen -t ed25519 -N "" -C "argocd@self-hosted-ci-cd" -f "${KEY_PATH}"
else
  echo "==> Reusing existing key at ${KEY_PATH}"
fi

echo "==> Creating repository Secret ${SECRET_NAME} in ${ARGOCD_NS}"
# The label is what makes Argo CD treat this Secret as repository credentials.
# `url` must match the Application's repoURL EXACTLY, or the credentials are
# never associated with the repo and clones fail with a permission error.
kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${ARGOCD_NS}" \
  --from-literal=type=git \
  --from-literal=url="${REPO_URL}" \
  --from-file=sshPrivateKey="${KEY_PATH}" \
  --dry-run=client -o yaml |
  kubectl label --local -f - \
    argocd.argoproj.io/secret-type=repository \
    --dry-run=client -o yaml |
  kubectl apply -f -

echo
echo "=============================================================================="
echo " ACTION REQUIRED — add this PUBLIC key as a deploy key on the repo"
echo
echo "   https://github.com/sliu2200899/self-hosted-ci-cd/settings/keys/new"
echo
echo "   Title:        argocd"
echo "   Allow write:  NO  (leave unchecked — Argo CD only ever reads)"
echo "   Key:"
echo
cat "${KEY_PATH}.pub"
echo
echo "=============================================================================="
echo
echo "Then run ./scripts/30-bootstrap-app.sh"
