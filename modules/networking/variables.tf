variable "name" {
  description = "Virtual network name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}[a-zA-Z0-9_]$", var.name))
    error_message = "name must be 2-64 characters, start alphanumeric, and contain only letters, digits, '.', '_' or '-'."
  }
}

variable "resource_group_name" {
  description = "Resource group to create the network in — typically `module.resource_group.name`."
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

variable "address_space" {
  description = "Address space of the virtual network, as a list of CIDR blocks."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0
    error_message = "address_space must contain at least one CIDR block."
  }

  validation {
    condition     = alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "every entry in address_space must be a valid CIDR block (e.g. `10.42.0.0/16`)."
  }
}

variable "dns_servers" {
  description = "Custom DNS servers for the virtual network. Empty list means Azure-provided DNS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.dns_servers : can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", ip))])
    error_message = "every entry in dns_servers must be an IPv4 address."
  }
}

variable "subnets" {
  description = <<-EOT
    Subnets to create, keyed by a stable logical name (e.g. `system`, `user`).

    A map — not a list — on purpose: with a list, inserting a subnet shifts every
    later index and OpenTofu wants to replace all of them. Stable string keys make
    `for_each` idempotent.

    A subnet only gets a network security group when `security_rules` is non-empty;
    an empty NSG is noise, not security.

    Example:
    ```
    subnets = {
      system = {
        address_prefixes  = ["10.42.0.0/22"]
        service_endpoints = ["Microsoft.ContainerRegistry"]
      }
      user = {
        address_prefixes = ["10.42.4.0/22"]
      }
    }
    ```
  EOT

  type = map(object({
    address_prefixes                  = list(string)
    service_endpoints                 = optional(list(string), [])
    private_endpoint_network_policies = optional(string, "Enabled")
    default_outbound_access_enabled   = optional(bool, true)

    delegation = optional(object({
      name    = string
      service = string
      actions = optional(list(string), [])
    }), null)

    security_rules = optional(list(object({
      name        = string
      priority    = number
      direction   = string
      access      = string
      protocol    = string
      description = optional(string)

      source_port_range       = optional(string)
      source_port_ranges      = optional(set(string))
      destination_port_range  = optional(string)
      destination_port_ranges = optional(set(string))

      source_address_prefix        = optional(string)
      source_address_prefixes      = optional(set(string))
      destination_address_prefix   = optional(string)
      destination_address_prefixes = optional(set(string))

      source_application_security_group_ids      = optional(set(string))
      destination_application_security_group_ids = optional(set(string))
    })), [])
  }))

  validation {
    condition     = length(var.subnets) > 0
    error_message = "subnets must not be empty — a virtual network without subnets is never what was meant."
  }

  validation {
    condition     = alltrue([for k, v in var.subnets : length(v.address_prefixes) > 0])
    error_message = "every subnet needs at least one entry in address_prefixes."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : alltrue([
        for cidr in v.address_prefixes : can(cidrhost(cidr, 0))
      ])
    ])
    error_message = "every subnet address prefix must be a valid CIDR block."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : contains(
        ["Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"],
        v.private_endpoint_network_policies
      )
    ])
    error_message = "private_endpoint_network_policies must be one of: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : alltrue([
        for r in v.security_rules : r.priority >= 100 && r.priority <= 4096
      ])
    ])
    error_message = "security rule priority must be between 100 and 4096."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : alltrue([
        for r in v.security_rules : contains(["Inbound", "Outbound"], r.direction)
      ])
    ])
    error_message = "security rule direction must be either `Inbound` or `Outbound`."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : alltrue([
        for r in v.security_rules : contains(["Allow", "Deny"], r.access)
      ])
    ])
    error_message = "security rule access must be either `Allow` or `Deny`."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : alltrue([
        for r in v.security_rules : contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], r.protocol)
      ])
    ])
    error_message = "security rule protocol must be one of: Tcp, Udp, Icmp, Esp, Ah, *."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : alltrue([
        for r in v.security_rules :
        (r.source_port_range != null) != (r.source_port_ranges != null) &&
        (r.destination_port_range != null) != (r.destination_port_ranges != null) &&
        (r.source_address_prefix != null) != (r.source_address_prefixes != null) &&
        (r.destination_address_prefix != null) != (r.destination_address_prefixes != null)
      ])
    ])
    error_message = "each security rule must set exactly one of `source_port_range`/`source_port_ranges`, `destination_port_range`/`destination_port_ranges`, `source_address_prefix`/`source_address_prefixes`, and `destination_address_prefix`/`destination_address_prefixes`."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      length(distinct([for r in v.security_rules : r.priority])) == length(v.security_rules)
    ])
    error_message = "security rule priorities must be unique within a subnet."
  }
}

variable "tags" {
  description = "Tags applied to the virtual network, subnets' NSGs and all other taggable resources in this module."
  type        = map(string)
  default     = {}
}
