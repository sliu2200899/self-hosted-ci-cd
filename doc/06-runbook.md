# Runbook

## Bootstrapping a fresh cluster

Everything is either committed here or lives outside the cluster, so rebuilding after a
teardown is a handful of scripts. **There is no separate CRD step** — the four
`actions.github.com` CRDs ship with the ARC controller chart, and Argo CD's ship with
its own.

```bash
# 1. Point kubectl at the new cluster. Mandatory after any recreate: the AKS API
#    server FQDN contains a random suffix that changes, so the old context is dead.
az aks get-credentials -g wus3-rdev-rg -n rdev-aks-wus3-1 --overwrite-existing
kubectl get nodes          # expect Ready nodes before continuing

# 2. Reuse the existing PAT if it has not expired, else mint a new one
#    (classic, `repo` scope).
export GH_PAT=ghp_xxxxxxxx

# 3. CI — ARC controller + CRDs + the arc-rdev runner scale set. Idempotent.
./scripts/20-install-arc.sh

# 4. CD — Argo CD via Helm, its repo credentials, then the Application.
./scripts/10-install-argocd.sh
./scripts/11-argocd-repo-key.sh
./scripts/30-bootstrap-app.sh
```

CI and CD are independent, so the order of steps 3 and 4 does not matter.

### The deploy key usually needs no GitHub action

`11-argocd-repo-key.sh` reuses the key at `~/.ssh/argocd-self-hosted-ci-cd` if it
exists and only recreates the in-cluster Secret. The private key lives on your machine
and its public half is already registered on the repo, so **a new cluster does not need
a new deploy key**. The script generates a keypair — and prints one to add — only when
that file is missing, e.g. on a new laptop.

### Verify before pushing any code

A job queued against a label no runner provides waits forever with no error, so confirm
registration first:

```bash
kubectl -n arc-systems get pods    # controller + arc-rdev-...-listener, both Running
kubectl get autoscalinglisteners -A
```

and check `arc-rdev` appears at repo → Settings → Actions → Runners.

For CD:

```bash
kubectl -n argocd get application sample-app    # expect Synced / Healthy
kubectl -n sample-app get deploy,pods
```

### What does not need redoing

| Thing | Why |
|---|---|
| GHCR package + its public visibility | Lives on GitHub, not in the cluster |
| CI workflow, app, manifests, Helm values | Already committed to `master` |
| GitHub-side runner registration | Recreated by the install script |
| The GitHub deploy key | Still valid; only the in-cluster Secret is recreated |
| Knowing which image version to deploy | Pinned in `deploy/overlays/dev`, so Argo CD restores the exact previous state from git |

That last row is the point of GitOps: the cluster is disposable because git already
describes what belongs on it.

The listener pod runs in **`arc-systems`** (the controller's namespace), not
`arc-runners` — only the ephemeral runner pods appear in `arc-runners`, and only while
a job is executing. An empty `arc-runners` is the normal idle state, not a fault.

## Quick reference

```bash
# Cluster access
az aks get-credentials -g wus3-rdev-rg -n rdev-aks-wus3-1 --overwrite-existing

# What is running
kubectl -n arc-systems get pods
kubectl -n arc-runners get pods

# Listener logs (the component that talks to GitHub)
kubectl -n arc-runners logs -l app.kubernetes.io/component=runner-scale-set-listener --tail=100

# Controller logs
kubectl -n arc-systems logs -l app.kubernetes.io/name=gha-rs-controller --tail=100

# Reinstall / reconcile everything
export GH_PAT=ghp_xxxx && ./scripts/20-install-arc.sh

# --- Argo CD ---
kubectl -n argocd get application sample-app
kubectl -n sample-app get deploy,pods,svc

# Why is a sync failing?
kubectl -n argocd get application sample-app -o jsonpath='{.status.conditions}'
kubectl -n argocd logs deploy/argocd-repo-server --tail=50

# Force a sync instead of waiting ~3 minutes
kubectl -n argocd patch application sample-app --type merge \
  -p '{"operation":{"sync":{"revision":"master"}}}'

# UI
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## Troubleshooting

### Job stuck in "Queued" forever

The most common failure. GitHub has a job for label `arc-rdev` and nothing is claiming it.

1. Is the listener running? `kubectl -n arc-runners get pods`
2. Does GitHub see the runner? Settings → Actions → Runners
3. Does `runs-on:` match the Helm release name exactly? The release name **is** the
   label — a rename breaks every workflow silently.
4. Check listener logs for 401/403 — usually an expired PAT or missing `repo` scope.

### Listener pod in CrashLoopBackOff

Almost always credentials.

```bash
kubectl -n arc-runners logs -l app.kubernetes.io/component=runner-scale-set-listener --tail=50
```

- `401 Unauthorized` → PAT is invalid or expired.
- `404 Not Found` → `githubConfigUrl` is wrong, or the PAT cannot see a private repo.

Rotate the PAT and re-run the install script; it recreates the Secret rather than
patching it, so a new token actually takes effect.

### `docker: command not found` in a job

`containerMode.type: dind` is not applied. Confirm the runner pod has two containers:

```bash
kubectl -n arc-runners get pod <runner-pod> -o jsonpath='{.spec.containers[*].name}'
```

Expect `runner` and `dind`.

### Runner pod stuck in Pending

No node has room. These are 2-vCPU nodes.

```bash
kubectl -n arc-runners describe pod <runner-pod> | tail -20
kubectl get nodes
```

The autoscaler should add a node within a couple of minutes (the `rdev` pool scales to
10). If it does not, check pool limits:

```bash
az aks nodepool list -g wus3-rdev-rg --cluster-name rdev-aks-wus3-1 -o table
```

### Push to GHCR denied

- The job must declare `permissions: packages: write`.
- The image name must be lowercase — `${{ github.repository }}` already is.

### `kubectl` says `no such host`

Stale kubeconfig. The AKS API server FQDN contains a random suffix that changes when a
cluster is recreated, so a deleted-and-recreated cluster leaves an unreachable context.

```bash
az aks get-credentials -g wus3-rdev-rg -n rdev-aks-wus3-1 --overwrite-existing
```

## Rotating the PAT

```bash
export GH_PAT=<new token>
./scripts/20-install-arc.sh
kubectl -n arc-runners rollout restart deploy -l app.kubernetes.io/component=runner-scale-set-listener
```

## Tearing ARC down

```bash
helm uninstall arc-rdev -n arc-runners
helm uninstall arc -n arc-systems
kubectl delete ns arc-runners arc-systems
```

Removes all runners. Nothing in GHCR or GitHub is affected.

## Cost control

Runners scale to zero when idle, so cost is only incurred during builds. To check
whether nodes are being held:

```bash
kubectl get nodes
kubectl -n arc-runners get pods
```

If runner pods linger with no active jobs, restart the listener.
