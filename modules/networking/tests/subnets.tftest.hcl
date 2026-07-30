mock_provider "azurerm" {}

variables {
  name                = "vnet-demo-dev"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
  address_space       = ["10.42.0.0/16"]

  subnets = {
    system = {
      address_prefixes  = ["10.42.0.0/22"]
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    }
    user = {
      address_prefixes = ["10.42.4.0/22"]
    }
    private_endpoints = {
      address_prefixes                  = ["10.42.8.0/24"]
      private_endpoint_network_policies = "Disabled"
    }
  }
}

run "creates_one_subnet_per_map_entry" {
  command = plan

  assert {
    condition     = length(azurerm_subnet.subnets) == 3
    error_message = "three map entries must produce exactly three subnets."
  }

  assert {
    condition = alltrue([
      for key in ["system", "user", "private_endpoints"] : contains(keys(azurerm_subnet.subnets), key)
    ])
    error_message = "subnet resource keys must match the input map keys, so state addresses stay stable."
  }
}

run "subnet_name_matches_map_key" {
  command = plan

  assert {
    condition     = azurerm_subnet.subnets["system"].name == "system"
    error_message = "the subnet's Azure name is taken from the map key."
  }
}

run "passes_through_address_prefixes" {
  command = plan

  assert {
    condition     = azurerm_subnet.subnets["user"].address_prefixes == tolist(["10.42.4.0/22"])
    error_message = "address_prefixes must reach the correct subnet."
  }
}

run "passes_through_service_endpoints" {
  command = plan

  assert {
    condition     = length(azurerm_subnet.subnets["system"].service_endpoints) == 2
    error_message = "service_endpoints must reach the subnet that declared them."
  }

  assert {
    condition     = length(azurerm_subnet.subnets["user"].service_endpoints) == 0
    error_message = "a subnet that declared no service endpoints must not inherit any."
  }
}

run "defaults_private_endpoint_network_policies_to_enabled" {
  command = plan

  assert {
    condition     = azurerm_subnet.subnets["user"].private_endpoint_network_policies == "Enabled"
    error_message = "private_endpoint_network_policies must default to Enabled."
  }

  assert {
    condition     = azurerm_subnet.subnets["private_endpoints"].private_endpoint_network_policies == "Disabled"
    error_message = "an explicit private_endpoint_network_policies value must win over the default."
  }
}

run "vnet_carries_address_space_and_tags" {
  command = plan

  variables {
    tags = { environment = "dev" }
  }

  assert {
    condition     = azurerm_virtual_network.main.address_space == toset(["10.42.0.0/16"])
    error_message = "address_space must reach the virtual network."
  }

  assert {
    condition     = azurerm_virtual_network.main.tags["environment"] == "dev"
    error_message = "tags must reach the virtual network."
  }

  assert {
    condition     = length(azurerm_virtual_network.main.dns_servers) == 0
    error_message = "dns_servers must default to empty (meaning Azure-provided DNS)."
  }
}

run "supports_subnet_delegation" {
  command = plan

  variables {
    subnets = {
      aci = {
        address_prefixes = ["10.42.12.0/24"]
        delegation = {
          name    = "aci-delegation"
          service = "Microsoft.ContainerInstance/containerGroups"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_subnet.subnets["aci"].delegation) == 1
    error_message = "a configured delegation must produce exactly one delegation block."
  }

  assert {
    condition     = azurerm_subnet.subnets["aci"].delegation[0].name == "aci-delegation"
    error_message = "the delegation name must be passed through."
  }
}

run "omits_delegation_when_not_configured" {
  command = plan

  assert {
    condition     = length(azurerm_subnet.subnets["user"].delegation) == 0
    error_message = "no delegation configured must mean no delegation block at all."
  }
}
