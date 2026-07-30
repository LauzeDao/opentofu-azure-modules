mock_provider "azurerm" {
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.ContainerService/managedClusters/aks-demo-dev"
      oidc_issuer_url = "https://germanywestcentral.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"

      kube_config = [{
        host                   = "https://aks-demo-dev.hcp.germanywestcentral.azmk8s.io:443"
        client_certificate     = "bW9jaw=="
        client_key             = "bW9jaw=="
        cluster_ca_certificate = "bW9jaw=="
        username               = "clusterUser"
        password               = "mock"
      }]
    }
  }
}

variables {
  name                = "aks-demo-dev"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
}

run "creates_one_node_pool_per_map_entry" {
  command = plan

  variables {
    user_node_pools = {
      apps = { vm_size = "Standard_D2s_v5" }
      data = { vm_size = "Standard_D2s_v5" }
      edge = { vm_size = "Standard_B2s" }
    }
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.user) == 3
    error_message = "three map entries must produce exactly three node pools."
  }

  assert {
    condition     = join(",", sort(keys(azurerm_kubernetes_cluster_node_pool.user))) == "apps,data,edge"
    error_message = "node pool resource keys must mirror the input map keys, so state addresses stay stable."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["apps"].name == "apps"
    error_message = "the pool's Azure name is taken from the map key."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["apps"].mode == "User"
    error_message = "user node pools must default to mode User."
  }
}

run "system_pool_autoscaling_sets_bounds_and_drops_node_count" {
  command = plan

  variables {
    system_node_pool = {
      auto_scaling_enabled = true
      min_count            = 2
      max_count            = 5
      node_count           = 7
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].auto_scaling_enabled == true
    error_message = "auto_scaling_enabled must reach the default node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].min_count == 2
    error_message = "min_count must reach the default node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].max_count == 5
    error_message = "max_count must reach the default node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].node_count != 7
    error_message = "node_count must not be sent when autoscaling is enabled."
  }
}

run "system_pool_without_autoscaling_omits_bounds" {
  command = plan

  variables {
    system_node_pool = {
      node_count = 3
      min_count  = 2
      max_count  = 5
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].node_count == 3
    error_message = "node_count must be sent when autoscaling is off."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].min_count != 2
    error_message = "min_count must not be sent when autoscaling is off."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].max_count != 5
    error_message = "max_count must not be sent when autoscaling is off."
  }
}

run "user_pool_autoscaling_behaves_the_same" {
  command = plan

  variables {
    user_node_pools = {
      apps = {
        auto_scaling_enabled = true
        min_count            = 1
        max_count            = 4
        node_count           = 7
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["apps"].node_count != 7
    error_message = "a user pool with autoscaling must not send node_count."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["apps"].max_count == 4
    error_message = "max_count must reach the user pool."
  }
}

run "critical_addons_taint_with_user_pool_is_accepted" {
  command = plan

  variables {
    system_node_pool = {
      only_critical_addons_enabled = true
    }
    user_node_pools = {
      apps = { vm_size = "Standard_B2s" }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].only_critical_addons_enabled == true
    error_message = "only_critical_addons_enabled must reach the default node pool, applying the CriticalAddonsOnly taint."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.user) == 1
    error_message = "the user pool that makes the taint safe must exist."
  }
}

run "spot_pool_passes_through_eviction_settings" {
  command = plan

  variables {
    user_node_pools = {
      batch = {
        vm_size         = "Standard_D2s_v5"
        priority        = "Spot"
        eviction_policy = "Delete"
        spot_max_price  = 0.05
        node_taints     = ["workload=batch:NoSchedule"]
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["batch"].priority == "Spot"
    error_message = "priority must reach the node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["batch"].eviction_policy == "Delete"
    error_message = "eviction_policy must reach the node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["batch"].spot_max_price == 0.05
    error_message = "spot_max_price must reach the node pool."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.user["batch"].node_taints) == 1
    error_message = "node_taints must reach the node pool."
  }
}

run "regular_pool_never_sends_spot_max_price" {
  command = plan

  variables {
    user_node_pools = {
      apps = {
        priority       = "Regular"
        spot_max_price = 0.05
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["apps"].spot_max_price != 0.05
    error_message = "spot_max_price must be dropped for a Regular priority pool."
  }
}

run "subnet_ids_reach_the_pools" {
  command = plan

  variables {
    system_node_pool = {
      vnet_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.Network/virtualNetworks/vnet-demo-dev/subnets/system"
    }
    user_node_pools = {
      apps = {
        vnet_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.Network/virtualNetworks/vnet-demo-dev/subnets/user"
      }
    }
  }

  assert {
    condition     = endswith(azurerm_kubernetes_cluster.main.default_node_pool[0].vnet_subnet_id, "/subnets/system")
    error_message = "the system pool must land in the subnet it was given."
  }

  assert {
    condition     = endswith(azurerm_kubernetes_cluster_node_pool.user["apps"].vnet_subnet_id, "/subnets/user")
    error_message = "the user pool must land in the subnet it was given."
  }
}

run "tags_reach_cluster_and_all_pools" {
  command = plan

  variables {
    tags = { environment = "dev" }
    user_node_pools = {
      apps = { vm_size = "Standard_B2s" }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.tags["environment"] == "dev"
    error_message = "tags must reach the cluster."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].tags["environment"] == "dev"
    error_message = "tags must reach the system node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user["apps"].tags["environment"] == "dev"
    error_message = "tags must reach user node pools too."
  }
}
