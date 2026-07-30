locals {
  subnets_with_nsg = {
    for key, subnet in var.subnets : key => subnet
    if length(subnet.security_rules) > 0
  }
}

resource "azurerm_virtual_network" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "subnets" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name

  address_prefixes                  = each.value.address_prefixes
  service_endpoints                 = each.value.service_endpoints
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = each.value.default_outbound_access_enabled

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]

    content {
      name = delegation.value.name

      service_delegation {
        name    = delegation.value.service
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "subnet_nsg" {
  for_each = local.subnets_with_nsg

  name                = "nsg-${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule = [
    for rule in each.value.security_rules : {
      name        = rule.name
      priority    = rule.priority
      direction   = rule.direction
      access      = rule.access
      protocol    = rule.protocol
      description = rule.description

      source_port_range       = rule.source_port_range
      source_port_ranges      = rule.source_port_ranges
      destination_port_range  = rule.destination_port_range
      destination_port_ranges = rule.destination_port_ranges

      source_address_prefix        = rule.source_address_prefix
      source_address_prefixes      = rule.source_address_prefixes
      destination_address_prefix   = rule.destination_address_prefix
      destination_address_prefixes = rule.destination_address_prefixes

      source_application_security_group_ids      = rule.source_application_security_group_ids
      destination_application_security_group_ids = rule.destination_application_security_group_ids
    }
  ]
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  for_each = local.subnets_with_nsg

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.subnet_nsg[each.key].id
}
