# `aks`

Azure Kubernetes Service cluster with system/user node pool separation, OIDC issuer and
Workload Identity always on, and the kubelet identity exposed for downstream role
assignments.

The core module of this library. The other four exist largely to serve it.

## Usage

```hcl
module "aks" {
  source = "git::https://github.com/<owner>/opentofu-azure-modules.git//modules/aks?ref=v0.1.0"

  name                = "aks-demo-dev"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # null uses the Azure default for the region; pin it for reproducibility.
  kubernetes_version = "1.31"

  system_node_pool = {
    vm_size        = "Standard_B2s"
    node_count     = 1
    vnet_subnet_id = module.networking.subnet_ids["system"]

    # Applies the CriticalAddonsOnly taint. Requires a user pool below.
    only_critical_addons_enabled = true
  }

  user_node_pools = {
    apps = {
      vm_size              = "Standard_D2s_v5"
      auto_scaling_enabled = true
      min_count            = 1
      max_count            = 5
      vnet_subnet_id       = module.networking.subnet_ids["user"]
    }

    batch = {
      vm_size         = "Standard_D2s_v5"
      priority        = "Spot"
      eviction_policy = "Delete"
      node_taints     = ["workload=batch:NoSchedule"]
      vnet_subnet_id  = module.networking.subnet_ids["user"]
    }
  }

  admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
  tenant_id              = var.tenant_id

  # Strongly recommended outside a throwaway cluster.
  api_server_authorized_ip_ranges = ["203.0.113.0/24"]

  tags = { environment = "dev" }
}
```

Then grant the cluster access to a registry:

```hcl
module "acr" {
  # ...
  role_assignments = {
    aks_kubelet = {
      principal_id   = module.aks.kubelet_identity_object_id
      role           = "AcrPull"
      principal_type = "ServicePrincipal"
    }
  }
}
```

## Notes worth knowing

- **`oidc_issuer_enabled` and `workload_identity_enabled` are hard-coded `true`** and are
  not exposed as variables. A flag that can be switched off eventually is switched off,
  and then workloads need client secrets again. See
  [ADR 0004](../../docs/adr/0004-oidc-workload-identity-immer-aktiv.md). The
  `oidc_issuer_url` output is therefore always available.

- **There is no `service_principal` block.** It would put a long-lived client secret in
  state. Identity is always managed — `SystemAssigned` by default.

- **Three different identities are involved**, and they are routinely confused:
  `cluster_identity_principal_id` (control plane), `kubelet_identity_object_id` (nodes
  pulling images — this is the one ACR needs), and Workload Identity via
  `oidc_issuer_url` (per-ServiceAccount, the right choice for applications). See
  [architecture §3](../../docs/architecture.md#3-aks-identitäten).

- **`kubernetes_version` defaults to `null`**, meaning "Azure's default for this region".
  A hard-coded default would go stale and break the module within months as Azure retires
  minor versions. Pin it in your root module.

- **`network_plugin_mode` defaults to `overlay`.** Azure CNI without overlay assigns a VNet
  IP per pod, which exhausts a /22 subnet at around 1000 pods. Overlay decouples pod IPs
  from the VNet. `pod_cidr` is only sent when overlay or kubenet is in use — passing it
  otherwise makes the Azure API reject the request.

- **`only_critical_addons_enabled = true` requires a user node pool.** A cross-variable
  validation enforces it, so you find out at plan time instead of after a 15-minute apply
  that has nowhere to schedule workloads.

- **`node_count` is not sent when autoscaling is on.** Azure owns the value then; sending it
  would be a permanent diff. The module deliberately does *not* use
  `lifecycle { ignore_changes = [...] }` for this, because that would also mask genuine
  drift elsewhere in the pool.

- **`temporary_name_for_rotation` is always set.** Without it, any change that forces a
  default-node-pool rebuild (changing `vm_size`, for instance) fails with an opaque
  provider error.

- **Defaults are deliberately open for CI:** `private_cluster_enabled = false` and an empty
  `api_server_authorized_ip_ranges`, so a GitHub-hosted runner can reach the API server.
  **Restrict both for production.**

- **All kubeconfig-derived outputs are `sensitive`.** Without that, client certificates and
  keys are printed in CI logs.

- **Add-ons are off by default but all reachable.** `azure_policy_enabled`,
  `key_vault_secrets_provider` (Secrets Store CSI Driver), `disk_encryption_set_id` and
  `image_cleaner_enabled` each schedule extra system pods or require prerequisites outside
  this module, so none is on by default — but every one is an input, because a module that
  cannot enable them is incomplete. When you do opt into the CSI driver,
  `secret_rotation_enabled` defaults to `true`: without rotation, a secret rotated in the
  vault is never picked up by running pods.

## Tests

```bash
tofu -chdir=modules/aks test
```

Covers defaults, the hard-coded Workload Identity invariants, node pool expansion,
autoscaling in both directions, spot pools, identity wiring, and every validation rule
negatively — see [`tests/`](tests/).

One limitation, stated openly: `kubelet_identity` is a computed-only block that
`mock_provider` leaves empty and cannot inject, so the kubelet outputs resolve to null
under test and are asserted for plan-safety rather than by value. The end-to-end proof
that AcrPull binds to that identity is a real apply/destroy against Azure, which has not
been run yet.
