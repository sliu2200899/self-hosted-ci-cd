# ARC self-hosted runners

Actions Runner Controller (ARC) runs GitHub Actions jobs as ephemeral pods in our AKS
cluster. Pinned to **gha-runner-scale-set 0.14.2**.

## How it works

```
GitHub queues a job for label `arc-rdev`
        │
        ▼
listener pod (ns arc-runners) is long-lived, polls GitHub
        │  sees a queued job
        ▼
ARC controller (ns arc-systems) creates an ephemeral runner pod
        │
        ▼
runner pod ──┬── runner container   (executes the workflow steps)
             └── dind sidecar       (provides /var/run/docker.sock)
        │  job finishes
        ▼
pod is destroyed — every job gets a clean machine
```

Runners are **ephemeral**: one pod per job, destroyed afterwards. There is no state to
leak between builds, and no runner to patch.

## Two namespaces

| Namespace | Contains |
|---|---|
| `arc-systems` | The controller — one deployment, watches all scale sets |
| `arc-runners` | The listener pod and the ephemeral runner pods |

## The PAT

Runner registration needs a **classic PAT with `repo` scope**.

Create it at **GitHub → Settings → Developer settings → Personal access tokens →
Tokens (classic)**. `repo` scope is sufficient for a repository-scoped runner set.

> **A GitHub App is the production-grade alternative** — higher API rate limits and not
> tied to one person's account, so the runners keep working after that person leaves.
> A PAT was chosen here for a single personal repo because it has far fewer moving
> parts. Worth upgrading before this is shared.

The PAT is stored as the Secret `arc-github-token` in `arc-runners`, key `github_token`.

## Installation

```bash
export GH_PAT=ghp_xxxxxxxxxxxx
./scripts/20-install-arc.sh
```

The script is idempotent (`helm upgrade --install`), so re-running it reconciles rather
than failing. It:

1. installs the controller into `arc-systems`,
2. creates `arc-runners` and the PAT Secret,
3. installs the runner scale set `arc-rdev` from `platform/arc/values-runner-set.yaml`.

## Configuration choices

From `platform/arc/values-runner-set.yaml`:

| Setting | Value | Why |
|---|---|---|
| `githubConfigUrl` | the repo URL | Scopes runners to this repository |
| `minRunners` | `0` | No node capacity held between builds |
| `maxRunners` | `3` | Bounds load on 2-vCPU nodes |
| `containerMode.type` | `dind` | Gives each runner its own Docker daemon so `docker build` works |
| `requests` | 500m / 1Gi | Small enough that a runner always fits alongside system pods |
| `limits` | 1 CPU / 2Gi | Headroom for a container build without starving the kubelet |

### The release name is the label

The Helm **release name** is what workflows target. Installed as `arc-rdev`, so
workflows say:

```yaml
runs-on: arc-rdev
```

There is no `self-hosted` label with runner scale sets — unlike ARC's older
`RunnerDeployment` API, the release name is the entire label. Renaming the release
silently breaks every workflow that references it.

## Verifying registration

Do this **before** opening a PR, so a stuck job is never ambiguous:

```bash
kubectl -n arc-systems get pods     # controller Running
kubectl -n arc-runners get pods     # listener Running
```

Then check **repo → Settings → Actions → Runners** — `arc-rdev` should be listed.

If the listener is not Running, or the runner set does not appear in GitHub, the PAT or
`githubConfigUrl` is wrong. Fix it here; a job queued against a label that no runner
provides simply waits forever with no error.

```bash
kubectl -n arc-runners logs -l app.kubernetes.io/component=runner-scale-set-listener --tail=50
```
