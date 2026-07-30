variable "name" {
  description = "AKS cluster name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-63 characters, start and end alphanumeric, and contain only letters, digits, '-' or '_'."
  }
}

variable "resource_group_name" {
  description = "Resource group for the cluster — typically `module.resource_group.name`. Note that AKS also creates its own `MC_…` group for node resources."
  type        = string
}

variable "location" {
  description = "Azure region, short form (e.g. `germanywestcentral`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be the short region name: lowercase letters and digits only."
  }
}

variable "dns_prefix" {
  description = "DNS prefix for the cluster's API server. Falls back to `name` when null."
  type        = string
  default     = null

  validation {
    condition     = var.dns_prefix == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,43}[a-zA-Z0-9]$", var.dns_prefix))
    error_message = "dns_prefix must be 2-45 characters, alphanumeric or '-', starting and ending alphanumeric."
  }
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes version, e.g. `1.31` or `1.31.3`. `null` means "use the Azure default
    for this region".

    Deliberately not defaulted to a concrete version: Azure removes old minor versions,
    so a hard default would make this module unusable within months. Pin it in the root
    module if you need reproducibility.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^\\d+\\.\\d+(\\.\\d+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must look like `1.31` or `1.31.3` — catches typos such as `1.31-lts`."
  }
}

variable "sku_tier" {
  description = "Control plane SKU. `Free` has no uptime SLA; `Standard` does. Defaults to the tier that costs nothing."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be one of: Free, Standard, Premium."
  }
}

variable "automatic_upgrade_channel" {
  description = "Automatic Kubernetes upgrade channel. `patch` keeps the cluster on security patches without minor-version jumps."
  type        = string
  default     = "patch"

  validation {
    condition     = contains(["none", "patch", "rapid", "stable", "node-image"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be one of: none, patch, rapid, stable, node-image."
  }
}

variable "node_os_upgrade_channel" {
  description = "Node OS image upgrade channel."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["None", "Unmanaged", "SecurityPatch", "NodeImage"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be one of: None, Unmanaged, SecurityPatch, NodeImage."
  }
}

variable "local_account_disabled" {
  description = <<-EOT
    Disable the local `clusterAdmin` account, leaving Entra ID as the only way in.

    Default `false` on purpose: with `true` and no `admin_group_object_ids`, you lock
    yourself out of the cluster completely. Set both together or neither.
  EOT
  type        = bool
  default     = false

  validation {
    condition     = !var.local_account_disabled || length(var.admin_group_object_ids) > 0
    error_message = "local_account_disabled = true requires at least one entry in admin_group_object_ids, otherwise nobody can reach the cluster."
  }
}

variable "cost_analysis_enabled" {
  description = "Enable AKS cost analysis. Requires `sku_tier` to be Standard or Premium."
  type        = bool
  default     = false

  validation {
    condition     = !var.cost_analysis_enabled || contains(["Standard", "Premium"], var.sku_tier)
    error_message = "cost_analysis_enabled requires sku_tier to be Standard or Premium."
  }
}

variable "azure_policy_enabled" {
  description = <<-EOT
    Enable the Azure Policy add-on, which enforces Gatekeeper/OPA constraints in the cluster.

    Defaults to `false` because the add-on schedules additional system pods, which is
    noticeable on the `Standard_B2s` default node size. Worth enabling on a real cluster.
  EOT
  type        = bool
  default     = false
}

variable "disk_encryption_set_id" {
  description = <<-EOT
    Resource ID of a disk encryption set for node OS and data disks, giving
    customer-managed-key encryption at rest.

    Null uses platform-managed keys. Setting this requires a disk encryption set and a key
    vault key to exist first, which is outside this module's scope.
  EOT
  type        = string
  default     = null
}

variable "key_vault_secrets_provider" {
  description = <<-EOT
    Enable the Secrets Store CSI Driver add-on, which mounts Key Vault secrets into pods.

    `null` leaves the add-on off. When enabled, prefer `secret_rotation_enabled = true` —
    without it, a rotated secret in the vault is never picked up by running pods.

    Note this is node-level access via the kubelet identity: every pod on the node shares
    it. For per-application identity use Workload Identity via the `oidc_issuer_url`
    output instead.

    Example:
    ```
    key_vault_secrets_provider = {
      secret_rotation_enabled  = true
      secret_rotation_interval = "2m"
    }
    ```
  EOT

  type = object({
    secret_rotation_enabled  = optional(bool, true)
    secret_rotation_interval = optional(string, "2m")
  })

  default = null

  validation {
    condition = (
      var.key_vault_secrets_provider == null ||
      can(regex("^[0-9]+(s|m|h)$", try(var.key_vault_secrets_provider.secret_rotation_interval, "")))
    )
    error_message = "secret_rotation_interval must be a duration such as `30s`, `2m` or `1h`."
  }
}

variable "image_cleaner_enabled" {
  description = "Enable the Image Cleaner add-on, which removes unused and vulnerable images from nodes."
  type        = bool
  default     = false
}

variable "image_cleaner_interval_hours" {
  description = "How often Image Cleaner runs, in hours (24-2160). Only meaningful when `image_cleaner_enabled` is true."
  type        = number
  default     = 48

  validation {
    condition     = var.image_cleaner_interval_hours >= 24 && var.image_cleaner_interval_hours <= 2160
    error_message = "image_cleaner_interval_hours must be between 24 and 2160."
  }
}

variable "tags" {
  description = "Tags applied to the cluster and to all node pools."
  type        = map(string)
  default     = {}
}

variable "identity_type" {
  description = <<-EOT
    Control plane identity type. `SystemAssigned` lets Azure manage the lifecycle, which
    keeps `destroy` clean — see docs/adr/0006.

    Note: regardless of this setting, the module never configures a `service_principal`
    block. A service principal means a long-lived client secret in state, which this library
    rules out.
  EOT
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.identity_type)
    error_message = "identity_type must be either SystemAssigned or UserAssigned."
  }
}

