mock_provider "azurerm" {
  mock_resource "azurerm_container_registry" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.ContainerRegistry/registries/demodevacr"
      login_server = "demodevacr.azurecr.io"
    }
  }
}

variables {
  name                = "demodevacr"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
}

run "plans_with_only_required_inputs" {
  command = plan

  assert {
    condition     = azurerm_container_registry.main.name == "demodevacr"
    error_message = "name must reach the registry unchanged."
  }

  assert {
    condition     = azurerm_container_registry.main.sku == "Basic"
    error_message = "sku must default to Basic — the cheapest SKU keeps test runs affordable."
  }
}

run "admin_account_is_disabled_by_default" {
  command = plan

  assert {
    condition     = azurerm_container_registry.main.admin_enabled == false
    error_message = "admin_enabled must default to false — it is a shared credential with full push/pull rights (ADR 0005)."
  }
}

run "anonymous_pull_is_disabled_by_default" {
  command = plan

  assert {
    condition     = azurerm_container_registry.main.anonymous_pull_enabled == false
    error_message = "anonymous_pull_enabled must default to false."
  }
}

run "premium_only_features_default_off" {
  command = plan

  assert {
    condition     = azurerm_container_registry.main.zone_redundancy_enabled == false
    error_message = "zone_redundancy_enabled must default to false so the Basic SKU stays valid."
  }

  assert {
    condition     = azurerm_container_registry.main.trust_policy_enabled == false
    error_message = "trust_policy_enabled must default to false."
  }

  assert {
    condition     = azurerm_container_registry.main.quarantine_policy_enabled == false
    error_message = "quarantine_policy_enabled must default to false."
  }

  assert {
    condition     = azurerm_container_registry.main.retention_policy_in_days == null
    error_message = "retention_policy_in_days must default to null."
  }

  assert {
    condition     = length(azurerm_container_registry.main.georeplications) == 0
    error_message = "georeplications must default to empty."
  }
}

run "premium_features_accepted_on_premium_sku" {
  command = plan

  variables {
    sku                       = "Premium"
    zone_redundancy_enabled   = true
    trust_policy_enabled      = true
    quarantine_policy_enabled = true
    retention_policy_in_days  = 30
    data_endpoint_enabled     = true

    georeplications = [{
      location                = "westeurope"
      zone_redundancy_enabled = true
    }]
  }

  assert {
    condition     = azurerm_container_registry.main.sku == "Premium"
    error_message = "sku must reach the registry."
  }

  assert {
    condition     = azurerm_container_registry.main.retention_policy_in_days == 30
    error_message = "retention_policy_in_days must reach the registry on Premium."
  }

  assert {
    condition     = length(azurerm_container_registry.main.georeplications) == 1
    error_message = "a georeplication entry must produce one georeplications block."
  }

  assert {
    condition     = azurerm_container_registry.main.georeplications[0].location == "westeurope"
    error_message = "the georeplication location must be passed through."
  }
}

run "exposes_login_server" {
  command = plan

  assert {
    condition     = output.login_server == "demodevacr.azurecr.io"
    error_message = "login_server must be exposed — it is the image prefix consumers need."
  }
}

run "tags_reach_the_registry" {
  command = plan

  variables {
    tags = { environment = "dev" }
  }

  assert {
    condition     = azurerm_container_registry.main.tags["environment"] == "dev"
    error_message = "tags must reach the registry."
  }
}
