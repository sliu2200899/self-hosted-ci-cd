# Overview

A CI/CD system where both halves run on infrastructure we own: CI jobs execute in
pods on our own AKS cluster, and CD is a pull-based GitOps loop in the same cluster.

## Phases

| Phase | Scope | Status |
|---|---|---|
| **1a** | CI — GitHub Actions jobs on self-hosted ARC runners in AKS, producing an image in GHCR | done |
| **1b** | CD — Argo CD pulls from git and deploys that image | current |
| **2** | Buildkite agents replace the GitHub Actions half of CI | not started |

## Why the phases split here

CI and CD are deliberately decoupled. The only contract between them is **a commit in
git that names an image tag**. CI's job ends when an image exists in the registry; CD's
job begins when git changes. Neither half calls the other.

That seam is what makes Phase 2 tractable: Buildkite can produce the same commit that
Actions produces, so replacing CI does not touch the deployment path at all.

## Phase 1a data flow

```
push to feature branch ──> nothing runs

open / update PR ──> job `test`  ──> job `build`   (build only, NOT published)
                       pytest          proves the Dockerfile still builds

merge to master ────> job `test`  ──> job `build`   (build AND publish)
                                         ├─ docker buildx build (dind sidecar)
                                         └─ push to GHCR:
                                            ghcr.io/sliu2200899/self-hosted-ci-cd/sample-app
                                              :sha-<short>
                                              :latest
                                              │
                                     job `bump` commits that tag into
                                     deploy/overlays/dev/kustomization.yaml
                                              │
                     ┌────────────────────────┘
                     ▼
             Argo CD (in-cluster) polls git, renders Kustomize,
             applies the diff → Deployment in ns sample-app rolls
```

Merging a PR *is* a push to `master` — that is the trigger, not a separate event.

CI never touches the cluster and holds no cluster credentials. Argo CD never talks to
CI. The **only** thing joining them is a commit that changes an image tag.

## Components

| Component | Where | Purpose |
|---|---|---|
| ARC controller | AKS ns `arc-systems` | Watches GitHub for queued jobs |
| Runner scale set `arc-rdev` | AKS ns `arc-runners` | Ephemeral runner pods, scale 0→3 |
| Sample app | `app/` | FastAPI service; something real to test and build |
| CI workflow | `.github/workflows/ci.yml` | Test on PR, build+push+bump on merge |
| GHCR | github.com | Image registry |
| Argo CD | AKS ns `argocd` | Reconciles git → cluster |
| Deployed app | AKS ns `sample-app` | Deployment (2 replicas) + Service |

## Repository layout

```
app/                  Python service, tests, Dockerfile
deploy/               Kustomize manifests (base + overlays/dev)
platform/arc/         Helm values for the runner scale set
platform/argocd/      The Argo CD Application
scripts/              Repeatable install scripts
.github/workflows/    CI definition
doc/                  This documentation
```

## Read next

1. [Prerequisites](01-prerequisites.md)
2. [The sample app](02-app.md)
3. [ARC self-hosted runners](03-arc-runners.md)
4. [The CI workflow](04-ci-workflow.md)
5. [Verification](05-verification.md)
6. [Runbook](06-runbook.md)
7. [CD with Argo CD](07-argocd.md)
