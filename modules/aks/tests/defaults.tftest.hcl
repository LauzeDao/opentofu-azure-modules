mock_provider "azurerm" {
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.ContainerService/managedClusters/aks-demo-dev"
      oidc_issuer_url = "https://germanywestcentral.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"

      kube_config = [{
        host                   = "https://aks-demo-dev.hcp.germanywestcentral.azmk8s.io:443"
        client_certificate     = "bW9jay1jbGllbnQtY2VydA=="
        client_key             = "bW9jay1jbGllbnQta2V5"
        cluster_ca_certificate = "bW9jay1jYS1jZXJ0"
        username               = "clusterUser_rg-demo-dev_aks-demo-dev"
        password               = "mock-password"
      }]
    }
  }
}

variables {
  name                = "aks-demo-dev"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
}

run "plans_with_only_required_inputs" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.main.name == "aks-demo-dev"
    error_message = "name must reach the cluster unchanged."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.location == "germanywestcentral"
    error_message = "location must reach the cluster unchanged."
  }
}

run "oidc_issuer_and_workload_identity_are_always_enabled" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.main.oidc_issuer_enabled == true
    error_message = "oidc_issuer_enabled must be true even when the consumer says nothing — it is hard-coded on purpose (ADR 0004)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.workload_identity_enabled == true
    error_message = "workload_identity_enabled must be true even when the consumer says nothing — it is hard-coded on purpose (ADR 0004)."
  }
}

run "never_configures_a_service_principal" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.service_principal) == 0
    error_message = "a service_principal block would mean a long-lived client secret in state; the module must never configure one."
  }
}

run "dns_prefix_falls_back_to_name" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.main.dns_prefix == "aks-demo-dev"
    error_message = "dns_prefix must default to the cluster name."
  }
}

run "explicit_dns_prefix_wins" {
  command = plan

  variables {
    dns_prefix = "demo-dev-api"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.dns_prefix == "demo-dev-api"
    error_message = "an explicit dns_prefix must override the fallback."
  }
}

run "cost_conscious_defaults" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.main.sku_tier == "Free"
    error_message = "sku_tier must default to Free — a test cluster needs no uptime SLA."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].vm_size == "Standard_B2s"
    error_message = "the system node pool must default to the smallest sensible SKU."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].node_count == 1
    error_message = "the system node pool must default to a single node."
  }
}

run "network_defaults_use_overlay" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].network_plugin == "azure"
    error_message = "network_plugin must default to azure."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].network_plugin_mode == "overlay"
    error_message = "network_plugin_mode must default to overlay so pod IPs do not consume VNet address space."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].pod_cidr == "10.244.0.0/16"
    error_message = "pod_cidr must be set when overlay mode applies."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].service_cidr == "10.0.0.0/16"
    error_message = "service_cidr default must reach the cluster."
  }
}

run "omits_pod_cidr_for_plain_azure_cni" {
  command = plan

  variables {
    network_plugin      = "azure"
    network_plugin_mode = null
    pod_cidr            = "10.244.0.0/16"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].pod_cidr != "10.244.0.0/16"
    error_message = "pod_cidr must be omitted when neither kubenet nor overlay is in use."
  }
}

run "system_node_pool_gets_a_rotation_name" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].temporary_name_for_rotation == "systemtmp"
    error_message = "temporary_name_for_rotation must be set, otherwise any change forcing a pool rebuild fails."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.default_node_pool[0].temporary_name_for_rotation) <= 12
    error_message = "the rotation name must respect the 12-character node pool limit."
  }
}

run "entra_rbac_block_present_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control) == 1
    error_message = "azure_rbac_enabled defaults to true, so the Entra RBAC block must be present."
  }
}

run "entra_rbac_block_omitted_when_disabled" {
  command = plan

  variables {
    azure_rbac_enabled = false
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control) == 0
    error_message = "with azure_rbac_enabled = false the block must be absent, not empty."
  }
}

run "api_server_access_profile_omitted_when_no_ranges" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.api_server_access_profile) == 0
    error_message = "an empty authorized_ip_ranges must mean no api_server_access_profile block at all."
  }
}

run "api_server_access_profile_present_with_ranges" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["203.0.113.0/24", "198.51.100.10/32"]
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.api_server_access_profile) == 1
    error_message = "authorized ranges must produce an api_server_access_profile block."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.api_server_access_profile[0].authorized_ip_ranges) == 2
    error_message = "both ranges must reach the cluster."
  }
}

run "no_user_node_pools_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.user) == 0
    error_message = "user_node_pools must default to empty."
  }
}
