mock_provider "azurerm" {
  mock_resource "azurerm_container_registry" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-dev/providers/Microsoft.ContainerRegistry/registries/demodevacr"
      login_server = "demodevacr.azurecr.io"
    }
  }
}

variables {
  name                = "demodevacr"
  resource_group_name = "rg-demo-dev"
  location            = "germanywestcentral"
}

run "creates_no_assignments_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.registry) == 0
    error_message = "role_assignments must default to empty — no implicit grants."
  }

  assert {
    condition     = length(output.role_assignment_ids) == 0
    error_message = "role_assignment_ids must be an empty map, not null."
  }
}

run "creates_one_assignment_per_map_entry" {
  command = plan

  variables {
    role_assignments = {
      aks_kubelet = {
        principal_id   = "22222222-2222-2222-2222-222222222222"
        role           = "AcrPull"
        principal_type = "ServicePrincipal"
      }
      ci_push = {
        principal_id = "66666666-6666-6666-6666-666666666666"
        role         = "AcrPush"
      }
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.registry) == 2
    error_message = "two map entries must produce exactly two role assignments."
  }

  assert {
    condition     = join(",", sort(keys(azurerm_role_assignment.registry))) == "aks_kubelet,ci_push"
    error_message = "assignment resource keys must mirror the input map keys, so state addresses stay stable."
  }
}

run "assignment_uses_role_name_and_registry_scope" {
  command = plan

  variables {
    role_assignments = {
      aks_kubelet = {
        principal_id   = "22222222-2222-2222-2222-222222222222"
        role           = "AcrPull"
        principal_type = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.registry["aks_kubelet"].role_definition_name == "AcrPull"
    error_message = "the role must be passed as a readable name, not a GUID."
  }

  assert {
    condition     = azurerm_role_assignment.registry["aks_kubelet"].principal_id == "22222222-2222-2222-2222-222222222222"
    error_message = "the principal id must reach the assignment."
  }

  assert {
    condition     = azurerm_role_assignment.registry["aks_kubelet"].principal_type == "ServicePrincipal"
    error_message = "principal_type must reach the assignment — it avoids an Entra lookup race on fresh identities."
  }

  assert {
    condition     = endswith(azurerm_role_assignment.registry["aks_kubelet"].scope, "/registries/demodevacr")
    error_message = "the assignment must be scoped to this registry, not to the resource group."
  }
}
