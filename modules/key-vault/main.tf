resource "azurerm_key_vault" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = var.sku_name
  tags                = var.tags

  rbac_authorization_enabled = true

  soft_delete_retention_days = var.soft_delete_retention_days

  purge_protection_enabled = var.purge_protection_enabled

  public_network_access_enabled   = var.public_network_access_enabled
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_template_deployment = var.enabled_for_template_deployment

  dynamic "network_acls" {
    for_each = var.network_acls == null ? [] : [var.network_acls]

    content {
      default_action             = network_acls.value.default_action
      bypass                     = network_acls.value.bypass
      ip_rules                   = network_acls.value.ip_rules
      virtual_network_subnet_ids = network_acls.value.virtual_network_subnet_ids
    }
  }
}

resource "azurerm_role_assignment" "vault" {
  for_each = var.role_assignments

  scope                = azurerm_key_vault.main.id
  principal_id         = each.value.principal_id
  role_definition_name = each.value.role
  principal_type       = each.value.principal_type
  description          = each.value.description
}
