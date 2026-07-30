mock_provider "azurerm" {
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.KeyVault/vaults/kv-demo-dev"
      vault_uri = "https://kv-demo-dev.vault.azure.net/"
    }
  }
}

variables {
  name                = "kv-demo-dev"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
  tenant_id           = "55555555-5555-5555-5555-555555555555"
}

run "plans_with_only_required_inputs" {
  command = plan

  assert {
    condition     = azurerm_key_vault.main.name == "kv-demo-dev"
    error_message = "name must reach the vault unchanged."
  }

  assert {
    condition     = azurerm_key_vault.main.tenant_id == "55555555-5555-5555-5555-555555555555"
    error_message = "tenant_id must reach the vault — it comes from the contract, not a data source."
  }
}

run "rbac_authorization_is_always_enabled" {
  command = plan

  assert {
    condition     = azurerm_key_vault.main.rbac_authorization_enabled == true
    error_message = "rbac_authorization_enabled must be true and not configurable — this module supports RBAC only, never access policies."
  }
}

run "never_configures_access_policies" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault.main.access_policy) == 0
    error_message = "the module must never create access policies — the two authorization models must not be mixed."
  }
}

run "destroy_friendly_defaults" {
  command = plan

  assert {
    condition     = azurerm_key_vault.main.purge_protection_enabled == false
    error_message = "purge_protection_enabled must default to false so the apply/destroy cycle stays repeatable (ADR 0007)."
  }

  assert {
    condition     = azurerm_key_vault.main.soft_delete_retention_days == 7
    error_message = "soft_delete_retention_days must default to the 7-day minimum, releasing the vault name as early as Azure allows."
  }

  assert {
    condition     = azurerm_key_vault.main.sku_name == "standard"
    error_message = "sku_name must default to standard."
  }
}

run "purge_protection_can_be_enabled_for_production" {
  command = plan

  variables {
    purge_protection_enabled   = true
    soft_delete_retention_days = 90
  }

  assert {
    condition     = azurerm_key_vault.main.purge_protection_enabled == true
    error_message = "a consumer must be able to opt into purge protection."
  }

  assert {
    condition     = azurerm_key_vault.main.soft_delete_retention_days == 90
    error_message = "the maximum retention must be accepted."
  }
}

run "deployment_flags_default_off" {
  command = plan

  assert {
    condition     = azurerm_key_vault.main.enabled_for_disk_encryption == false
    error_message = "enabled_for_disk_encryption must default to false."
  }

  assert {
    condition     = azurerm_key_vault.main.enabled_for_deployment == false
    error_message = "enabled_for_deployment must default to false."
  }

  assert {
    condition     = azurerm_key_vault.main.enabled_for_template_deployment == false
    error_message = "enabled_for_template_deployment must default to false."
  }
}

run "omits_network_acls_when_null" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault.main.network_acls) == 0
    error_message = "network_acls = null must mean no block at all, not an empty one."
  }
}

run "applies_network_acls_when_set" {
  command = plan

  variables {
    network_acls = {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = ["203.0.113.0/24"]
    }
  }

  assert {
    condition     = length(azurerm_key_vault.main.network_acls) == 1
    error_message = "a configured network_acls object must produce exactly one block."
  }

  assert {
    condition     = azurerm_key_vault.main.network_acls[0].default_action == "Deny"
    error_message = "default_action must reach the vault."
  }

  assert {
    condition     = azurerm_key_vault.main.network_acls[0].bypass == "AzureServices"
    error_message = "bypass must default to AzureServices inside the object."
  }

  assert {
    condition     = length(azurerm_key_vault.main.network_acls[0].ip_rules) == 1
    error_message = "ip_rules must reach the vault."
  }
}

run "creates_no_assignments_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.vault) == 0
    error_message = "role_assignments must default to empty — no implicit grants."
  }
}

run "creates_one_assignment_per_map_entry" {
  command = plan

  variables {
    role_assignments = {
      deployer = {
        principal_id = "88888888-8888-8888-8888-888888888888"
        role         = "Key Vault Administrator"
      }
      aks_kubelet = {
        principal_id   = "22222222-2222-2222-2222-222222222222"
        role           = "Key Vault Secrets User"
        principal_type = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.vault) == 2
    error_message = "two map entries must produce exactly two role assignments."
  }

  assert {
    condition     = azurerm_role_assignment.vault["aks_kubelet"].role_definition_name == "Key Vault Secrets User"
    error_message = "the role must be passed as a readable name, not a GUID."
  }

  assert {
    condition     = endswith(azurerm_role_assignment.vault["deployer"].scope, "/vaults/kv-demo-dev")
    error_message = "assignments must be scoped to this vault, not to the resource group."
  }
}

run "exposes_vault_uri" {
  command = plan

  assert {
    condition     = output.vault_uri == "https://kv-demo-dev.vault.azure.net/"
    error_message = "vault_uri must be exposed — it is what SDKs and the CSI driver connect to."
  }
}
