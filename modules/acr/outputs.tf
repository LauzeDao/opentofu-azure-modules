output "id" {
  description = "Registry resource ID. Use as `scope` for additional role assignments made outside this module."
  value       = azurerm_container_registry.main.id
}

output "name" {
  description = "Registry name."
  value       = azurerm_container_registry.main.name
}

output "login_server" {
  description = "Registry login server, e.g. `demodevacr.azurecr.io`. This is the image prefix for your manifests."
  value       = azurerm_container_registry.main.login_server
}

output "role_assignment_ids" {
  description = "Map of role assignment key to its resource ID."
  value       = { for key, assignment in azurerm_role_assignment.registry : key => assignment.id }
}
