# The CI workflow

`.github/workflows/ci.yml`. Two jobs, both on self-hosted runners.

## Triggers

| Event | Runs | Publishes? | Purpose |
|---|---|---|---|
| push to a feature branch | nothing | — | Branch work is not CI's concern |
| `pull_request` → `master` | `test`, then `build` | **no** | Gate the merge; prove the image still builds |
| `push` → `master` (paths `app/**`, the workflow itself) | `test`, then `build` | **yes** | Publish the image |

**`push` here does not mean "any commit anywhere."** The `branches: [master]` filter
restricts it to master — and merging a PR *is* how a push to master happens. GitHub has
no separate "merged" event; the merge commit landing on the branch is the push.

The two runs are not duplicates. The PR run tests the **PR head**; the post-merge run
tests the **merge commit**, which also contains anything else that landed on `master`
in the meantime. The second run is what catches "both PRs passed alone but break
together" — and it is the commit the published image is actually built from.

The `paths` filter on `push` means unrelated commits — docs, scripts, ARC values — do
not trigger a rebuild. It also becomes load-bearing in Phase 1b, when CI starts writing
image tags back into `deploy/**`: that write must not retrigger CI.

`pull_request` deliberately has **no** paths filter, so every PR is validated even if it
only touches docs. PRs are cheap; a wrongly-skipped check is not.

## The runner image is minimal — assume nothing is installed

The single biggest difference from GitHub-hosted runners. `ubuntu-latest` ships with
Python, Node, Go, the AWS CLI and hundreds of other tools preinstalled. The
`ghcr.io/actions/actions-runner` image ships almost none of it.

Verified by running the image directly:

```
python:  MISSING
python3: /usr/bin/python3
pip:     MISSING
pip3:    MISSING
docker:  /usr/bin/docker      (from the dind sidecar)
git:     /usr/bin/git
```

So `python -m pip install ...` — copied from any normal workflow — fails instantly with
`python: command not found`. This is what broke the first run of this pipeline.

**Rule: every toolchain the workflow needs must be set up explicitly**, with a
`setup-*` action or an install step. When porting a workflow from GitHub-hosted
runners, this is the first thing to check.

To see what an image actually contains before debugging a failed run:

```bash
kubectl run runner-probe --rm -i --restart=Never \
  --image=ghcr.io/actions/actions-runner:latest \
  --command -- bash -lc 'command -v python3 pip docker git'
```

## Job `test`

Runs on both events. Uses `actions/setup-python@v5` pinned to **3.13** — the same minor
as the Dockerfile's base image, so tests run against the interpreter that ships in
production. Then installs `requirements-dev.txt` (which pulls in the runtime
requirements via `-r`) and runs `pytest -v` from the `app/` directory.

This is the gate. `build` declares `needs: test`, so a red test means no image is ever
built, let alone published.

## Job `build`

Runs on **both** events. What changes is whether it publishes:

```yaml
push: ${{ github.event_name == 'push' }}
```

That single line separates **validation** from **publication**:

- On a **PR**, the image is built and thrown away. This catches a broken Dockerfile
  before the merge rather than after — a failure mode tests alone cannot detect, since
  the app can be perfectly healthy while the image fails to build.
- On **push to master**, the same build is published.

The GHCR login step is skipped on PRs (`if: github.event_name == 'push'`). Nothing is
published there, so no credentials are needed — which also keeps **fork PRs** working,
where `GITHUB_TOKEN` is read-only and a GHCR login would fail outright.

Steps:

1. `docker/login-action` → `ghcr.io` with the built-in `secrets.GITHUB_TOKEN`. Nothing
   to create, nothing to rotate. Works because the job declares `permissions:
   packages: write`. **Push events only.**
2. `docker/setup-buildx-action` → BuildKit, talking to the dind sidecar.
3. Derive `sha-<short-sha>` from `git rev-parse --short HEAD`.
4. `docker/build-push-action` with context `./app`, building both tags and pushing only
   on master.

A useful side effect: the PR build populates the layer cache, so the post-merge publish
is mostly re-tagging layers that were already built.

## Image tags

```
ghcr.io/sliu2200899/self-hosted-ci-cd/sample-app:sha-<short-sha>
ghcr.io/sliu2200899/self-hosted-ci-cd/sample-app:latest
```

`sha-<short-sha>` is the one that matters — immutable and traceable to exactly one
commit. Phase 1b deploys that tag, never `latest`, because a mutable tag makes "what is
actually running?" unanswerable and breaks rollback.

`latest` exists only for convenient manual pulls.

## Caching

`cache-from`/`cache-to: type=gha` uses GitHub's cache service, which works from
self-hosted runners. Since every runner pod is destroyed after its job, this is the only
thing making a second build faster than the first — there is no local layer cache to
reuse.

## Concurrency

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

A newer push to the same branch makes an in-flight run obsolete. Cancelling frees the
runner pod immediately, which matters when `maxRunners` is 3.

## What CI deliberately does not do

It does not deploy, and it does not talk to the cluster. Its entire output is an image
in a registry. Deployment is Argo CD's job in Phase 1b, driven by git.
