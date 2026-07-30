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

run "rejects_name_with_consecutive_hyphens" {
  command = plan

  variables {
    name = "kv--demo-dev"
  }

  expect_failures = [var.name]
}

run "rejects_name_starting_with_digit" {
  command = plan

  variables {
    name = "1kv-demo-dev"
  }

  expect_failures = [var.name]
}

run "rejects_name_ending_with_hyphen" {
  command = plan

  variables {
    name = "kv-demo-dev-"
  }

  expect_failures = [var.name]
}

run "rejects_name_longer_than_24" {
  command = plan

  variables {
    name = "kv-demo-dev-much-too-long"
  }

  expect_failures = [var.name]
}

run "rejects_name_shorter_than_3" {
  command = plan

  variables {
    name = "kv"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_underscore" {
  command = plan

  variables {
    name = "kv_demo_dev"
  }

  expect_failures = [var.name]
}

run "rejects_capitalised_sku" {
  command = plan

  variables {
    sku_name = "Standard"
  }

  expect_failures = [var.sku_name]
}

run "rejects_unknown_sku" {
  command = plan

  variables {
    sku_name = "basic"
  }

  expect_failures = [var.sku_name]
}

run "rejects_retention_below_7" {
  command = plan

  variables {
    soft_delete_retention_days = 6
  }

  expect_failures = [var.soft_delete_retention_days]
}

run "rejects_retention_above_90" {
  command = plan

  variables {
    soft_delete_retention_days = 91
  }

  expect_failures = [var.soft_delete_retention_days]
}

run "rejects_non_guid_tenant_id" {
  command = plan

  variables {
    tenant_id = "nope"
  }

  expect_failures = [var.tenant_id]
}

run "rejects_invalid_default_action" {
  command = plan

  variables {
    network_acls = {
      default_action = "Reject"
    }
  }

  expect_failures = [var.network_acls]
}

run "rejects_invalid_bypass" {
  command = plan

  variables {
    network_acls = {
      default_action = "Deny"
      bypass         = "Everything"
    }
  }

  expect_failures = [var.network_acls]
}

run "rejects_non_guid_principal_id" {
  command = plan

  variables {
    role_assignments = {
      deployer = {
        principal_id = "not-a-guid"
        role         = "Key Vault Administrator"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_empty_role" {
  command = plan

  variables {
    role_assignments = {
      deployer = {
        principal_id = "88888888-8888-8888-8888-888888888888"
        role         = ""
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_invalid_principal_type" {
  command = plan

  variables {
    role_assignments = {
      deployer = {
        principal_id   = "88888888-8888-8888-8888-888888888888"
        role           = "Key Vault Administrator"
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
