variable "name" {
  description = <<-EOT
    Registry name. **Alphanumeric only** — no hyphens, 5-50 characters.

    This is the most common ACR trip-hazard: the repo-wide `<project>-<env>-<resource>`
    convention does not work here. The root module normalises it (see
    examples/aks-cluster/main.tf) rather than this module hiding the problem.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "name must be 5-50 alphanumeric characters with no hyphens or underscores — Azure Container Registry does not allow them."
  }
}

variable "resource_group_name" {
  description = "Resource group for the registry — typically `module.resource_group.name`."
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

variable "sku" {
  description = "Registry SKU. `Basic` is the cost-conscious default; private link, geo-replication, content trust and retention policies all require `Premium`."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of: Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  description = <<-EOT
    Enable the built-in admin account. Defaults to `false` and should stay there.

    The admin account is a single shared username/password with full push and pull
    rights — not attributable, not individually revocable, not rotatable without
    breaking every consumer. Use role assignments instead.

    Note that even with this set to `true`, the module does **not** output the
    credentials. See docs/adr/0005-acr-ohne-admin-konto.md.
  EOT
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow access from public networks. Disabling this meaningfully requires Premium (private endpoints)."
  type        = bool
  default     = true
}

variable "anonymous_pull_enabled" {
  description = "Allow unauthenticated pulls. Requires Standard or Premium."
  type        = bool
  default     = false

  validation {
    condition     = !var.anonymous_pull_enabled || contains(["Standard", "Premium"], var.sku)
    error_message = "anonymous_pull_enabled requires sku to be Standard or Premium."
  }
}

variable "data_endpoint_enabled" {
  description = "Enable dedicated data endpoints. Premium only."
  type        = bool
  default     = false

  validation {
    condition     = !var.data_endpoint_enabled || var.sku == "Premium"
    error_message = "data_endpoint_enabled requires sku = \"Premium\"."
  }
}

variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy. Premium only."
  type        = bool
  default     = false

  validation {
    condition     = !var.zone_redundancy_enabled || var.sku == "Premium"
    error_message = "zone_redundancy_enabled requires sku = \"Premium\"."
  }
}

variable "retention_policy_in_days" {
  description = "Days to retain untagged manifests. Premium only; null disables the policy."
  type        = number
  default     = null

  validation {
    condition     = var.retention_policy_in_days == null || var.sku == "Premium"
    error_message = "retention_policy_in_days requires sku = \"Premium\"."
  }

  validation {
    condition     = var.retention_policy_in_days == null || (var.retention_policy_in_days >= 0 && var.retention_policy_in_days <= 365)
    error_message = "retention_policy_in_days must be between 0 and 365."
  }
}

variable "trust_policy_enabled" {
  description = "Enable content trust (image signing). Premium only."
  type        = bool
  default     = false

  validation {
    condition     = !var.trust_policy_enabled || var.sku == "Premium"
    error_message = "trust_policy_enabled requires sku = \"Premium\"."
  }
}

variable "quarantine_policy_enabled" {
  description = "Quarantine newly pushed images until they pass scanning. Premium only."
  type        = bool
  default     = false

  validation {
    condition     = !var.quarantine_policy_enabled || var.sku == "Premium"
    error_message = "quarantine_policy_enabled requires sku = \"Premium\"."
  }
}

variable "georeplications" {
  description = "Additional regions to replicate to. Premium only."
  type = list(object({
    location                  = string
    zone_redundancy_enabled   = optional(bool, false)
    regional_endpoint_enabled = optional(bool, false)
    tags                      = optional(map(string), {})
  }))
  default = []

  validation {
    condition     = length(var.georeplications) == 0 || var.sku == "Premium"
    error_message = "georeplications require sku = \"Premium\"."
  }

  validation {
    condition = alltrue([
      for replica in var.georeplications : can(regex("^[a-z0-9]+$", replica.location))
    ])
    error_message = "every georeplication location must be the short region name: lowercase letters and digits only."
  }

  validation {
    condition = alltrue([
      for replica in var.georeplications : replica.location != var.location
    ])
    error_message = "a georeplication must not target the registry's own location."
  }
}

variable "role_assignments" {
  description = <<-EOT
    Role assignments scoped to this registry, keyed by a logical name.

    Deliberately generic rather than an AKS-specific input: this module does not need to
    know that AKS exists. Granting `AcrPull` to a cluster's kubelet identity, to a
    Container App or to a CI runner is the same operation.

    Example:
    ```
    role_assignments = {
      aks_kubelet = {
        principal_id   = module.aks.kubelet_identity_object_id
        role           = "AcrPull"
        principal_type = "ServicePrincipal"
      }
      ci_push = {
        principal_id = var.ci_principal_id
        role         = "AcrPush"
      }
    }
    ```
  EOT

  type = map(object({
    principal_id   = string
    role           = string
    principal_type = optional(string)
    description    = optional(string)
  }))

  default = {}

  validation {
    condition = alltrue([
      for key, assignment in var.role_assignments :
      can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", assignment.principal_id))
    ])
    error_message = "every role_assignments principal_id must be a GUID (an object/principal ID, not a resource ID)."
  }

  validation {
    condition = alltrue([
      for key, assignment in var.role_assignments : length(trimspace(assignment.role)) > 0
    ])
    error_message = "every role_assignments entry needs a non-empty role."
  }

  validation {
    condition = alltrue([
      for key, assignment in var.role_assignments :
      assignment.principal_type == null ||
      contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], assignment.principal_type)
    ])
    error_message = "principal_type must be one of: User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}

variable "tags" {
  description = "Tags applied to the registry."
  type        = map(string)
  default     = {}
}
