mock_provider "azurerm" {}

variables {
  name                = "vnet-demo-dev"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
  address_space       = ["10.42.0.0/16"]

  subnets = {
    system = { address_prefixes = ["10.42.0.0/22"] }
  }
}

run "rejects_malformed_vnet_cidr" {
  command = plan

  variables {
    address_space = ["10.42.0.0/33"]
  }

  expect_failures = [var.address_space]
}

run "rejects_non_cidr_vnet_address" {
  command = plan

  variables {
    address_space = ["not-a-cidr"]
  }

  expect_failures = [var.address_space]
}

run "rejects_empty_address_space" {
  command = plan

  variables {
    address_space = []
  }

  expect_failures = [var.address_space]
}

run "rejects_empty_subnets_map" {
  command = plan

  variables {
    subnets = {}
  }

  expect_failures = [var.subnets]
}

run "rejects_subnet_without_address_prefix" {
  command = plan

  variables {
    subnets = {
      system = { address_prefixes = [] }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_malformed_subnet_cidr" {
  command = plan

  variables {
    subnets = {
      system = { address_prefixes = ["10.42.0.0/99"] }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_invalid_private_endpoint_network_policies" {
  command = plan

  variables {
    subnets = {
      system = {
        address_prefixes                  = ["10.42.0.0/22"]
        private_endpoint_network_policies = "Maybe"
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_priority_below_100" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [{
          name                       = "bad-priority"
          priority                   = 99
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_priority_above_4096" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [{
          name                       = "bad-priority"
          priority                   = 5000
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_invalid_direction" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [{
          name                       = "sideways"
          priority                   = 100
          direction                  = "Sideways"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_invalid_access" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [{
          name                       = "maybe"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Perhaps"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_invalid_protocol" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [{
          name                       = "carrier-pigeon"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Pigeon"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_both_singular_and_plural_port_form" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [{
          name                       = "both-forms"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          destination_port_ranges    = ["443", "8443"]
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_neither_singular_nor_plural_port_form" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [{
          name                       = "no-destination-port"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_duplicate_rule_priorities" {
  command = plan

  variables {
    subnets = {
      restricted = {
        address_prefixes = ["10.42.8.0/24"]
        security_rules = [
          {
            name                       = "first"
            priority                   = 100
            direction                  = "Inbound"
            access                     = "Allow"
            protocol                   = "Tcp"
            source_port_range          = "*"
            destination_port_range     = "443"
            source_address_prefix      = "*"
            destination_address_prefix = "*"
          },
          {
            name                       = "second"
            priority                   = 100
            direction                  = "Inbound"
            access                     = "Allow"
            protocol                   = "Tcp"
            source_port_range          = "*"
            destination_port_range     = "80"
            source_address_prefix      = "*"
            destination_address_prefix = "*"
          },
        ]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_location_display_name" {
  command = plan

  variables {
    location = "Germany West Central"
  }

  expect_failures = [var.location]
}

run "rejects_non_ipv4_dns_server" {
  command = plan

  variables {
    dns_servers = ["dns.example.com"]
  }

  expect_failures = [var.dns_servers]
}
