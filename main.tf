locals {
  prefix = "${var.project}-${var.environment}"

  names = {
    resource_group = "rg-${local.prefix}"
    vnet           = "vnet-${local.prefix}"
    aks            = "aks-${local.prefix}"
    key_vault      = "kv-${local.prefix}"

    acr = substr(replace("acr${local.prefix}", "-", ""), 0, 50)
  }

  common_tags = merge(var.tags, {
    project     = var.project
    environment = var.environment
    managed_by  = "opentofu"
    repository  = "opentofu-azure-modules"
  })

  subnet_newbits = 22 - tonumber(split("/", var.vnet_address_space)[1])

  user_node_pools = var.enable_user_node_pool ? {
    apps = {
      vm_size        = var.user_node_vm_size
      node_count     = var.user_node_count
      vnet_subnet_id = module.networking.subnet_ids["user"]
    }
  } : {}
}

module "resource_group" {
  source = "./modules/resource-group"

  name     = local.names.resource_group
  location = var.location
  tags     = local.common_tags
}

module "networking" {
  source = "./modules/networking"

  name                = local.names.vnet
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  address_space       = [var.vnet_address_space]

  subnets = {
    system = {
      address_prefixes = [cidrsubnet(var.vnet_address_space, local.subnet_newbits, 0)]

      service_endpoints = ["Microsoft.ContainerRegistry", "Microsoft.KeyVault"]
    }

    user = {
      address_prefixes  = [cidrsubnet(var.vnet_address_space, local.subnet_newbits, 1)]
      service_endpoints = ["Microsoft.ContainerRegistry", "Microsoft.KeyVault"]
    }
  }

  tags = local.common_tags
}

module "aks" {
  source = "./modules/aks"

  name                = local.names.aks
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  kubernetes_version = var.kubernetes_version
  sku_tier           = var.sku_tier

  admin_group_object_ids          = var.admin_group_object_ids
  tenant_id                       = var.tenant_id
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges

  system_node_pool = {
    name           = "system"
    vm_size        = var.system_node_vm_size
    node_count     = 1
    vnet_subnet_id = module.networking.subnet_ids["system"]

    only_critical_addons_enabled = var.enable_user_node_pool
  }

  user_node_pools = local.user_node_pools

  tags = local.common_tags
}

module "acr" {
  source = "./modules/acr"

  name                = local.names.acr
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = var.acr_sku

  role_assignments = {
    aks_kubelet = {
      principal_id   = module.aks.kubelet_identity_object_id
      role           = "AcrPull"
      principal_type = "ServicePrincipal"
      description    = "Allows AKS nodes to pull images from this registry."
    }
  }

  tags = local.common_tags
}

module "key_vault" {
  source = "./modules/key-vault"

  name                = local.names.key_vault
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  tenant_id           = var.tenant_id

  purge_protection_enabled = var.key_vault_purge_protection_enabled

  role_assignments = merge(
    {
      deployer = {
        principal_id = var.deployer_principal_id
        role         = "Key Vault Administrator"
        description  = "Lets the identity running OpenTofu manage secrets in this vault."
      }
    },
    var.grant_kubelet_key_vault_access ? {
      aks_kubelet = {
        principal_id   = module.aks.kubelet_identity_object_id
        role           = "Key Vault Secrets User"
        principal_type = "ServicePrincipal"
        description    = "Allows the Secrets Store CSI Driver on AKS nodes to read secrets."
      }
    } : {}
  )

  tags = local.common_tags
}
