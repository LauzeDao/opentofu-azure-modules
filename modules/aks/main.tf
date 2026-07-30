locals {
  system_pool_rotation_name = substr("${var.system_node_pool.name}tmp", 0, 12)

  pod_cidr_applies = var.network_plugin == "kubenet" || var.network_plugin_mode == "overlay"

  system_node_count = var.system_node_pool.auto_scaling_enabled ? null : var.system_node_pool.node_count

  kubelet_identity = try(azurerm_kubernetes_cluster.main.kubelet_identity[0], {
    object_id                 = null
    client_id                 = null
    user_assigned_identity_id = null
  })
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = coalesce(var.dns_prefix, var.name)
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  automatic_upgrade_channel = var.automatic_upgrade_channel == "none" ? null : var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel
  local_account_disabled    = var.local_account_disabled
  private_cluster_enabled   = var.private_cluster_enabled
  cost_analysis_enabled     = var.cost_analysis_enabled
  azure_policy_enabled      = var.azure_policy_enabled
  disk_encryption_set_id    = var.disk_encryption_set_id

  image_cleaner_enabled        = var.image_cleaner_enabled
  image_cleaner_interval_hours = var.image_cleaner_enabled ? var.image_cleaner_interval_hours : null

  identity {
    type         = var.identity_type
    identity_ids = var.identity_type == "UserAssigned" ? var.identity_ids : null
  }

  default_node_pool {
    name    = var.system_node_pool.name
    vm_size = var.system_node_pool.vm_size

    node_count           = local.system_node_count
    auto_scaling_enabled = var.system_node_pool.auto_scaling_enabled
    min_count            = var.system_node_pool.auto_scaling_enabled ? var.system_node_pool.min_count : null
    max_count            = var.system_node_pool.auto_scaling_enabled ? var.system_node_pool.max_count : null

    only_critical_addons_enabled = var.system_node_pool.only_critical_addons_enabled

    vnet_subnet_id = var.system_node_pool.vnet_subnet_id
    pod_subnet_id  = var.system_node_pool.pod_subnet_id
    zones          = var.system_node_pool.zones

    os_disk_size_gb      = var.system_node_pool.os_disk_size_gb
    os_disk_type         = var.system_node_pool.os_disk_type
    os_sku               = var.system_node_pool.os_sku
    max_pods             = var.system_node_pool.max_pods
    node_labels          = var.system_node_pool.node_labels
    orchestrator_version = var.system_node_pool.orchestrator_version

    host_encryption_enabled = var.system_node_pool.host_encryption_enabled
    node_public_ip_enabled  = var.system_node_pool.node_public_ip_enabled

    temporary_name_for_rotation = local.system_pool_rotation_name
    tags                        = var.tags
  }

  network_profile {
    network_plugin      = var.network_plugin
    network_plugin_mode = var.network_plugin_mode
    network_policy      = var.network_policy
    network_data_plane  = var.network_data_plane
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = local.pod_cidr_applies ? var.pod_cidr : null
    load_balancer_sku   = var.load_balancer_sku
    outbound_type       = var.outbound_type
  }

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.azure_rbac_enabled ? [1] : []

    content {
      azure_rbac_enabled     = true
      admin_group_object_ids = var.admin_group_object_ids
      tenant_id              = var.tenant_id
    }
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.key_vault_secrets_provider == null ? [] : [var.key_vault_secrets_provider]

    content {
      secret_rotation_enabled = key_vault_secrets_provider.value.secret_rotation_enabled

      secret_rotation_interval = (
        key_vault_secrets_provider.value.secret_rotation_enabled
        ? key_vault_secrets_provider.value.secret_rotation_interval
        : null
      )
    }
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []

    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.user_node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  mode                  = each.value.mode

  node_count           = each.value.auto_scaling_enabled ? null : each.value.node_count
  auto_scaling_enabled = each.value.auto_scaling_enabled
  min_count            = each.value.auto_scaling_enabled ? each.value.min_count : null
  max_count            = each.value.auto_scaling_enabled ? each.value.max_count : null

  node_taints = each.value.node_taints
  node_labels = each.value.node_labels

  priority        = each.value.priority
  eviction_policy = each.value.eviction_policy
  spot_max_price  = each.value.priority == "Spot" ? each.value.spot_max_price : null

  vnet_subnet_id = each.value.vnet_subnet_id
  pod_subnet_id  = each.value.pod_subnet_id
  zones          = each.value.zones

  os_disk_size_gb      = each.value.os_disk_size_gb
  os_disk_type         = each.value.os_disk_type
  os_sku               = each.value.os_sku
  os_type              = each.value.os_type
  max_pods             = each.value.max_pods
  orchestrator_version = each.value.orchestrator_version

  host_encryption_enabled = each.value.host_encryption_enabled
  node_public_ip_enabled  = each.value.node_public_ip_enabled

  temporary_name_for_rotation = substr("${each.key}tmp", 0, 12)
  tags                        = var.tags
}
