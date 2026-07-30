output "name" {
  description = "Resource group name. Feed this into every other module's `resource_group_name`."
  value       = azurerm_resource_group.main.name
}

output "id" {
  description = "Fully qualified resource group ID. Use as `scope` for role assignments at resource-group level."
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region of the resource group, so consumers need not carry the region separately."
  value       = azurerm_resource_group.main.location
}
