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

run "rejects_malformed_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "1.31-lts"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_invalid_sku_tier" {
  command = plan

  variables {
    sku_tier = "Gratis"
  }

  expect_failures = [var.sku_tier]
}

run "rejects_invalid_upgrade_channel" {
  command = plan

  variables {
    automatic_upgrade_channel = "yolo"
  }

  expect_failures = [var.automatic_upgrade_channel]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "aks_demo/dev"
  }

  expect_failures = [var.name]
}

run "rejects_user_assigned_without_identity_ids" {
  command = plan

  variables {
    identity_type = "UserAssigned"
    identity_ids  = []
  }

  expect_failures = [var.identity_ids]
}

run "rejects_identity_ids_with_system_assigned" {
  command = plan

  variables {
    identity_type = "SystemAssigned"
    identity_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/x",
    ]
  }

  expect_failures = [var.identity_ids]
}

run "rejects_non_guid_admin_group" {
  command = plan

  variables {
    admin_group_object_ids = ["not-a-guid"]
  }

  expect_failures = [var.admin_group_object_ids]
}

run "rejects_non_guid_tenant_id" {
  command = plan

  variables {
    tenant_id = "nope"
  }

  expect_failures = [var.tenant_id]
}

run "rejects_disabled_local_account_without_admin_groups" {
  command = plan

  variables {
    local_account_disabled = true
    admin_group_object_ids = []
  }

  expect_failures = [var.local_account_disabled]
}

run "rejects_dns_service_ip_outside_service_cidr" {
  command = plan

  variables {
    service_cidr   = "10.0.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  expect_failures = [var.dns_service_ip]
}

run "rejects_malformed_service_cidr" {
  command = plan

  variables {
    service_cidr = "10.0.0.0/99"
  }

  expect_failures = [var.service_cidr]
}

run "rejects_cilium_policy_without_cilium_data_plane" {
  command = plan

  variables {
    network_policy     = "cilium"
    network_data_plane = null
  }

  expect_failures = [var.network_data_plane]
}

run "rejects_overlay_with_kubenet" {
  command = plan

  variables {
    network_plugin      = "kubenet"
    network_plugin_mode = "overlay"
  }

  expect_failures = [var.network_plugin_mode]
}

run "rejects_invalid_network_policy" {
  command = plan

  variables {
    network_policy = "iptables"
  }

  expect_failures = [var.network_policy]
}

run "rejects_invalid_outbound_type" {
  command = plan

  variables {
    outbound_type = "carrierPigeon"
  }

  expect_failures = [var.outbound_type]
}

run "rejects_malformed_authorized_ip_range" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["203.0.113.0"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_authorized_ip_ranges_on_private_cluster" {
  command = plan

  variables {
    private_cluster_enabled         = true
    api_server_authorized_ip_ranges = ["203.0.113.0/24"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_cost_analysis_on_free_tier" {
  command = plan

  variables {
    sku_tier              = "Free"
    cost_analysis_enabled = true
  }

  expect_failures = [var.cost_analysis_enabled]
}

run "rejects_autoscaling_without_min_count" {
  command = plan

  variables {
    system_node_pool = {
      auto_scaling_enabled = true
      max_count            = 5
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_min_count_above_max_count" {
  command = plan

  variables {
    system_node_pool = {
      auto_scaling_enabled = true
      min_count            = 9
      max_count            = 3
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_critical_addons_taint_without_user_pool" {
  command = plan

  variables {
    system_node_pool = {
      only_critical_addons_enabled = true
    }
    user_node_pools = {}
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_node_pool_name_over_12_characters" {
  command = plan

  variables {
    system_node_pool = {
      name = "systempoolone"
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_node_pool_name_with_uppercase" {
  command = plan

  variables {
    system_node_pool = {
      name = "System"
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_zero_node_count_without_autoscaling" {
  command = plan

  variables {
    system_node_pool = {
      node_count = 0
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_invalid_os_disk_type" {
  command = plan

  variables {
    system_node_pool = {
      os_disk_type = "Spinning"
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_user_pool_key_over_12_characters" {
  command = plan

  variables {
    user_node_pools = {
      averylongpoolname = {}
    }
  }

  expect_failures = [var.user_node_pools]
}

run "rejects_spot_pool_without_eviction_policy" {
  command = plan

  variables {
    user_node_pools = {
      batch = {
        priority = "Spot"
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

run "rejects_eviction_policy_on_regular_pool" {
  command = plan

  variables {
    user_node_pools = {
      apps = {
        priority        = "Regular"
        eviction_policy = "Delete"
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

run "rejects_invalid_eviction_policy" {
  command = plan

  variables {
    user_node_pools = {
      batch = {
        priority        = "Spot"
        eviction_policy = "Vaporise"
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

run "rejects_user_pool_autoscaling_without_bounds" {
  command = plan

  variables {
    user_node_pools = {
      apps = {
        auto_scaling_enabled = true
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

run "rejects_invalid_user_pool_mode" {
  command = plan

  variables {
    user_node_pools = {
      apps = {
        mode = "Hybrid"
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

run "rejects_invalid_os_type" {
  command = plan

  variables {
    user_node_pools = {
      apps = {
        os_type = "Plan9"
      }
    }
  }

  expect_failures = [var.user_node_pools]
}
