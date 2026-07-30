variable "name" {
  description = "Key Vault name. 3-24 characters, must start with a letter, alphanumeric and hyphens only, no consecutive hyphens, must not end with a hyphen. Globally unique across Azure."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 3-24 characters, start with a letter, end alphanumeric, and contain only letters, digits and hyphens."
  }

  validation {
    condition     = !can(regex("--", var.name))
    error_message = "name must not contain consecutive hyphens."
  }
}

variable "resource_group_name" {
  description = "Resource group for the vault — typically `module.resource_group.name`."
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

variable "tenant_id" {
  description = <<-EOT
    Entra ID tenant that owns the vault.

    An input rather than a `data "azurerm_client_config"` lookup on purpose: a data source
    would make the module unplannable under `mock_provider` in tests, and the module genuinely
    needs this information — so it belongs in the contract.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "sku_name" {
  description = "Vault SKU. `premium` adds HSM-backed keys. Lowercase — Azure rejects `Standard`."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be either `standard` or `premium` — lowercase."
  }
}

variable "soft_delete_retention_days" {
  description = "Days a deleted vault stays recoverable, 7-90. Defaults to the minimum so a destroyed vault's name is released again as soon as Azure allows."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  description = <<-EOT
    Prevent permanent deletion before the retention period expires.

    **Defaults to `false`, which is weaker than every security baseline recommends.** The
    reason is that purge protection is *irreversible* once enabled and holds the vault name
    for 7-90 days. That makes a repeatable destroy/apply cycle impossible — the second run
    fails on a name collision.

    **Set this to `true` for production.** See docs/adr/0007-purge-protection-default-aus.md.
  EOT
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow access from public networks. Left on by default so CI can reach its own test resources; combine with `network_acls` to restrict."
  type        = bool
  default     = true
}

variable "enabled_for_disk_encryption" {
  description = "Allow Azure Disk Encryption to retrieve secrets and unwrap keys from this vault."
  type        = bool
  default     = false
}

variable "enabled_for_deployment" {
  description = "Allow Azure Virtual Machines to retrieve certificates stored as secrets."
  type        = bool
  default     = false
}

variable "enabled_for_template_deployment" {
  description = "Allow Azure Resource Manager templates to retrieve secrets."
  type        = bool
  default     = false
}

variable "network_acls" {
  description = <<-EOT
    Network restrictions for the vault. `null` means no ACLs at all.

    Note that `default_action = "Deny"` locks out anything not listed, including the
    identity running OpenTofu — set `ip_rules` accordingly or you will not be able to
    manage the vault's contents.
  EOT

  type = object({
    default_action             = string
    bypass                     = optional(string, "AzureServices")
    ip_rules                   = optional(set(string), [])
    virtual_network_subnet_ids = optional(set(string), [])
  })

  default = null

  validation {
    condition     = var.network_acls == null || contains(["Allow", "Deny"], try(var.network_acls.default_action, ""))
    error_message = "network_acls.default_action must be either Allow or Deny."
  }

  validation {
    condition     = var.network_acls == null || contains(["AzureServices", "None"], try(var.network_acls.bypass, ""))
    error_message = "network_acls.bypass must be either AzureServices or None."
  }
}

variable "role_assignments" {
  description = <<-EOT
    Role assignments scoped to this vault, keyed by a logical name. Roles are given by
    name, not ID, so the plan diff stays readable.

    The vault uses Azure RBAC, so `Contributor` on the resource is **not** enough to read
    or write secrets — a data-plane role such as `Key Vault Secrets User` or
    `Key Vault Administrator` is required.

    Example:
    ```
    role_assignments = {
      deployer = {
        principal_id = var.deployer_principal_id
        role         = "Key Vault Administrator"
      }
      aks_kubelet = {
        principal_id   = module.aks.kubelet_identity_object_id
        role           = "Key Vault Secrets User"
        principal_type = "ServicePrincipal"
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
  description = "Tags applied to the vault."
  type        = map(string)
  default     = {}
}
