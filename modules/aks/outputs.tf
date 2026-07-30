output "id" {
  description = "Cluster resource ID."
  value       = azurerm_kubernetes_cluster.main.id
}

output "name" {
  description = "Cluster name."
  value       = azurerm_kubernetes_cluster.main.name
}

output "fqdn" {
  description = "Public FQDN of the API server. Empty for a private cluster — use `private_fqdn` there."
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "private_fqdn" {
  description = "Private FQDN of the API server. Only populated when `private_cluster_enabled` is true."
  value       = azurerm_kubernetes_cluster.main.private_fqdn
}

output "node_resource_group" {
  description = "The Azure-managed `MC_…` resource group holding node VMs, disks and load balancers."
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kubernetes_version" {
  description = "Kubernetes version actually running — resolves what Azure chose when `kubernetes_version` was left null."
  value       = azurerm_kubernetes_cluster.main.kubernetes_version
}

output "current_kubernetes_version" {
  description = "Full patch-level version currently deployed, e.g. `1.31.3` even when only `1.31` was requested."
  value       = azurerm_kubernetes_cluster.main.current_kubernetes_version
}

output "oidc_issuer_url" {
  description = <<-EOT
    OIDC issuer URL of the cluster. Always populated, because the module hard-codes
    `oidc_issuer_enabled = true` (ADR 0004).

    This is what you point a federated identity credential at to give a Kubernetes
    ServiceAccount an Azure identity without any secret in the cluster.
  EOT
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = <<-EOT
    Object (principal) ID of the kubelet identity — the identity nodes use to pull images
    and mount CSI secrets.

    This is the value the ACR module needs for its `AcrPull` role assignment.
  EOT
  value       = local.kubelet_identity.object_id
}

output "kubelet_identity_client_id" {
  description = "Client ID of the kubelet identity."
  value       = local.kubelet_identity.client_id
}

output "kubelet_identity_id" {
  description = "Resource ID of the kubelet user-assigned managed identity."
  value       = local.kubelet_identity.user_assigned_identity_id
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the control plane identity. Needs e.g. Network Contributor when the subnet lives in another resource group."
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

output "cluster_identity_tenant_id" {
  description = "Tenant ID of the control plane identity."
  value       = azurerm_kubernetes_cluster.main.identity[0].tenant_id
}

output "user_node_pool_ids" {
  description = "Map of user node pool name to its resource ID."
  value       = { for name, pool in azurerm_kubernetes_cluster_node_pool.user : name => pool.id }
}

output "kube_config_raw" {
  description = "Complete kubeconfig for the local admin account. Empty when `local_account_disabled` is true."
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "host" {
  description = "API server endpoint, for configuring the `kubernetes` provider in a consumer."
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "client_certificate" {
  description = "Base64-encoded client certificate for cluster authentication."
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64-encoded client private key for cluster authentication."
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive   = true
}
