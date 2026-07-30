output "vnet_id" {
  description = "Virtual network ID. Needed for peerings and private DNS zone links."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.main.name
}

output "vnet_address_space" {
  description = "Address space of the virtual network, echoed back for consumers that derive further CIDRs."
  value       = azurerm_virtual_network.main.address_space
}

output "subnet_ids" {
  description = "Map of subnet key to subnet ID — feed directly into e.g. the AKS module's `vnet_subnet_id`."
  value       = { for key, subnet in azurerm_subnet.subnets : key => subnet.id }
}

output "subnet_names" {
  description = "Map of subnet key to the subnet's actual Azure name."
  value       = { for key, subnet in azurerm_subnet.subnets : key => subnet.name }
}

output "subnet_address_prefixes" {
  description = "Map of subnet key to its address prefixes, so consumers can build NSG rules without restating CIDRs."
  value       = { for key, subnet in azurerm_subnet.subnets : key => subnet.address_prefixes }
}

output "nsg_ids" {
  description = "Map of subnet key to network security group ID. Only contains entries for subnets that declared `security_rules`."
  value       = { for key, nsg in azurerm_network_security_group.subnet_nsg : key => nsg.id }
}
