# CD with Argo CD

Argo CD is the deployment half. It runs **in** the cluster and **pulls** from git —
nothing ever pushes to the cluster from outside.

Pinned to **v3.5.1**.

## Push CD vs pull CD

The familiar model is push: CI finishes, then runs `kubectl apply` against the cluster.
That requires CI to hold cluster-admin credentials, which is the part that ages badly —
a token with write access to production, sitting in a CI system that also executes
whatever code lands in a pull request.

Pull CD inverts it:

```
CI ──> writes an image tag into git ──┐
                                      │  (CI never touches the cluster,
                                      │   and holds no cluster credentials)
                                      ▼
                            Argo CD, inside the cluster,
                            reads git and applies changes
```

Argo CD needs only **read** access to one repository. CI needs none. The cluster's
API server is never exposed to CI at all.

## The loop

```
merge to master
   └─> CI: test → build → push image → bump job commits the new tag
                                             │
                                             ▼
                                    deploy/overlays/dev/kustomization.yaml
                                       images[0].newTag: sha-<short>
                                             │
                        Argo CD polls (~3 min) and sees the commit
                                             │
                                             ▼
                        renders Kustomize, diffs against the cluster,
                        applies the difference → Deployment rolls
```

## Components

| Piece | Where | Purpose |
|---|---|---|
| Argo CD | ns `argocd` | The controller set that reconciles git → cluster |
| `Application` `sample-app` | ns `argocd` | Points at `deploy/overlays/dev` on `master` |
| Deployed workload | ns `sample-app` | Deployment (2 replicas) + ClusterIP Service |
| Repo credentials | Secret in `argocd` | Read-only SSH deploy key |

## Installation

```bash
./scripts/10-install-argocd.sh     # Argo CD itself
./scripts/11-argocd-repo-key.sh    # deploy key — prints a public key to add on GitHub
./scripts/30-bootstrap-app.sh      # create the Application
```

### Why server-side apply

`10-install-argocd.sh` uses `kubectl apply --server-side`. This is required, not a
preference — client-side apply stores the entire manifest in a
`last-applied-configuration` annotation, and the `applicationsets` CRD schema exceeds
Kubernetes' annotation limit:

```
metadata.annotations: Too long: may not be more than 262144 bytes
```

Server-side apply does not use that annotation, so the install succeeds.

## Repository credentials

The repo is private, so Argo CD cannot clone it anonymously. It authenticates with a
**read-only SSH deploy key**.

A deploy key is scoped to exactly one repository and, left read-only, cannot write
anything. Compare with a classic `repo`-scoped PAT, which grants read **and write** to
every repository you own — far more authority than a component that only ever clones.

`11-argocd-repo-key.sh` generates the key at `~/.ssh/argocd-self-hosted-ci-cd`,
deliberately **outside the repo**, so it cannot be committed by accident. It then
creates a Secret in `argocd` labelled:

```yaml
argocd.argoproj.io/secret-type: repository
```

That label is what makes Argo CD treat the Secret as repository credentials.

> **The `url` in the Secret must match the Application's `repoURL` exactly.** If one
> says `git@github.com:...` and the other `https://github.com/...`, Argo CD never
> associates the credentials with the repo and every sync fails with a permission
> error — despite the key being perfectly valid. This is the most common Argo CD
> misconfiguration.

The public half must be added at repo → Settings → Deploy keys, **without** write access.

## The Application

`platform/argocd/application.yaml`:

| Field | Value | Why |
|---|---|---|
| `source.repoURL` | `git@github.com:...` | SSH, to match the deploy key |
| `source.targetRevision` | `master` | Track the default branch |
| `source.path` | `deploy/overlays/dev` | The Kustomize overlay to render |
| `destination.namespace` | `sample-app` | Workloads land here, not in `argocd` |
| `syncPolicy.automated.prune` | `true` | Resources deleted from git are deleted from the cluster |
| `syncPolicy.automated.selfHeal` | `true` | Manual `kubectl` edits are reverted |
| `syncOptions` | `CreateNamespace=true` | Argo CD creates `sample-app` itself |
| `finalizers` | `resources-finalizer...` | Deleting the Application deletes what it deployed, rather than orphaning it |

**`selfHeal` is what makes git the source of truth** rather than merely the starting
point. Without it, git describes the intended state and anyone with `kubectl` can
silently diverge from it. With it, the cluster is continuously corrected back.

## The CI → CD contract

The entire interface between the two halves is one field:

```yaml
# deploy/overlays/dev/kustomization.yaml
images:
  - name: ghcr.io/sliu2200899/self-hosted-ci-cd/sample-app
    newTag: sha-55f6609
```

CI's `bump` job rewrites `newTag` with `kustomize edit set image` and commits. Argo CD
reads it. Neither half knows the other exists.

That seam is what makes Phase 2 tractable: Buildkite can produce the same commit, and
nothing under `deploy/` changes.

### Always an immutable tag

The overlay pins `sha-<short-sha>`, never `latest`. A mutable tag makes "what is
actually running?" unanswerable, and it breaks rollback — with an immutable tag,
rolling back is just reverting the commit that changed this line.

### Why this does not loop forever

The `bump` job commits to the same repo that triggers CI. Two independent guards stop
the recursion:

1. **Commits pushed with `GITHUB_TOKEN` do not trigger workflow runs.** This is
   deliberate GitHub behaviour and is the primary guard.
2. **The `push` trigger's `paths` filter** covers `app/**` and the workflow file only.
   The bump only touches `deploy/**`, so it would not match even if guard 1 vanished.

## Accessing the UI

Argo CD is not exposed publicly — no LoadBalancer, no Ingress, no public IP.

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
open https://localhost:8080     # self-signed cert; the browser warning is expected
```

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Change it, then delete that Secret — it is a bootstrap artifact, not a store:

```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

## Sync timing

Argo CD polls git roughly every **3 minutes**, so a deployment lands within about that
long after the bump commit. To skip the wait:

```bash
kubectl -n argocd patch application sample-app --type merge \
  -p '{"operation":{"sync":{"revision":"master"}}}'
```

A webhook from GitHub would make this instant, but that would require exposing Argo CD
to the internet — the same trade-off ARC's listener avoids by polling outbound.
