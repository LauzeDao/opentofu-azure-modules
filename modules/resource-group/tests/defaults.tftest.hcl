mock_provider "azurerm" {}

variables {
  name     = "rg-demo-dev"
  location = "germanywestcentral"
}

run "creates_resource_group_with_defaults" {
  command = plan

  assert {
    condition     = azurerm_resource_group.main.name == "rg-demo-dev"
    error_message = "name must be passed through unchanged — no hidden lower() or prefixing."
  }

  assert {
    condition     = azurerm_resource_group.main.location == "germanywestcentral"
    error_message = "location must be passed through unchanged."
  }

  assert {
    condition     = length(azurerm_resource_group.main.tags) == 0
    error_message = "tags must default to an empty map, not null."
  }
}

run "applies_tags" {
  command = plan

  variables {
    tags = {
      environment = "dev"
      managed_by  = "opentofu"
    }
  }

  assert {
    condition     = azurerm_resource_group.main.tags["environment"] == "dev"
    error_message = "tags must reach the resource group."
  }

  assert {
    condition     = length(azurerm_resource_group.main.tags) == 2
    error_message = "the module must not inject tags of its own."
  }
}

run "accepts_maximum_length_name" {
  command = plan

  variables {
    name = "rg-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  }

  assert {
    condition     = length(azurerm_resource_group.main.name) == 90
    error_message = "a 90-character name is valid and must be accepted."
  }
}

run "accepts_azure_permitted_special_characters" {
  command = plan

  variables {
    name = "rg_demo-dev.01(eu)"
  }

  assert {
    condition     = azurerm_resource_group.main.name == "rg_demo-dev.01(eu)"
    error_message = "underscore, hyphen, period and parentheses are all legal in a resource group name."
  }
}
