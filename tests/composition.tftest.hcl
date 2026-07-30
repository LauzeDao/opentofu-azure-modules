mock_provider "azurerm" {
  mock_resource "azurerm_container_registry" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.ContainerRegistry/registries/acrdemodev"
      login_server = "acrdemodev.azurecr.io"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.KeyVault/vaults/kv-demo-dev"
      vault_uri = "https://kv-demo-dev.vault.azure.net/"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.Network/virtualNetworks/vnet-demo-dev/subnets/mock"
    }
  }
}

variables {
  subscription_id       = "00000000-0000-0000-0000-000000000000"
  tenant_id             = "11111111-1111-1111-1111-111111111111"
  deployer_principal_id = "88888888-8888-8888-8888-888888888888"

  project     = "demo"
  environment = "dev"
}

run "naming_follows_the_convention" {
  command = plan

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-demo-dev"
      fqdn                       = "aks-demo-dev.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg-demo-dev_aks-demo-dev_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://germanywestcentral.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = module.resource_group.name == "rg-demo-dev"
    error_message = "the resource group name must follow <resource>-<project>-<env>."
  }

  assert {
    condition     = module.networking.vnet_name == "vnet-demo-dev"
    error_message = "the vnet name must follow the naming convention."
  }

  assert {
    condition     = module.key_vault.name == "kv-demo-dev"
    error_message = "the vault name must follow the naming convention."
  }
}

run "acr_name_is_normalised_for_azures_stricter_rule" {
  command = plan

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-demo-dev"
      fqdn                       = "aks-demo-dev.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg-demo-dev_aks-demo-dev_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://example.invalid/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = module.acr.name == "acrdemodev"
    error_message = "the ACR name must be normalised to alphanumeric-only, since Azure Container Registry forbids hyphens."
  }

  assert {
    condition     = !can(regex("-", module.acr.name))
    error_message = "the ACR name must contain no hyphens at all."
  }

  assert {
    condition     = length(module.acr.name) >= 5 && length(module.acr.name) <= 50
    error_message = "the ACR name must stay within Azure's 5-50 character range."
  }
}

run "key_vault_name_stays_within_24_characters" {
  command = plan

  variables {
    project     = "abcdefgh"
    environment = "stage"
  }

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-abcdefgh-stage"
      fqdn                       = "aks.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg_aks_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://example.invalid/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = length(module.key_vault.name) <= 24
    error_message = "the derived Key Vault name must never exceed Azure's 24-character limit."
  }

  assert {
    condition     = length(module.acr.name) <= 50
    error_message = "the derived ACR name must stay within 50 characters even at maximum input length."
  }
}

run "subnets_are_derived_from_a_single_cidr" {
  command = plan

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-demo-dev"
      fqdn                       = "aks-demo-dev.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg-demo-dev_aks-demo-dev_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://example.invalid/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = length(module.networking.subnet_ids) == 2
    error_message = "the example must create exactly the system and user subnets."
  }

  assert {
    condition     = join(",", sort(keys(module.networking.subnet_ids))) == "system,user"
    error_message = "subnet keys must be `system` and `user`."
  }

  assert {
    condition     = module.networking.subnet_address_prefixes["system"] == tolist(["10.42.0.0/22"])
    error_message = "the system subnet must be the first /22 carved out of the default /16."
  }

  assert {
    condition     = module.networking.subnet_address_prefixes["user"] == tolist(["10.42.4.0/22"])
    error_message = "the user subnet must be the second /22, non-overlapping with the system subnet."
  }
}

run "subnet_derivation_adapts_to_a_smaller_vnet" {
  command = plan

  variables {
    vnet_address_space = "10.10.0.0/20"
  }

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-demo-dev"
      fqdn                       = "aks-demo-dev.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg-demo-dev_aks-demo-dev_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://example.invalid/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = module.networking.subnet_address_prefixes["system"] == tolist(["10.10.0.0/22"])
    error_message = "cidrsubnet must adapt to the supplied prefix length rather than assuming a /16."
  }

  assert {
    condition     = module.networking.subnet_address_prefixes["user"] == tolist(["10.10.4.0/22"])
    error_message = "the second subnet must remain non-overlapping at /20."
  }
}

run "acr_pull_is_granted_to_the_cluster_kubelet" {
  command = plan

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-demo-dev"
      fqdn                       = "aks-demo-dev.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg-demo-dev_aks-demo-dev_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://example.invalid/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = join(",", keys(module.acr.role_assignment_ids)) == "aks_kubelet"
    error_message = "the registry must grant exactly one role — AcrPull to the cluster's kubelet identity."
  }
}

run "key_vault_grants_deployer_and_kubelet_by_default" {
  command = plan

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-demo-dev"
      fqdn                       = "aks-demo-dev.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg-demo-dev_aks-demo-dev_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://example.invalid/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = contains(keys(module.key_vault.role_assignment_ids), "deployer")
    error_message = "the deploying identity needs a data-plane role, or the RBAC vault is unusable even for a subscription Owner."
  }

  assert {
    condition     = contains(keys(module.key_vault.role_assignment_ids), "aks_kubelet")
    error_message = "grant_kubelet_key_vault_access defaults to true, so the kubelet assignment must exist."
  }

  assert {
    condition     = length(module.key_vault.role_assignment_ids) == 2
    error_message = "exactly two assignments are expected by default."
  }
}

run "kubelet_key_vault_access_can_be_declined" {
  command = plan

  variables {
    grant_kubelet_key_vault_access = false
  }

  override_module {
    target = module.aks
    outputs = {
      name                       = "aks-demo-dev"
      fqdn                       = "aks-demo-dev.hcp.germanywestcentral.azmk8s.io"
      node_resource_group        = "MC_rg-demo-dev_aks-demo-dev_germanywestcentral"
      current_kubernetes_version = "1.31.3"
      oidc_issuer_url            = "https://example.invalid/"
      kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
      user_node_pool_ids         = {}
    }
  }

  assert {
    condition     = join(",", keys(module.key_vault.role_assignment_ids)) == "deployer"
    error_message = "with grant_kubelet_key_vault_access = false only the deployer assignment may remain."
  }
}
