# self-hosted-ci-cd

A CI/CD system running on infrastructure I own: GitHub Actions jobs execute in
ephemeral pods on my own AKS cluster, and deployment is a pull-based GitOps loop in
the same cluster.

## Status

| Phase | Scope | Status |
|---|---|---|
| **1a** | CI — Actions jobs on self-hosted ARC runners in AKS → image in GHCR | **done** |
| **1b** | CD — Argo CD deploys that image | **done** |
| **2** | Buildkite agents replace the Actions half of CI | not started |

## How it works

```
push to feature branch ──> nothing runs

open / update PR ──> `test` ──> `build`   build only, NOT published
                                          (proves the Dockerfile still builds)

merge to master ────> `test` ──> `build` ──> `bump`
                                    │           └─ commits the new tag into
                                    │              deploy/overlays/dev/
                                    └─ pushes ghcr.io/.../sample-app:sha-<short>
                                                          │
                        Argo CD (in-cluster) polls git ───┘
                              └─> rolls the Deployment in ns sample-app
```

Every CI job runs in an ephemeral pod in the cluster; runners scale to zero when idle.
Merging a PR *is* the push to `master`.

**CI and CD are decoupled on purpose.** CI never touches the cluster and holds no
cluster credentials; Argo CD never talks to CI. The only contract between them is a
commit naming an image tag — which is why Phase 2 can swap out CI without touching
anything under `deploy/`.

## Layout

```
app/                  Python service, tests, Dockerfile
deploy/               Kustomize manifests (base + overlays/dev)
platform/arc/         Helm values for the runner scale set
platform/argocd/      The Argo CD Application
scripts/              Repeatable install scripts
.github/workflows/    CI definition
doc/                  Documentation
```

## Setting up on a fresh cluster

Everything is either committed here or lives outside the cluster, so a rebuild after
teardown is a handful of scripts. **There is no separate CRD step** — the four
`actions.github.com` CRDs ship with the ARC controller chart, and Argo CD's ship with
its own.

```bash
# 0. Once per machine
brew install helm

# 1. Point kubectl at the cluster. Mandatory after any recreate: the AKS API server
#    FQDN contains a random suffix that changes, so the previous context is dead
#    and fails with "no such host".
az aks get-credentials -g wus3-rdev-rg -n rdev-aks-wus3-1 --overwrite-existing
kubectl get nodes                      # expect Ready nodes before continuing

# 2. Reuse the existing PAT if it has not expired, else mint a new one:
#    GitHub → Settings → Developer settings → Tokens (classic), scope `repo`.
export GH_PAT=ghp_xxxxxxxx

# 3. CI: controller + CRDs + the arc-rdev runner scale set. Idempotent.
./scripts/20-install-arc.sh

# 4. CD: Argo CD via Helm, its read-only deploy key, and the Application.
#    Independent of step 3 — order does not matter.
./scripts/10-install-argocd.sh
./scripts/11-argocd-repo-key.sh
./scripts/30-bootstrap-app.sh
```

`11-argocd-repo-key.sh` reuses the key at `~/.ssh/argocd-self-hosted-ci-cd` if present
and only recreates the in-cluster Secret, so **a new cluster needs no new deploy key**.
It generates one — and prints a public key to add at Settings → Deploy keys — only when
that file is missing.

### Verify before pushing any code

A job queued against a label no runner provides waits forever with no error, so confirm
registration first:

```bash
kubectl -n arc-systems get pods        # controller AND arc-rdev-...-listener, both Running
kubectl get autoscalinglisteners -A
```

and check `arc-rdev` is listed at repo → Settings → Actions → Runners. For CD:

```bash
kubectl -n argocd get application sample-app    # expect Synced / Healthy
kubectl -n sample-app get deploy,pods
```

> The listener runs in **`arc-systems`**, not `arc-runners`. Only ephemeral runner pods
> appear in `arc-runners`, and only while a job is executing — an empty `arc-runners`
> is the normal idle state, not a fault.

### What does not need redoing

| Thing | Why |
|---|---|
| GHCR package and its public visibility | Lives on GitHub, not in the cluster |
| CI workflow, app, manifests, Helm values | Already committed to `master` |
| GitHub-side runner registration | Recreated by the install script |
| The GitHub deploy key | Still valid; only the in-cluster Secret is recreated |
| Knowing which image version to deploy | Pinned in `deploy/overlays/dev`, so Argo CD restores the exact previous state from git |

Then follow [doc/05-verification.md](doc/05-verification.md) for the PR round trip, or
[doc/06-runbook.md](doc/06-runbook.md) when something misbehaves.

## Documentation

- [Overview](doc/00-overview.md) — architecture and phases
- [Prerequisites](doc/01-prerequisites.md) — cluster facts, local tools
- [The sample app](doc/02-app.md)
- [ARC self-hosted runners](doc/03-arc-runners.md)
- [The CI workflow](doc/04-ci-workflow.md)
- [Verification](doc/05-verification.md) — the PR round trip
- [Runbook](doc/06-runbook.md) — troubleshooting
- [CD with Argo CD](doc/07-argocd.md) — the GitOps loop
