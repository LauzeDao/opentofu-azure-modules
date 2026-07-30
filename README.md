# opentofu-azure-modules

A small, curated library of reusable **OpenTofu modules for Azure** — resource group,
networking, **AKS**, container registry, key vault — plus a root module at the repository
root that composes all five into a working cluster.

This is a portfolio project. Its point is not "here is some Azure infrastructure" but
**how a module library is built**: contract-first interfaces, validation that fails at plan
time instead of mid-apply, tests that cost nothing to run, and written reasoning for the
decisions a reviewer would otherwise read as mistakes.

## Modules

| Module | Purpose |
|---|---|
| [`modules/resource-group`](modules/resource-group) | Resource group with tag pass-through and up-front name validation. Deliberately boring. |
| [`modules/networking`](modules/networking) | VNet with map-keyed subnets; a network security group is created only for subnets that declare rules. |
| [`modules/aks`](modules/aks) | **The core.** System/user node pool separation, OIDC issuer and Workload Identity always on, kubelet identity exposed for downstream role assignments. |
| [`modules/acr`](modules/acr) | Container registry with role-based access instead of an admin account. |
| [`modules/key-vault`](modules/key-vault) | Key vault with RBAC authorization; access policies are not supported at all. |

The root module ([`main.tf`](main.tf)) wires them together: naming locals, `AcrPull` for the
cluster's kubelet identity, and Key Vault RBAC.

## Layout

```
.
├─ provider.tf         the only provider block, plus required_providers
├─ main.tf             composes the five modules
├─ variables.tf
├─ outputs.tf
├─ terraform.tfvars    configuration — placeholder values only
├─ modules/
│   └─ <name>/         main.tf, variables.tf, outputs.tf, README.md, tests/
├─ tests/              composition tests for the root module
├─ pipelines/          ci.yml (gate, no credentials), apply.yml (manual)
└─ docs/               architecture, ADRs, deployment checklist, build specs
```

Conventions, the module contract and how to add a module: [`CONTRIBUTING.md`](CONTRIBUTING.md).

Three `.tf` files per module, no `versions.tf` — `required_providers` lives only in
`provider.tf`. The `.tf` files carry no comments; explanations are in `description` fields,
module READMEs and `docs/`. Reasoning: [ADR 0009](docs/adr/0009-vereinfachtes-repo-layout.md).

## Quickstart

Everything below works without an Azure account:

```bash
git clone https://github.com/<owner>/opentofu-azure-modules.git
cd opentofu-azure-modules

tofu init -backend=false
tofu validate
tofu test                                  # composition tests

tofu -chdir=modules/aks init -backend=false
tofu -chdir=modules/aks test               # one module, no flags needed

tflint --init
tflint --recursive --config="$PWD/.tflint.hcl"
```

The `--config` path is required, not cosmetic: with `--recursive`, tflint chdirs into each
subdirectory and looks for a `.tflint.hcl` *there*. Without the absolute path the root config
is ignored inside `modules/*`, and `terraform_required_providers` /
`terraform_required_version` report ten false positives — they expect a per-module
`versions.tf`, which this repo deliberately does not have.

To actually deploy — locally or through the pipeline — follow
**[`docs/deployment.md`](docs/deployment.md)**. It is a checklist with the `az` commands,
including the two roles that are easy to miss.

**`terraform.tfvars` is committed, and this repository is public.** It holds placeholder
GUIDs only, and it needs to stay that way — subscription and tenant IDs are not credentials,
but they do identify your environment. Override them locally instead of editing the file:
```bash
export TF_VAR_subscription_id=`az account show --query id -o tsv`
export TF_VAR_tenant_id=`az account show --query tenantId -o tsv`
export TF_VAR_deployer_principal_id=`az ad signed-in-user show --query id -o tsv`
```

The CI pipeline fails the build if a real value ever lands in that file.

## Consuming a module

Versioning is by git tag; there is no registry to host. One tag spans the whole repo, so
every module in it comes from the same tested state.

```hcl
module "aks" {
  source = "git::https://github.com/<owner>/opentofu-azure-modules.git//modules/aks?ref=v0.1.0"

  name                = "aks-demo-dev"
  resource_group_name = module.resource_group.name
  location            = "germanywestcentral"

  system_node_pool = {
    vm_size        = "Standard_B2s"
    vnet_subnet_id = module.networking.subnet_ids["system"]
  }
}
```

