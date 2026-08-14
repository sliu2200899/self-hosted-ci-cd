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

## Getting started

```bash
brew install helm
az aks get-credentials -g wus3-rdev-rg -n rdev-aks-wus3-1 --overwrite-existing

export GH_PAT=<classic PAT with repo scope>
./scripts/20-install-arc.sh
```

Then follow [doc/05-verification.md](doc/05-verification.md).

## Documentation

- [Overview](doc/00-overview.md) — architecture and phases
- [Prerequisites](doc/01-prerequisites.md) — cluster facts, local tools
- [The sample app](doc/02-app.md)
- [ARC self-hosted runners](doc/03-arc-runners.md)
- [The CI workflow](doc/04-ci-workflow.md)
- [Verification](doc/05-verification.md) — the PR round trip
- [Runbook](doc/06-runbook.md) — troubleshooting
