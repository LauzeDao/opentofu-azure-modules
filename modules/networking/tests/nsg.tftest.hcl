mock_provider "azurerm" {
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.Network/virtualNetworks/vnet-demo-dev/subnets/mock"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.Network/networkSecurityGroups/mock"
    }
  }
}

variables {
  name                = "vnet-demo-dev"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
  address_space       = ["10.42.0.0/16"]

  subnets = {
    system = {
      address_prefixes = ["10.42.0.0/22"]
    }
    user = {
      address_prefixes = ["10.42.4.0/22"]
    }
    restricted = {
      address_prefixes = ["10.42.8.0/24"]
      security_rules = [
        {
          name                       = "allow-https-inbound"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "Internet"
          destination_address_prefix = "*"
        },
        {
          name                       = "deny-all-inbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        },
      ]
    }
  }
}

run "creates_nsg_only_for_subnets_with_rules" {
  command = plan

  assert {
    condition     = length(azurerm_network_security_group.subnet_nsg) == 1
    error_message = "only the one subnet declaring security_rules may get an NSG — an empty NSG is noise, not security."
  }

  assert {
    condition     = contains(keys(azurerm_network_security_group.subnet_nsg), "restricted")
    error_message = "the NSG must belong to the subnet that declared the rules."
  }

  assert {
    condition     = !contains(keys(azurerm_network_security_group.subnet_nsg), "system")
    error_message = "a subnet without security_rules must not get an NSG."
  }
}

run "associates_nsg_with_its_own_subnet" {
  command = plan

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.subnet_nsg) == 1
    error_message = "exactly one association, for the one subnet that has an NSG."
  }

  assert {
    condition     = contains(keys(azurerm_subnet_network_security_group_association.subnet_nsg), "restricted")
    error_message = "the association must be keyed by the same subnet key."
  }
}

run "nsg_name_is_derived_from_vnet_and_subnet" {
  command = plan

  assert {
    condition     = azurerm_network_security_group.subnet_nsg["restricted"].name == "nsg-vnet-demo-dev-restricted"
    error_message = "NSG name must be nsg-<vnet>-<subnet key> so it is identifiable in the portal."
  }
}

run "all_rules_reach_the_nsg" {
  command = plan

  assert {
    condition     = length(azurerm_network_security_group.subnet_nsg["restricted"].security_rule) == 2
    error_message = "both declared rules must reach the NSG."
  }
}

run "creates_no_nsg_when_no_subnet_has_rules" {
  command = plan

  variables {
    subnets = {
      system = { address_prefixes = ["10.42.0.0/22"] }
      user   = { address_prefixes = ["10.42.4.0/22"] }
    }
  }

  assert {
    condition     = length(azurerm_network_security_group.subnet_nsg) == 0
    error_message = "no rules anywhere must mean no NSG resources at all."
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.subnet_nsg) == 0
    error_message = "no NSGs must mean no associations."
  }

  assert {
    condition     = length(output.nsg_ids) == 0
    error_message = "the nsg_ids output must be an empty map, not null."
  }
}

run "nsg_ids_output_covers_only_subnets_with_rules" {
  command = plan

  assert {
    condition     = join(",", keys(output.nsg_ids)) == "restricted"
    error_message = "nsg_ids must contain exactly the subnets that have an NSG."
  }
}

run "subnet_ids_output_covers_every_subnet" {
  command = plan

  assert {
    condition     = length(output.subnet_ids) == 3
    error_message = "subnet_ids must have one entry per input subnet."
  }

  assert {
    condition     = join(",", sort(keys(output.subnet_ids))) == "restricted,system,user"
    error_message = "subnet_ids keys must mirror the input map keys exactly."
  }
}