Pin the exact tag. Never `?ref=main`.

## What this repo does differently

The decisions most likely to look wrong at first glance, each with the reasoning written
down:

- **Workload Identity is not a feature flag.** `oidc_issuer_enabled` and
  `workload_identity_enabled` are hard-coded `true` in the AKS module, with a test that
  fails if anyone turns them into variables. A flag that can be switched off eventually is,
  and then workloads need client secrets again
  ([ADR 0004](docs/adr/0004-oidc-workload-identity-immer-aktiv.md)).

- **The ACR module never outputs admin credentials**, even when the admin account is enabled.
  Access goes through role assignments on managed identities
  ([ADR 0005](docs/adr/0005-acr-ohne-admin-konto.md)).

- **ACR and Key Vault are created *after* AKS**, not before. They need the cluster's kubelet
  identity for their role assignments, and letting AKS create it keeps the destroy path clean.
  The dependency graph in [`docs/architecture.md`](docs/architecture.md#1-modul-abhängigkeitsgraph)
  makes this visible; the reasoning is in
  [ADR 0006](docs/adr/0006-kubelet-identity-statt-vorab-identity.md).

- **Key Vault purge protection defaults to `false`** — the one place a default knowingly
  departs from the security baseline. It is irreversible and holds the vault name for up to
  90 days, which would make a repeatable destroy/apply cycle impossible. Written down rather
  than quietly shipped — [ADR 0007](docs/adr/0007-purge-protection-default-aus.md).

- **No comments in the Terraform code, and no generated docs.** The contract lives in the
  `description` fields, the reasoning in `docs/`. This replaced an earlier setup with nine
  tooling config files and four external tools
  ([ADR 0009](docs/adr/0009-vereinfachtes-repo-layout.md)).

- **Naming lives in the root module, not the modules.** Which matters because two Azure
  services break the generic convention: registries forbid hyphens, vaults cap at 24
  characters. Both are corrected visibly in the root `main.tf`, where naming belongs.

- **Subnets and node pools are maps, not lists.** With a list, inserting an entry shifts
  every later index and OpenTofu wants to replace all of them. Stable keys make `for_each`
  idempotent.

- **Every `validation` block has a negative test.** A rule that is never tested negatively
  provides no guarantee at all — a typo in the condition would simply never surface. Roughly
  half the test cases exist to prove that bad input really is rejected.

All decisions: [`docs/adr/`](docs/adr/). Architecture and diagrams:
[`docs/architecture.md`](docs/architecture.md).

## Testing

Three layers, deliberately separated by cost:

| Layer | What it proves | Cost |
|---|---|---|
| `tofu validate` | Syntax, types, provider schema | none |
| `tofu test` + `mock_provider` | Contract logic: defaults, validations, `for_each` expansion, output wiring | none |
| Real `apply` → `kubectl` → `destroy` | That Azure actually accepts it | real money |

Most of the value sits in the middle layer, with one caveat worth being blunt about: green
tests do not mean "works in Azure". No mock knows whether a VM size is available in a region
or whether a role assignment took effect. See
[`docs/architecture.md` §6](docs/architecture.md#6-test-strategie-mock-vs-echt).

## CI and deployment

Two Azure DevOps pipelines: [`pipelines/ci.yml`](pipelines/ci.yml) runs the gate above on
every push and pull request and holds no Azure credentials at all;
[`pipelines/apply.yml`](pipelines/apply.yml) does the real apply, verifies with `kubectl` and
tears everything down again — manual trigger, behind an approval.

To deploy this yourself, work through [`docs/deployment.md`](docs/deployment.md). It covers
both the local route (`az login` and nothing else) and the pipeline route, with the `az`
commands and the two role assignments that are easy to miss. What the pipelines do and why:
[`docs/pipeline.md`](docs/pipeline.md).

The apply path has not been exercised end to end yet — that needs a subscription, a service
connection and a state backend. So the composition is coherent and tested against mocks, but
not yet proven deployable, and the pipeline definitions are untried.

Out of scope on purpose: multi-cloud abstraction, hosting a private module registry, the
Kubernetes workloads themselves, and cost-management tooling.
