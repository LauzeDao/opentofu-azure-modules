# `resource-group`

Azure resource group with tag pass-through and up-front name validation.

The deliberately boring module of this library. It does not exist because
`azurerm_resource_group` is difficult — it exists so that every downstream module draws
`name` and `location` from **one** place instead of from four separate root variables, and
so tag inheritance has a single home.

## Usage

```hcl
module "resource_group" {
  source = "git::https://github.com/<owner>/opentofu-azure-modules.git//modules/resource-group?ref=v0.1.0"

  name     = "rg-demo-dev"
  location = "germanywestcentral"

  tags = {
    environment = "dev"
    managed_by  = "opentofu"
  }
}
```

Then feed it into the other modules:

```hcl
module "networking" {
  source = "../networking"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  # ...
}
```

## Notes worth knowing

- **The name is not built here.** The `<project>-<env>-<resource>` convention lives in the
  root module, not in this module. Pass a complete name in.
- **`location` wants the short form.** `germanywestcentral`, not `Germany West Central`. The
  validation enforces this, because the display name fails only at apply time with an
  unhelpful message.
- **A trailing period is rejected.** It is a legal character *inside* a resource group name
  but illegal at the end — a genuine Azure rule that otherwise surfaces minutes into an
  apply.
- **No tags are injected.** What you pass is what the resource group gets; the module adds
  nothing of its own.

## Tests

```bash
tofu -chdir=modules/resource-group test
```

Covers the positive path (defaults, tags, 90-character name, all legal special characters)
and every validation rule negatively — see [`tests/`](tests/).
