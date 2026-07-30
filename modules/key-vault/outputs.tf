output "id" {
  description = "Vault resource ID. Use as `scope` for additional role assignments made outside this module."
  value       = azurerm_key_vault.main.id
}

output "name" {
  description = "Vault name."
  value       = azurerm_key_vault.main.name
}

output "vault_uri" {
  description = "Vault data-plane URI, e.g. `https://kv-demo-dev.vault.azure.net/`. This is what SDKs and the CSI driver connect to."
  value       = azurerm_key_vault.main.vault_uri
}

output "tenant_id" {
  description = "Tenant the vault belongs to, echoed back for consumers configuring clients against it."
  value       = azurerm_key_vault.main.tenant_id
}

output "role_assignment_ids" {
  description = "Map of role assignment key to its resource ID."
  value       = { for key, assignment in azurerm_role_assignment.vault : key => assignment.id }
}
