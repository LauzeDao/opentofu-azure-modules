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

run "defaults_to_system_assigned_identity" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.main.identity[0].type == "SystemAssigned"
    error_message = "identity must default to SystemAssigned, which keeps destroy clean (ADR 0006)."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.main.identity[0].identity_ids == null ||
      length(azurerm_kubernetes_cluster.main.identity[0].identity_ids) == 0
    )
    error_message = "no identity_ids may be sent for a SystemAssigned cluster."
  }
}

run "supports_user_assigned_identity" {
  command = plan

  variables {
    identity_type = "UserAssigned"
    identity_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aks-cp",
    ]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.identity[0].type == "UserAssigned"
    error_message = "identity_type must reach the cluster."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.identity[0].identity_ids) == 1
    error_message = "identity_ids must reach the cluster when UserAssigned."
  }
}

run "exposes_oidc_issuer_url_for_federated_credentials" {
  command = plan

  assert {
    condition     = startswith(output.oidc_issuer_url, "https://")
    error_message = "oidc_issuer_url must be exposed — it is what federated identity credentials point at."
  }
}

run "kubelet_identity_outputs_are_declared_and_plan_safe" {
  command = plan

  assert {
    condition     = output.kubelet_identity_object_id == null
    error_message = "under mock_provider the kubelet identity is unavailable, so the output must resolve to null rather than abort the plan."
  }

  assert {
    condition     = output.kubelet_identity_client_id == null
    error_message = "kubelet_identity_client_id must resolve to null under mock_provider, not error."
  }

  assert {
    condition     = output.kubelet_identity_id == null
    error_message = "kubelet_identity_id must resolve to null under mock_provider, not error."
  }
}

run "entra_rbac_receives_admin_groups_and_tenant" {
  command = plan

  variables {
    admin_group_object_ids = ["44444444-4444-4444-4444-444444444444"]
    tenant_id              = "55555555-5555-5555-5555-555555555555"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].admin_group_object_ids) == 1
    error_message = "admin_group_object_ids must reach the Entra RBAC block."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].tenant_id == "55555555-5555-5555-5555-555555555555"
    error_message = "tenant_id must reach the Entra RBAC block."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "azure_rbac_enabled must be true inside the block."
  }
}

run "local_account_can_be_disabled_together_with_admin_groups" {
  command = plan

  variables {
    local_account_disabled = true
    admin_group_object_ids = ["44444444-4444-4444-4444-444444444444"]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.local_account_disabled == true
    error_message = "local_account_disabled must reach the cluster when paired with admin groups."
  }
}
