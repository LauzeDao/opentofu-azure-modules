# `networking`

Virtual network with map-keyed subnets and optional per-subnet network security groups.

The network foundation the AKS module sits on. Deliberately scoped to VNet, subnets and
NSGs — no route tables, no firewall, no peerings.

## Usage

```hcl
module "networking" {
  source = "git::https://github.com/<owner>/opentofu-azure-modules.git//modules/networking?ref=v0.1.0"

  name                = "vnet-demo-dev"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  address_space       = ["10.42.0.0/16"]

  subnets = {
    system = {
      address_prefixes  = ["10.42.0.0/22"]
      service_endpoints = ["Microsoft.ContainerRegistry", "Microsoft.KeyVault"]
    }

    user = {
      address_prefixes = ["10.42.4.0/22"]
    }

    restricted = {
      address_prefixes = ["10.42.8.0/24"]

      # Declaring rules is what creates the NSG — see below.
      security_rules = [{
        name                       = "allow-https-inbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "Internet"
        destination_address_prefix = "*"
      }]
    }
  }

  tags = { environment = "dev" }
}
```

Wire the subnets into AKS via the `subnet_ids` output:

```hcl
module "aks" {
  # ...
  system_node_pool = {
    vnet_subnet_id = module.networking.subnet_ids["system"]
  }
}
```

## Notes worth knowing

- **`subnets` is a map, not a list.** With a list, inserting a subnet at the front shifts
  every later index and OpenTofu wants to replace all of them. Stable string keys make
  `for_each` idempotent. The map key also becomes the subnet's Azure name.

- **An NSG is created only for subnets that declare `security_rules`.** A subnet with no
  rules gets no NSG and no association at all. An empty NSG is portal noise, not a security
  control. The `nsg_ids` output therefore contains *fewer* entries than `subnet_ids` — that
  is intended, not a bug.

- **NSGs are named `nsg-<vnet>-<subnet key>`.** Derived, not configurable, so they are
  identifiable in the portal without a lookup.

- **Subnets are separate resources, never the inline `subnet` attribute** of
  `azurerm_virtual_network`. The inline form silently removes any subnet created outside this
  configuration on every apply.

- **Each security rule must set exactly one of `source_port_range` / `source_port_ranges`**
  (and likewise for destination ports and both address prefixes). Azure rejects both-or-neither;
  the validation catches it before the provider does.

- **`security_rule` is a typed set attribute in azurerm 4.x**, not a nested block. Rule order
  in your list carries no meaning — priority does.

## Tests

```bash
tofu -chdir=modules/networking test
```

Covers subnet expansion, delegation, the conditional-NSG logic in both directions, output
shapes, and every validation rule negatively — see [`tests/`](tests/).
