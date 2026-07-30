# `acr`

Azure Container Registry with role-based access instead of an admin account.

## Usage

```hcl
module "acr" {
  source = "git::https://github.com/<owner>/opentofu-azure-modules.git//modules/acr?ref=v0.1.0"

  # Alphanumeric only — no hyphens. See the note below.
  name                = "acrdemodev"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = "Basic"

  role_assignments = {
    # This is what makes image pulls work without any registry secret in the cluster.
    aks_kubelet = {
      principal_id   = module.aks.kubelet_identity_object_id
      role           = "AcrPull"
      principal_type = "ServicePrincipal"
    }

    ci_push = {
      principal_id = var.ci_principal_id
      role         = "AcrPush"
    }
  }

  tags = { environment = "dev" }
}
```

## Notes worth knowing

- **The name must be alphanumeric, 5-50 characters.** This is the most common ACR
  trip-hazard: the repo-wide `<project>-<env>-<resource>` convention produces
  `acr-demo-dev`, which Azure rejects. Normalise it in your root module — see how
  [`main.tf`](../../main.tf) does it visibly
  rather than hiding it here. The validation makes the failure immediate instead of
  surfacing mid-apply.

- **`admin_enabled` defaults to `false`, and the credentials are never output.** The admin
  account is one shared username/password with full push and pull rights: not attributable,
  not individually revocable, not rotatable without breaking every consumer. Even setting
  `admin_enabled = true` will not get you the password from this module —
  see [ADR 0005](../../docs/adr/0005-acr-ohne-admin-konto.md). Use `az acr login` or a role
  assignment.

- **`role_assignments` is intentionally generic.** The module does not know that AKS exists.
  Granting `AcrPull` to a cluster's kubelet identity, to a Container App, or to a CI runner
  is the same operation, so there is one generic map rather than an AKS-shaped input.

- **`principal_id` must be an object ID, not a resource ID.** A validation enforces the GUID
  shape, because passing `/subscriptions/…/userAssignedIdentities/x` is an easy mistake and
  the resulting Azure error is unhelpful.

- **Roles are given by name** (`AcrPull`), not by role definition ID, so the plan diff is
  readable.

- **Premium-only features are validated against the SKU.** `zone_redundancy_enabled`,
  `retention_policy_in_days`, `trust_policy_enabled`, `quarantine_policy_enabled`,
  `data_endpoint_enabled` and `georeplications` all require `sku = "Premium"`; cross-variable
  validations catch the mismatch at plan time. The default stays `Basic` because Premium
  multiplies the cost of every test run.

- **`public_network_access_enabled` defaults to `true`.** Turning it off meaningfully means
  private endpoints, which are Premium-only. Noted as a deliberate, documented skip in
  `.checkov.yaml` (removed) rather than a silent inline suppression.

## Tests

```bash
tofu -chdir=modules/acr test
```

Covers defaults (including the admin-account guard), role assignment expansion and scoping,
Premium feature gating, and every validation rule negatively — see
[`tests/`](tests/).
