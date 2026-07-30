variable "name" {
  description = <<-EOT
    Full resource group name. The naming convention is applied by the root module, not
    here.
  EOT
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 90
    error_message = "name must be between 1 and 90 characters (Azure limit); got ${length(var.name)}."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]+$", var.name))
    error_message = "name may only contain letters, digits, '.', '_', '-', '(' and ')'."
  }

  validation {
    condition     = !endswith(var.name, ".")
    error_message = "name must not end with a period."
  }
}

variable "location" {
  description = "Azure region, in the short form Azure expects (e.g. `germanywestcentral`, not `Germany West Central`)."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be the short region name: lowercase letters and digits only (e.g. `germanywestcentral`)."
  }
}

variable "tags" {
  description = "Tags applied to the resource group. Consumers typically pass a merged set of common tags."
  type        = map(string)
  default     = {}
}
