# The CI workflow

`.github/workflows/ci.yml`. Two jobs, both on self-hosted runners.

## Triggers

| Event | Runs | Purpose |
|---|---|---|
| `pull_request` → `master` | `test` only | Gate the merge |
| `push` → `master` (paths `app/**`, the workflow itself) | `test`, then `build-push` | Publish an image |

The `paths` filter on `push` means unrelated commits — docs, scripts, ARC values — do
not trigger a rebuild. It also becomes load-bearing in Phase 1b, when CI starts writing
image tags back into `deploy/**`: that write must not retrigger CI.

## Job `test`

Runs on both events. Installs `requirements-dev.txt` (which pulls in the runtime
requirements via `-r`) and runs `pytest -v` from the `app/` directory.

This is the gate. `build-push` declares `needs: test`, so a red test means no image is
ever published.

## Job `build-push`

Guarded twice:

```yaml
needs: test
if: github.event_name == 'push' && github.ref == 'refs/heads/master'
```

**Why never on `pull_request`:** a fork PR receives a read-only `GITHUB_TOKEN` and
could not push regardless — but more importantly, we do not want unreviewed PR code
producing published images.

Steps:

1. `docker/login-action` → `ghcr.io`, authenticating with the built-in
   `secrets.GITHUB_TOKEN`. Nothing to create, nothing to rotate. This works because the
   job declares `permissions: packages: write`.
2. `docker/setup-buildx-action` → BuildKit, talking to the dind sidecar.
3. Derive `sha-<short-sha>` from `git rev-parse --short HEAD`.
4. `docker/build-push-action` with context `./app`, pushing two tags.

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
