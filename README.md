# self-hosted-ci-cd

A CI/CD system running on infrastructure I own: GitHub Actions jobs execute in
ephemeral pods on my own AKS cluster, and deployment is a pull-based GitOps loop in
the same cluster.

## Status

| Phase | Scope | Status |
|---|---|---|
| **1a** | CI — Actions jobs on self-hosted ARC runners in AKS → image in GHCR | **done** |
| **1b** | CD — Argo CD deploys that image | not started |
| **2** | Buildkite agents replace the Actions half of CI | not started |

Verified end to end: a push to a feature branch runs nothing, a PR runs tests and
builds the image without publishing, and merging to `master` runs both and publishes
`sha-<short>` to GHCR. Every job executes in an ephemeral pod in the cluster, and
runners scale back to zero when idle.

## How it works today

```
push to feature branch ──> nothing runs

open / update PR ──> `test` ──> `build`   build only, NOT published
                                          (proves the Dockerfile still builds)

merge to master ────> `test` ──> `build`   build AND push
                                          ghcr.io/sliu2200899/self-hosted-ci-cd/sample-app
                                            :sha-<short>  :latest
```

Both run on ephemeral pods in the cluster. Merging a PR *is* the push to `master`.

CI and CD are decoupled on purpose. The only contract between them is a commit in git
naming an image tag — which is why Phase 2 can swap out CI without touching deployment.

## Layout

```
app/                  Python service, tests, Dockerfile
platform/arc/         Helm values for the runner scale set
scripts/              Repeatable install scripts
.github/workflows/    CI definition
doc/                  Documentation
```

## Setting up CI on a fresh cluster

Everything CI needs is either committed here or lives outside the cluster, so a rebuild
after teardown is three commands. **There is no separate CRD step** — the four
`actions.github.com` CRDs ship with the controller chart.

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

# 3. Controller + CRDs + the arc-rdev runner scale set. Idempotent.
./scripts/20-install-arc.sh
```

### Verify before pushing any code

A job queued against a label no runner provides waits forever with no error, so confirm
registration first:

```bash
kubectl -n arc-systems get pods        # controller AND arc-rdev-...-listener, both Running
kubectl get autoscalinglisteners -A
```

and check `arc-rdev` is listed at repo → Settings → Actions → Runners.

> The listener runs in **`arc-systems`**, not `arc-runners`. Only ephemeral runner pods
> appear in `arc-runners`, and only while a job is executing — an empty `arc-runners`
> is the normal idle state, not a fault.

### What does not need redoing

| Thing | Why |
|---|---|
| GHCR package and its public visibility | Lives on GitHub, not in the cluster |
| CI workflow, app, Helm values | Already committed to `master` |
| GitHub-side runner registration | Recreated by the install script |

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
