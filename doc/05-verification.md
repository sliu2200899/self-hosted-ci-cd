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

- [x] A PR runs `test` and `build` on pods in your cluster, publishing nothing
- [x] A merge to `master` runs both jobs and publishes
- [x] A `sha-<short-sha>` image tag exists in GHCR matching the merge commit
- [x] That image starts and reports the expected version
- [x] Runners return to zero when idle

---

# Phase 1b verification — the GitOps loop

## 8. Argo CD reaches Synced / Healthy

```bash
kubectl -n argocd get application sample-app
kubectl -n sample-app get deploy,pods,svc
```

Expect `Synced` / `Healthy` and two Running pods.

If it is stuck, it is almost always the deploy key:

```bash
kubectl -n argocd get application sample-app -o jsonpath='{.status.conditions}'
kubectl -n argocd logs deploy/argocd-repo-server --tail=50
```

A permission error means the public key was never added to the repo, or the repository
Secret's `url` does not match the Application's `repoURL` character for character.

## 9. The app serves

```bash
kubectl -n sample-app port-forward svc/sample-app 8000:80
curl -s localhost:8000/healthz   # {"status":"ok"}
curl -s localhost:8000/          # {"app":"sample-app","version":"..."}
```

## 10. Self-heal — proof git is the source of truth

This is the test that distinguishes GitOps from a one-shot deployment:

```bash
kubectl -n sample-app scale deploy/sample-app --replicas=5
kubectl -n sample-app get deploy sample-app -w
```

Argo CD should revert it to 2 within a minute. If it does not, `selfHeal` is
misconfigured — and git is only describing the *initial* state, not the current one.

## 11. The full loop

The end-to-end test of both phases together:

1. Change the `APP_VERSION` default in `app/main.py` (e.g. `0.1.1` → `0.2.0`).
2. Open a PR, confirm `test` and `build` pass and publish nothing, then merge.
3. Watch CI: `test` → `build` → `bump`.
4. Confirm `bump` committed — a new `Deploy sha-...` commit by `github-actions[bot]`
   on `master`, touching only `deploy/overlays/dev/kustomization.yaml`.
5. Confirm that commit did **not** trigger another CI run.
6. Wait ~3 minutes (or force a sync), then:

```bash
kubectl -n sample-app rollout status deploy/sample-app
kubectl -n sample-app port-forward svc/sample-app 8000:80
curl -s localhost:8000/          # reports the NEW version
```

Force a sync instead of waiting:

```bash
kubectl -n argocd patch application sample-app --type merge \
  -p '{"operation":{"sync":{"revision":"master"}}}'
```

## Phase 1b is done when

- [ ] `sample-app` Application is `Synced` / `Healthy`
- [ ] The app serves `/healthz` and `/` from the cluster
- [ ] A manual `kubectl scale` is reverted by self-heal
- [ ] A merge produces a `bump` commit that does **not** retrigger CI
- [ ] The new version is live without anyone running `kubectl apply`