variable "identity_ids" {
  description = "User-assigned identity resource IDs. Required when `identity_type` is `UserAssigned`, must be empty otherwise."
  type        = list(string)
  default     = []

  validation {
    condition     = var.identity_type != "UserAssigned" || length(var.identity_ids) > 0
    error_message = "identity_ids must contain at least one identity when identity_type is UserAssigned."
  }

  validation {
    condition     = var.identity_type != "SystemAssigned" || length(var.identity_ids) == 0
    error_message = "identity_ids must be empty when identity_type is SystemAssigned."
  }
}

variable "azure_rbac_enabled" {
  description = "Use Azure RBAC for Kubernetes authorization, so cluster access is granted via Azure role assignments rather than in-cluster RoleBindings."
  type        = bool
  default     = true
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs whose members become cluster admins."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.admin_group_object_ids :
      can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))
    ])
    error_message = "every entry in admin_group_object_ids must be a GUID."
  }
}

variable "tenant_id" {
  description = "Entra ID tenant for cluster RBAC. Null uses the tenant of the authenticated principal."
  type        = string
  default     = null

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "network_plugin" {
  description = "CNI plugin. `azure` is Azure CNI; `none` means you bring your own CNI."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "kubenet", "none"], var.network_plugin)
    error_message = "network_plugin must be one of: azure, kubenet, none."
  }
}

variable "network_plugin_mode" {
  description = <<-EOT
    `overlay` or null. Overlay is the default because Azure CNI without it assigns a VNet
    IP per pod — a /22 subnet is exhausted at roughly 1000 pods. Overlay decouples pod IPs
    from the VNet.
  EOT
  type        = string
  default     = "overlay"

  validation {
    condition     = var.network_plugin_mode == null || var.network_plugin_mode == "overlay"
    error_message = "network_plugin_mode must be either `overlay` or null."
  }

  validation {
    condition     = var.network_plugin_mode != "overlay" || var.network_plugin == "azure"
    error_message = "network_plugin_mode = \"overlay\" requires network_plugin = \"azure\"."
  }
}

variable "network_policy" {
  description = "Network policy engine. Null disables network policy entirely."
  type        = string
  default     = "calico"

  validation {
    condition     = var.network_policy == null || contains(["calico", "azure", "cilium"], var.network_policy)
    error_message = "network_policy must be one of: calico, azure, cilium — or null."
  }
}

