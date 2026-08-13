# AKS Setup Using Terraform

This module contains all the configuration specific to our Azure Kubernetes Service setup using Terraform

Changes to this module should be analogous to changes that are possible via the `az` CLI or [Azure Portal](https://portal.azure.com).

## Status: legacy layout

`aks-terraform/` is kept for backwards compatibility, but **new changes should go into**:

- `terraform/modules/aks-cluster` (shared AKS logic)
- `terraform/envs/**` (where you run Terraform per cluster)

See `terraform/README.md` for the new default workflow.

## Install terraform
```
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

## Preparing the local environment

Login to Azure using ```az login``` and your personal account.
Check if you have the correct role `CR: Administrator - Active' assigned and activated. Then raise PIM request to get the access to storage account with TF state (in the tfstate resource group). Note: make sure you logout using ```az logout``` and login again to get updated permissions.
Then run ```terraform init -var-file=<var file name>``` to init the TF locally.


## Staging and Prod Cluster
We use *.tfvars file to spin up different clusters.

Note: Replace the placeholder string for `client_secret` variable in *.tfvars file before running terraform commands

Terraform for Staging and Prod cluster is under the respective folders.
```
cd <cluster - staging / prod>
```
Under prod, the terraform for US-West and US-East clusters are under the respective folders.
```
cd <region - us-east / us-west>
```

### Instructions for switching workspace under respective folders
Before you do any change, you need to switch terraform workspace:
```
sh-3.2$ terraform workspace list
  default                 ==> rdev-aks-wus3-1
  rdev-aks-wus3-2         ==> rdev-aks-wus3-2
  rdev-aks-wus3-3         ==> rdev-aks-wus3-3
  rdev-aks-wus3-4         ==> rdev-aks-wus3-4
  rdev-aks-wus3-5         ==> rdev-aks-wus3-5
  rdev-aks-wus3-6         ==> rdev-aks-wus3-6
  rdev-aks-wus3-7         ==> rdev-aks-wus3-7
  rdev-aks-wus3-8         ==> rdev-aks-wus3-8
  rdev-aks-wus3-9         ==> rdev-aks-wus3-9
  rdev-aks-wus3-10        ==> rdev-aks-wus3-10
  rdev-aks-wus3-11        ==> rdev-aks-wus3-11
  rdev-aks-wus3-12        ==> rdev-aks-wus3-12
  rdev-aks-wus3-13        ==> rdev-aks-wus3-13
  rdev-aks-wus3-14        ==> rdev-aks-wus3-14
  rdev-aks-wus3-15        ==> rdev-aks-wus3-15
  rdev-aks-wus3-agents-1  ==> rdev-aks-wus3-agents-1
  rdev-aks-staging-wus3-1 ==> rdev-aks-staging-wus3-1
  rdev-aks-staging-wus3-2 ==> rdev-aks-staging-wus3-2
  rdev-aks-eus-1          ==> rdev-aks-eus-1
  rdev-aks-eus-2          ==> rdev-aks-eus-2
  rdev-aks-eus-3          ==> rdev-aks-eus-3
  rdev-aks-eus-4          ==> rdev-aks-eus-4
  rdev-aks-eus-5          ==> rdev-aks-eus-5
  rdev-aks-seas-1         ==> rdev-aks-seas-1
  rdev-aks-seas-c         ==> rdev-aks-seas-c
```

Note: TOOLS-464643: rdev-aks-seas-c is the cluster that we spin up specifically for Raja contractors

switch to a workspace:
```
terraform workspace select <WORKSPACE-NAME>
```
create a new workspace:
```
terraform workspace new <WORKSPACE-NAME>
```

### Instructions for spinning up cluster
To apply terraform with a var file
```
terraform init -var-file=<var file name>
terraform plan -var-file=<var file name>
terraform apply -var-file=<var file name>
```
Example:
```
terraform init -var-file=rdev-aks-wus3-1.tfvars
terraform plan -var-file=rdev-aks-wus3-1.tfvars
terraform apply -var-file=rdev-aks-wus3-1.tfvars
```
You need to uncomment the code in create-remote-storage.tf if you apply the change to rdev-aks-wus3-1

#### Update provider versions
To update one of the provider version (azurerm, kubernetes, helm) in providers.tf, edit the file to update the version and then run
```
terraform init -upgrade
```

## Note: Enable Prometheus metrics whenever the Terraform is updated for a cluster

On updating the terraform for any cluster, make sure to re-enable `Metrics Collection` for that cluster from Azure Portal.
This is important for the Grafana dashboard to collect the metrics for the cluster.

Steps:
- Login to https://portal.azure.com/ using LNKDPROD account
- Search for `Azure Monitor workspaces`
- Select the monitoring workspace and on the left hand side, under `Managed Prometheus`, click on `Monitored clusters`
- Make sure `Metrics Collection` is Enabled for the cluster that was just updated
- If its not enabled, request `CR: Administrator` access to this resource and then click on `Enable`

TODO: Move Metrics Enabling logic to Terraform to avoid the above manual step.


## Note: Cluster Upgrade

Upgrading cluster would re-provision all nodes, which force our node-manager pod to re-pull all images. It is pretty slow when all pods pull image together. We should firstly upgrade system node and operator node. Then we could upgrade rdev nodepool. 
Step:
1. Update kubernetes_version and apply the tf. It would update k8s, default node pool and operator node pool.
2. After 1 is done, confirm the operator is up.
3. Update rdev_node_version and apply the tf to upgrade rest node pools.

The long term solution is to enable image cache.