resource "azurerm_container_registry" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  tags                = var.tags

  admin_enabled = var.admin_enabled

  public_network_access_enabled = var.public_network_access_enabled
  anonymous_pull_enabled        = var.anonymous_pull_enabled
  data_endpoint_enabled         = var.data_endpoint_enabled
  zone_redundancy_enabled       = var.zone_redundancy_enabled
  retention_policy_in_days      = var.retention_policy_in_days
  trust_policy_enabled          = var.trust_policy_enabled
  quarantine_policy_enabled     = var.quarantine_policy_enabled

  dynamic "georeplications" {
    for_each = var.georeplications

    content {
      location                  = georeplications.value.location
      zone_redundancy_enabled   = georeplications.value.zone_redundancy_enabled
      regional_endpoint_enabled = georeplications.value.regional_endpoint_enabled
      tags                      = georeplications.value.tags
    }
  }
}

resource "azurerm_role_assignment" "registry" {
  for_each = var.role_assignments

  scope                = azurerm_container_registry.main.id
  principal_id         = each.value.principal_id
  role_definition_name = each.value.role
  principal_type       = each.value.principal_type
  description          = each.value.description
}
