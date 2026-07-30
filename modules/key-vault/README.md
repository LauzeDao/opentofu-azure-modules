# `key-vault`

Azure Key Vault with RBAC authorization. Access policies are not supported by this module
at all.

## Usage

```hcl
module "key_vault" {
  source = "git::https://github.com/<owner>/opentofu-azure-modules.git//modules/key-vault?ref=v0.1.0"

  name                = "kv-demo-dev"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  tenant_id           = var.tenant_id

  role_assignments = {
    # Required, not optional — see the note about Contributor below.
    deployer = {
      principal_id = var.deployer_principal_id
      role         = "Key Vault Administrator"
    }

    aks_kubelet = {
      principal_id   = module.aks.kubelet_identity_object_id
      role           = "Key Vault Secrets User"
      principal_type = "ServicePrincipal"
    }
  }

  tags = { environment = "dev" }
}
```

Production hardening:

```hcl
module "key_vault" {
  # ...
  purge_protection_enabled   = true   # IRREVERSIBLE — read the note below first
  soft_delete_retention_days = 90
  sku_name                   = "premium"

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
    # Without an entry for your own address, you lock yourself out of the data plane.
    ip_rules                   = ["203.0.113.0/24"]
    virtual_network_subnet_ids = [module.networking.subnet_ids["system"]]
  }
}
```

## Notes worth knowing

- **`rbac_authorization_enabled` is hard-coded `true`** and not exposed. There is no
  `access_policy` block anywhere in the module, so the two authorization models cannot be
  accidentally mixed.

- **`Contributor` does not grant access to secrets.** On an RBAC vault, even a subscription
  Owner cannot read or write secrets without a *data-plane* role. That is why the example
  root always assigns `Key Vault Administrator` to the deploying identity — omit it and
  your first `az keyvault secret set` fails with a permissions error that looks like a bug.

- **⚠️ `purge_protection_enabled` defaults to `false`, which is weaker than every security
  baseline recommends.** This is the one place in the repo where a default deliberately
  departs from the baseline. Purge protection is **irreversible** once enabled and holds the
  vault name for 7-90 days, which would make this repo's "destroy leaves nothing behind"
  requirement impossible — the second run would fail on a name collision.
  **Set it to `true` for production.** Full reasoning:
  [ADR 0007](../../docs/adr/0007-purge-protection-default-aus.md).

- **`soft_delete_retention_days` defaults to 7**, the minimum, for the same reason: the vault
  name is released again as early as Azure permits. 90 is the sensible production value.

- **`tenant_id` is an input, not a `data "azurerm_client_config"` lookup.** A data source
  would make the module unplannable under `mock_provider` in tests, and the module genuinely
  needs the value — so it belongs in the contract.

- **A destroy that leaves a soft-deleted vault is not clean.** Set these in your root
  provider block, as [`provider.tf`](../../provider.tf)
  does:
  ```hcl
  provider "azurerm" {
    features {
      key_vault {
        purge_soft_delete_on_destroy    = true
        recover_soft_deleted_key_vaults = true
      }
    }
  }
  ```

- **`sku_name` is lowercase.** Azure rejects `"Standard"`; the validation catches it at plan
  time rather than mid-apply.

- **Name rules are strict:** 3-24 characters, must start with a letter, no consecutive
  hyphens, must not end with a hyphen, and globally unique across Azure. The 24-character
  cap is why the example root limits `project` to 8 characters.

## Tests

```bash
tofu -chdir=modules/key-vault test
```

Covers the RBAC invariant, the absence of access policies, the destroy-friendly defaults,
`network_acls` in both states, role assignment scoping, and every validation rule
negatively — see [`tests/`](tests/).
