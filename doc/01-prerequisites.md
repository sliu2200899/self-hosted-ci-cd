# Prerequisites

## Target cluster

Verified state of the cluster this was built against:

| Item | Value |
|---|---|
| Cluster | `rdev-aks-wus3-1` |
| Resource group | `wus3-rdev-rg` |
| Subscription | `Azure subscription 1` (`dab544a2-6a18-4be1-9676-ce2fbce7713a`) |
| Region | `westus3` |
| Kubernetes | 1.34.6 |
| API server | public |
| Node pools | `default` (System), `rdev`, `operator` — all `Standard_D2s_v3` (2 vCPU / 8 GiB) |
| Autoscaling | 1→6, 1→10, 1→6 respectively |
| Networking | kubenet, Standard load balancer |
| Identity | OIDC issuer enabled; workload identity **not** enabled (not needed in Phase 1a) |
| Addons | azurepolicy, omsagent |

### Why privileged containers work here

Building images inside a runner pod uses Docker-in-Docker, which needs a privileged
container. That is only possible because this cluster has **no** admission control
blocking it. Confirmed by:

```bash
az policy assignment list --scope "/subscriptions/<sub>/resourceGroups/wus3-rdev-rg/providers/Microsoft.ContainerService/managedClusters/rdev-aks-wus3-1"
kubectl get constrainttemplates
kubectl get ns -o custom-columns='NAME:.metadata.name,ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce'
```

All three returned empty. **Re-check these before reusing this setup on a hardened
cluster** — with a `restricted` Pod Security label or a Gatekeeper privileged-container
constraint, dind runners will fail to schedule and a rootless builder is needed instead.

## Local tools

| Tool | Required | Install |
|---|---|---|
| `kubectl` | yes | already present |
| `helm` | yes | `brew install helm` |
| `az` | yes | already present (2.88.0) |
| `git` | yes | already present |
| `gh` | optional | `brew install gh` — convenient for PRs |
| `docker` | no | builds run in-cluster, not locally |

## Cluster access

```bash
az aks get-credentials -g wus3-rdev-rg -n rdev-aks-wus3-1 --overwrite-existing
kubectl get nodes
```

Expect three `Ready` nodes on v1.34.6.

> If `kubectl` reports `no such host`, the kubeconfig is stale — the AKS API server
> FQDN contains a random suffix that changes when a cluster is recreated. Re-run
> `az aks get-credentials --overwrite-existing`.

## GitHub

- Repository: `sliu2200899/self-hosted-ci-cd` (**private**)
- Default branch: `master`
- A **classic PAT with `repo` scope** is needed for runner registration — see
  [03-arc-runners.md](03-arc-runners.md).

No secret is needed for pushing images: the workflow uses the built-in `GITHUB_TOKEN`.

## Cost

Phase 1a creates **no new Azure resources** — no ACR, no public IP, no ingress. The
only cost movement is the `rdev` node pool autoscaling while builds run. Runners scale
to zero when idle.
