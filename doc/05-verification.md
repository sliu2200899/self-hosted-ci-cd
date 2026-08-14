# Verification — the PR round trip

The acceptance test for Phase 1a. Run it end to end; each step checks something the
next one depends on.

## 0. Runner is registered

Do this **first**. A job queued against a label no runner provides waits forever with
no error message, so an unverified runner makes every later failure ambiguous.

```bash
kubectl -n arc-systems get pods    # controller Running
kubectl -n arc-runners get pods    # listener Running
```

Repo → Settings → Actions → Runners should list `arc-rdev`.

## 1. Open a PR

```bash
git checkout -b test-ci
# edit APP_VERSION default in app/main.py, e.g. 0.1.0 -> 0.1.1
git commit -am "Bump version to 0.1.1"
git push -u origin test-ci
gh pr create --fill        # or open it in the browser
```

## 2. Watch it run on your own hardware

While the check is queued or running:

```bash
kubectl -n arc-runners get pods -w
```

An ephemeral runner pod should appear, run, and disappear. **That pod is the proof CI
is self-hosted** — this is the single most important observation in Phase 1a.

In the PR's Checks tab: `test` passes, then `build` runs and passes. `build` does **not**
publish here — its summary should read "Build validated — not published (pull request)".

## 3. Merge to master

Merge the PR. The `push` trigger fires.

## 4. Build and push

`test` runs again, then `build` — this time publishing. In the job log, confirm the push succeeded and
note the `sha-` tag. The job summary lists both tags pushed.

## 5. Confirm the image exists

GitHub → your profile → Packages → `sample-app`. There should be a tag matching the
merge commit's short SHA, plus `latest`.

From the CLI:

```bash
echo $GH_PAT | docker login ghcr.io -u sliu2200899 --password-stdin
docker manifest inspect ghcr.io/sliu2200899/self-hosted-ci-cd/sample-app:latest
```

## 6. Confirm it is a runnable image

A manifest existing is not the same as an image that starts. Once the package is public
(see below):

```bash
kubectl run smoke --rm -it --restart=Never \
  --image=ghcr.io/sliu2200899/self-hosted-ci-cd/sample-app:latest \
  -- python -c "import main; print(main.APP_VERSION)"
```

Expect the version you set in step 1.

## 7. Scale back to zero

A few minutes after the run:

```bash
kubectl -n arc-runners get pods
```

Only the listener should remain. Idle cost is back to zero.

## Package visibility

The first push creates the GHCR package as **private**, inherited from the private repo.
Make it public once:

**GitHub → profile → Packages → `sample-app` → Package settings → Change visibility →
Public**

CI passes either way. This matters for Phase 1b: a public package means the cluster
pulls need no `imagePullSecret`. Until it is flipped, pods sit in `ImagePullBackOff` —
the most likely first-run failure in Phase 1b.

## Phase 1a is done when

- [ ] A PR runs `test` and `build` on pods in your cluster, publishing nothing
- [ ] A merge to `master` runs both jobs and publishes
- [ ] A `sha-<short-sha>` image tag exists in GHCR matching the merge commit
- [ ] That image starts and reports the expected version
- [ ] Runners return to zero when idle
