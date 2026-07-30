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

run "rejects_name_with_hyphen" {
  command = plan

  variables {
    name = "demo-dev-acr"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_underscore" {
  command = plan

  variables {
    name = "demo_dev_acr"
  }

  expect_failures = [var.name]
}

run "rejects_name_shorter_than_5" {
  command = plan

  variables {
    name = "acr"
  }

  expect_failures = [var.name]
}

run "rejects_name_longer_than_50" {
  command = plan

  variables {
    name = "acrxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_sku" {
  command = plan

  variables {
    sku = "Free"
  }

  expect_failures = [var.sku]
}

run "rejects_zone_redundancy_on_basic" {
  command = plan

  variables {
    sku                     = "Basic"
    zone_redundancy_enabled = true
  }

  expect_failures = [var.zone_redundancy_enabled]
}

run "rejects_georeplication_on_basic" {
  command = plan

  variables {
    sku             = "Basic"
    georeplications = [{ location = "westeurope" }]
  }

  expect_failures = [var.georeplications]
}

run "rejects_retention_policy_on_basic" {
  command = plan

  variables {
    sku                      = "Basic"
    retention_policy_in_days = 30
  }

  expect_failures = [var.retention_policy_in_days]
}

run "rejects_trust_policy_on_basic" {
  command = plan

  variables {
    sku                  = "Basic"
    trust_policy_enabled = true
  }

  expect_failures = [var.trust_policy_enabled]
}

run "rejects_quarantine_policy_on_basic" {
  command = plan

  variables {
    sku                       = "Basic"
    quarantine_policy_enabled = true
  }

  expect_failures = [var.quarantine_policy_enabled]
}

run "rejects_data_endpoint_on_basic" {
  command = plan

  variables {
    sku                   = "Basic"
    data_endpoint_enabled = true
  }

  expect_failures = [var.data_endpoint_enabled]
}

run "rejects_anonymous_pull_on_basic" {
  command = plan

  variables {
    sku                    = "Basic"
    anonymous_pull_enabled = true
  }

  expect_failures = [var.anonymous_pull_enabled]
}

run "rejects_georeplication_to_own_location" {
  command = plan

  variables {
    sku             = "Premium"
    location        = "germanywestcentral"
    georeplications = [{ location = "germanywestcentral" }]
  }

  expect_failures = [var.georeplications]
}

run "rejects_georeplication_display_name_location" {
  command = plan

  variables {
    sku             = "Premium"
    georeplications = [{ location = "West Europe" }]
  }

  expect_failures = [var.georeplications]
}

run "rejects_retention_policy_out_of_range" {
  command = plan

  variables {
    sku                      = "Premium"
    retention_policy_in_days = 400
  }

  expect_failures = [var.retention_policy_in_days]
}

run "rejects_non_guid_principal_id" {
  command = plan

  variables {
    role_assignments = {
      aks_kubelet = {
        principal_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/x"
        role         = "AcrPull"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_empty_role" {
  command = plan

  variables {
    role_assignments = {
      aks_kubelet = {
        principal_id = "22222222-2222-2222-2222-222222222222"
        role         = "   "
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_invalid_principal_type" {
  command = plan

  variables {
    role_assignments = {
      aks_kubelet = {
        principal_id   = "22222222-2222-2222-2222-222222222222"
        role           = "AcrPull"
        principal_type = "Robot"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_location_display_name" {
  command = plan

  variables {
    location = "Germany West Central"
  }

  expect_failures = [var.location]
}