variable "network_data_plane" {
  description = "Data plane implementation. Must be `cilium` when `network_policy` is `cilium`."
  type        = string
  default     = null

  validation {
    condition     = var.network_data_plane == null || contains(["azure", "cilium"], var.network_data_plane)
    error_message = "network_data_plane must be either `azure` or `cilium`."
  }

  validation {
    condition     = var.network_policy != "cilium" || var.network_data_plane == "cilium"
    error_message = "network_policy = \"cilium\" requires network_data_plane = \"cilium\"."
  }
}

variable "service_cidr" {
  description = "CIDR for Kubernetes service IPs. Must not overlap the VNet address space."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "service_cidr must be a valid CIDR block."
  }
}

variable "dns_service_ip" {
  description = "IP of the in-cluster DNS service. Must lie inside `service_cidr`."
  type        = string
  default     = "10.0.0.10"

  validation {
    condition = (
      can(cidrhost(var.service_cidr, 0)) &&
      can(cidrhost("${var.dns_service_ip}/${split("/", var.service_cidr)[1]}", 0)) &&
      cidrhost("${var.dns_service_ip}/${split("/", var.service_cidr)[1]}", 0) == cidrhost(var.service_cidr, 0)
    )
    error_message = "dns_service_ip must be a valid IPv4 address lying inside service_cidr."
  }
}

variable "pod_cidr" {
  description = "CIDR for pod IPs. Used with `kubenet` or Azure CNI overlay; ignored otherwise."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = var.pod_cidr == null || can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR block."
  }
}

variable "load_balancer_sku" {
  description = "Load balancer SKU for the cluster."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["basic", "standard"], var.load_balancer_sku)
    error_message = "load_balancer_sku must be either `basic` or `standard`."
  }
}

variable "outbound_type" {
  description = "How cluster egress leaves the VNet."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be one of: loadBalancer, userDefinedRouting, managedNATGateway, userAssignedNATGateway."
  }
}

variable "private_cluster_enabled" {
  description = <<-EOT
    Make the API server reachable only from the VNet.

    Default `false` so the CI apply/destroy test can reach the API server from a
    GitHub-hosted runner without a self-hosted agent. **Set this to true for production.**
  EOT
  type        = bool
  default     = false
}

variable "api_server_authorized_ip_ranges" {
  description = <<-EOT
    CIDRs allowed to reach the API server. Empty means open to the internet (still
    authenticated, but reachable).

    **Set this for production.** It is left open by default for the same CI reason as
    `private_cluster_enabled`.
  EOT
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.api_server_authorized_ip_ranges : can(cidrhost(cidr, 0))])
    error_message = "every entry in api_server_authorized_ip_ranges must be a valid CIDR block."
  }

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) == 0 || !var.private_cluster_enabled
    error_message = "api_server_authorized_ip_ranges has no effect on a private cluster — set one or the other, not both."
  }
}

variable "system_node_pool" {
  description = <<-EOT
    The cluster's default node pool, which hosts system components.

    `only_critical_addons_enabled = true` applies the `CriticalAddonsOnly` taint, reserving
    this pool for system pods. That requires at least one entry in `user_node_pools`, or
    workloads have nowhere to run — enforced by a validation rule.
  EOT

  type = object({
    name                         = optional(string, "system")
    vm_size                      = optional(string, "Standard_B2s")
    node_count                   = optional(number, 1)
    auto_scaling_enabled         = optional(bool, false)
    min_count                    = optional(number)
    max_count                    = optional(number)
    only_critical_addons_enabled = optional(bool, false)
    vnet_subnet_id               = optional(string)
    pod_subnet_id                = optional(string)
    zones                        = optional(list(string), [])
    os_disk_size_gb              = optional(number)
    os_disk_type                 = optional(string, "Managed")
    os_sku                       = optional(string)
    max_pods                     = optional(number)
    node_labels                  = optional(map(string), {})
    host_encryption_enabled      = optional(bool, false)
    node_public_ip_enabled       = optional(bool, false)
    orchestrator_version         = optional(string)
  })

  default = {}

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.system_node_pool.name))
    error_message = "system_node_pool.name must be 1-12 lowercase alphanumeric characters starting with a letter (Azure node pool rule)."
  }

  validation {
    condition = (
      !var.system_node_pool.auto_scaling_enabled ||
      (var.system_node_pool.min_count != null && var.system_node_pool.max_count != null)
    )
    error_message = "system_node_pool requires both min_count and max_count when auto_scaling_enabled is true."
  }

  validation {
    condition = (
      var.system_node_pool.min_count == null ||
      var.system_node_pool.max_count == null ||
      var.system_node_pool.min_count <= var.system_node_pool.max_count
    )
    error_message = "system_node_pool.min_count must not exceed max_count."
  }

  validation {
    condition = (
      var.system_node_pool.auto_scaling_enabled ||
      (var.system_node_pool.node_count != null && var.system_node_pool.node_count >= 1)
    )
    error_message = "system_node_pool.node_count must be at least 1 when auto_scaling_enabled is false."
  }

  validation {
    condition     = contains(["Managed", "Ephemeral"], var.system_node_pool.os_disk_type)
    error_message = "system_node_pool.os_disk_type must be either Managed or Ephemeral."
  }

  validation {
    condition     = !var.system_node_pool.only_critical_addons_enabled || length(var.user_node_pools) > 0
    error_message = "system_node_pool.only_critical_addons_enabled = true requires at least one entry in user_node_pools, otherwise workloads have nowhere to run."
  }
}

