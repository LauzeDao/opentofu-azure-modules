output "resource_group_name" {
  description = "Resource group holding the cluster — needed for `az aks get-credentials`."
  value       = module.resource_group.name
}

output "aks_cluster_name" {
  description = "Cluster name — needed for `az aks get-credentials`."
  value       = module.aks.name
}

output "get_credentials_command" {
  description = "Ready-to-run command to configure kubectl against this cluster."
  value       = "az aks get-credentials --resource-group ${module.resource_group.name} --name ${module.aks.name}"
}

output "aks_fqdn" {
  description = "Public FQDN of the Kubernetes API server."
  value       = module.aks.fqdn
}

output "node_resource_group" {
  description = "The Azure-managed `MC_…` resource group holding node VMs, disks and load balancers."
  value       = module.aks.node_resource_group
}

output "kubernetes_version" {
  description = "Kubernetes version the cluster actually runs — resolves the Azure default when none was pinned."
  value       = module.aks.current_kubernetes_version
}

output "oidc_issuer_url" {
  description = <<-EOT
    The cluster's OIDC issuer URL. Point a federated identity credential at this to give a
    Kubernetes ServiceAccount an Azure identity with no secret in the cluster.
  EOT
  value       = module.aks.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity that holds AcrPull on the registry."
  value       = module.aks.kubelet_identity_object_id
}

output "acr_login_server" {
  description = "Registry login server — the image prefix for manifests, e.g. `acrdemodev.azurecr.io/myapp:1.0`."
  value       = module.acr.login_server
}

output "acr_name" {
  description = "Registry name, for `az acr login --name`."
  value       = module.acr.name
}

output "key_vault_name" {
  description = "Key Vault name, for `az keyvault secret set --vault-name`."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "Key Vault data-plane URI."
  value       = module.key_vault.vault_uri
}

output "verification_commands" {
  description = "The commands that actually prove this example worked — see docs/build-spec/05-example-root.md §6."
  value = join("\n", [
    "az aks get-credentials --resource-group ${module.resource_group.name} --name ${module.aks.name} --overwrite-existing",
    "kubectl get nodes",
    "az acr login --name ${module.acr.name}",
  ])
}
