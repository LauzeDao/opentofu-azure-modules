variable "subscription_id" {
  description = "Azure subscription to deploy into. Supply via tfvars or ARM_SUBSCRIPTION_ID; never commit a real value."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "tenant_id" {
  description = "Entra ID tenant. Supply via tfvars or ARM_TENANT_ID; never commit a real value."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "deployer_principal_id" {
  description = <<-EOT
    Object ID of the identity running OpenTofu (yourself, or the CI service principal).

    It receives `Key Vault Administrator` on the vault. Without a data-plane role, an
    RBAC-enabled vault is unreadable and unwritable even for a subscription Owner —
    `Contributor` is a control-plane role and grants no access to secrets.

    Find it with: az ad signed-in-user show --query id -o tsv
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.deployer_principal_id))
    error_message = "deployer_principal_id must be a GUID (an object ID, not a resource ID)."
  }
}

variable "project" {
  description = <<-EOT
    Short project identifier, used as the first naming segment.

    Capped at 8 characters because Key Vault names are limited to 24 and the derived name
    is `kv-<project>-<environment>`. Catching an over-long project name here beats
    discovering it as a truncated vault name later.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.project))
    error_message = "project must be 2-8 characters, lowercase alphanumeric, starting with a letter."
  }
}

variable "environment" {
  description = "Environment identifier, the second naming segment."
  type        = string

  validation {
    condition     = contains(["dev", "test", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, stage, prod."
  }
}

variable "location" {
  description = "Azure region, short form."
  type        = string
  default     = "germanywestcentral"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be the short region name: lowercase letters and digits only."
  }
}

variable "tags" {
  description = "Extra tags merged into the common tag set applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vnet_address_space" {
  description = "Single CIDR for the virtual network. Subnets are derived from it with cidrsubnet(), so only one value is needed."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.vnet_address_space)[1]) <= 20
    error_message = "vnet_address_space must be /20 or larger to accommodate the derived subnets."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version, e.g. `1.31`. Null uses the Azure default for the region — pin it for reproducibility."
  type        = string
  default     = null
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool. Smallest sensible SKU by default so a test run stays cheap."
  type        = string
  default     = "Standard_B2s"
}

variable "user_node_vm_size" {
  description = "VM size for the user node pool."
  type        = string
  default     = "Standard_B2s"
}

variable "enable_user_node_pool" {
  description = <<-EOT
    Create a separate user node pool for workloads.

    When true, the system pool also gets the `CriticalAddonsOnly` taint, giving proper
    system/user separation. When false, everything shares the system pool — cheaper, but not
    how you would run this for real.
  EOT
  type        = bool
  default     = true
}

variable "user_node_count" {
  description = "Node count for the user node pool."
  type        = number
  default     = 1

  validation {
    condition     = var.user_node_count >= 1
    error_message = "user_node_count must be at least 1."
  }
}

variable "sku_tier" {
  description = "AKS control plane tier. `Free` has no uptime SLA but costs nothing."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be one of: Free, Standard, Premium."
  }
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs whose members become cluster admins."
  type        = list(string)
  default     = []
}

variable "api_server_authorized_ip_ranges" {
  description = <<-EOT
    CIDRs allowed to reach the Kubernetes API server. Empty means reachable from anywhere
    (still authenticated).

    **Set this for anything beyond a throwaway cluster.** Left open by default so a CI
    runner can reach the cluster without a self-hosted agent.
  EOT
  type        = set(string)
  default     = []
}

variable "acr_sku" {
  description = "Container registry SKU. Basic keeps test runs cheap; Premium is needed for private link, geo-replication and retention policies."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be one of: Basic, Standard, Premium."
  }
}

variable "key_vault_purge_protection_enabled" {
  description = <<-EOT
    Enable Key Vault purge protection.

    Defaults to `false` so this example can be destroyed and redeployed repeatedly.
    **Irreversible once enabled** — see docs/adr/0007-purge-protection-default-aus.md.
  EOT
  type        = bool
  default     = false
}

variable "grant_kubelet_key_vault_access" {
  description = <<-EOT
    Grant the AKS kubelet identity `Key Vault Secrets User`.

    Only needed for Secrets Store CSI Driver scenarios, where every pod on a node shares
    the node's identity. For applications, the better path is Workload Identity via the
    cluster's `oidc_issuer_url` output — one federated credential per ServiceAccount.
  EOT
  type        = bool
  default     = true
}