variable "user_node_pools" {
  description = <<-EOT
    Additional node pools for workloads, keyed by pool name.

    A map — not a list — so `for_each` stays idempotent when a pool is added or removed;
    with a list, inserting one shifts every later index and OpenTofu replaces all of them.

    Example:
    ```
    user_node_pools = {
      apps = {
        vm_size              = "Standard_D2s_v5"
        auto_scaling_enabled = true
        min_count            = 1
        max_count            = 5
      }
      batch = {
        vm_size         = "Standard_D2s_v5"
        priority        = "Spot"
        eviction_policy = "Delete"
        node_taints     = ["workload=batch:NoSchedule"]
      }
    }
    ```
  EOT

  type = map(object({
    vm_size                 = optional(string, "Standard_B2s")
    node_count              = optional(number, 1)
    auto_scaling_enabled    = optional(bool, false)
    min_count               = optional(number)
    max_count               = optional(number)
    mode                    = optional(string, "User")
    node_taints             = optional(list(string), [])
    node_labels             = optional(map(string), {})
    priority                = optional(string, "Regular")
    eviction_policy         = optional(string)
    spot_max_price          = optional(number)
    vnet_subnet_id          = optional(string)
    pod_subnet_id           = optional(string)
    zones                   = optional(list(string), [])
    os_disk_size_gb         = optional(number)
    os_disk_type            = optional(string, "Managed")
    os_sku                  = optional(string)
    os_type                 = optional(string, "Linux")
    max_pods                = optional(number)
    host_encryption_enabled = optional(bool, false)
    node_public_ip_enabled  = optional(bool, false)
    orchestrator_version    = optional(string)
  }))

  default = {}

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools : can(regex("^[a-z][a-z0-9]{0,11}$", name))
    ])
    error_message = "every user_node_pools key must be 1-12 lowercase alphanumeric characters starting with a letter (Azure node pool rule)."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools :
      !pool.auto_scaling_enabled || (pool.min_count != null && pool.max_count != null)
    ])
    error_message = "a user node pool with auto_scaling_enabled requires both min_count and max_count."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools :
      pool.min_count == null || pool.max_count == null || pool.min_count <= pool.max_count
    ])
    error_message = "a user node pool's min_count must not exceed its max_count."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools : contains(["User", "System"], pool.mode)
    ])
    error_message = "user_node_pools mode must be either User or System."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools : contains(["Regular", "Spot"], pool.priority)
    ])
    error_message = "user_node_pools priority must be either Regular or Spot."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools :
      pool.priority != "Spot" || pool.eviction_policy != null
    ])
    error_message = "a Spot node pool requires eviction_policy (Delete or Deallocate)."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools :
      pool.eviction_policy == null || contains(["Delete", "Deallocate"], pool.eviction_policy)
    ])
    error_message = "eviction_policy must be either Delete or Deallocate."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools :
      pool.priority == "Spot" || pool.eviction_policy == null
    ])
    error_message = "eviction_policy is only valid on a Spot node pool."
  }

  validation {
    condition = alltrue([
      for name, pool in var.user_node_pools : contains(["Linux", "Windows"], pool.os_type)
    ])
    error_message = "user_node_pools os_type must be either Linux or Windows."
  }
}
