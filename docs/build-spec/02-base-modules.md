# Phase 2 — Basis-Module

## 1. `modules/resource-group`

Das absichtlich langweiligste Modul im Repo. Es existiert nicht, weil
`azurerm_resource_group` kompliziert wäre, sondern weil es der einheitliche Ort für **Tag-Vererbung**
und **Namens-Validierung** ist — und weil die anderen Module dann `name` + `location` aus *einer*
Quelle beziehen statt aus vier Root-Variablen.

### Contract

| Input | Typ | Default | Zweck |
|---|---|---|---|
| `name` | `string` | — (required) | Vollständiger RG-Name; das Naming-Schema lebt im Root, nicht hier (§4) |
| `location` | `string` | — (required) | Azure-Region |
| `tags` | `map(string)` | `{}` | Tags; wird von Consumern durchgereicht |

| Output | Zweck |
|---|---|
| `name` | Für alle nachgelagerten Module |
| `id` | Für Role Assignments auf RG-Scope |
| `location` | Damit Consumer die Region nicht doppelt herumtragen müssen |

### Validierungen

- `name`: 1–90 Zeichen, erlaubt sind Buchstaben/Ziffern/`.`/`_`/`-`/`(`/`)`, darf **nicht** mit `.`
  enden. Das ist die echte Azure-Regel; sie fällt sonst erst beim `apply` auf.
- `location`: nicht leer, keine Leerzeichen (Azure will `germanywestcentral`, nicht `Germany West Central`).

---

## 2. `modules/networking`

### Contract

| Input | Typ | Default | Zweck |
|---|---|---|---|
| `name` | `string` | — | VNet-Name |
| `resource_group_name` | `string` | — | Aus `module.resource_group.name` |
| `location` | `string` | — | Region |
| `address_space` | `list(string)` | — | VNet-CIDRs |
| `dns_servers` | `list(string)` | `[]` | Leer = Azure-DNS |
| `subnets` | `map(object)` | — | Der Kern des Contracts, siehe unten |
| `tags` | `map(string)` | `{}` | |

`subnets` ist eine **Map mit sprechenden Keys**, nicht eine Liste:

```hcl
subnets = {
  system = {
    address_prefixes  = ["10.42.0.0/22"]
    service_endpoints = ["Microsoft.ContainerRegistry"]
  }
  user = {
    address_prefixes = ["10.42.4.0/22"]
  }
  private_endpoints = {
    address_prefixes = ["10.42.8.0/24"]
    security_rules   = [ /* ... */ ]
  }
}
```

Warum Map und nicht Liste: bei einer Liste verschiebt das Einfügen eines Subnets am Anfang alle
Indizes und OpenTofu will danach **jedes** nachfolgende Subnet neu bauen. Mit stabilen String-Keys
ist `for_each` idempotent. Das ist die Art von Entscheidung, die man einmal trifft und nie bereut.

Objekt-Attribute (alle außer `address_prefixes` optional):

| Attribut | Typ | Default | Zweck |
|---|---|---|---|
| `address_prefixes` | `list(string)` | — | Subnet-CIDR(s) |
| `service_endpoints` | `list(string)` | `[]` | z. B. `Microsoft.KeyVault` |
| `private_endpoint_network_policies` | `string` | `"Enabled"` | `Enabled`/`Disabled`/`NetworkSecurityGroupEnabled`/`RouteTableEnabled` |
| `default_outbound_access_enabled` | `bool` | `true` | |
| `delegation` | `object` | `null` | Für ACI/App-Service-Delegation |
| `security_rules` | `list(object)` | `[]` | **Leer = kein NSG** wird angelegt |

| Output | Zweck |
|---|---|
| `vnet_id`, `vnet_name` | Peering, Private DNS Links |
| `subnet_ids` | Map `key → id`, direkt für `vnet_subnet_id` im AKS-Modul |
| `subnet_names`, `subnet_address_prefixes` | Map `key → …`, für NSG-Regeln im Consumer |
| `nsg_ids` | Map, nur für Subnets *mit* Regeln |

### Entscheidungen

- **NSG nur wo Regeln definiert sind.** Ein leeres NSG anzulegen ist keine Sicherheit, sondern
  Rauschen im Portal. `for_each` läuft daher über
  `{ for k, v in var.subnets : k => v if length(v.security_rules) > 0 }`.
- **Keine inline-`subnet`-Blöcke** in `azurerm_virtual_network`. Der Provider erlaubt das, aber die
  Inline-Variante entfernt bei jedem Apply Subnets, die außerhalb angelegt wurden — ein bekannter
  Fußschuss. Immer separate `azurerm_subnet`-Ressourcen.
- **Kein Route-Table/Firewall-Kram.** Nicht im Scope; das Modul bleibt
  „Netzwerk-Grundlage".

### Validierungen

- Jeder Eintrag in `address_space` und in jedem `address_prefixes` muss ein gültiges CIDR sein
  (`can(cidrhost(x, 0))`).
- `subnets` darf nicht leer sein — ein VNet ohne Subnet ist nie das, was gemeint war.
- Jedes Subnet muss mindestens ein `address_prefixes`-Element haben.
- `private_endpoint_network_policies` nur mit den vier erlaubten Werten.
- Jede `security_rules`-Regel: `priority` 100–4096, `direction` ∈ {Inbound, Outbound},
  `access` ∈ {Allow, Deny}.

---

## 3. Tests

Unter `modules/resource-group/tests/` und `modules/networking/tests/`, alle mit `mock_provider "azurerm"`.

Was geprüft wird — nicht „läuft durch", sondern konkrete Zusicherungen:

**`modules/resource-group/tests/`**
- Defaults: `tags` leer erzeugt trotzdem eine gültige RG.
- Name und Location landen unverändert an der Ressource (kein heimliches `lower()`).
- Negativ: 91-Zeichen-Name, Name mit `.` am Ende, `location` mit Leerzeichen → `expect_failures`.

**`modules/networking/tests/`**
- Drei Subnets in der Map → drei `azurerm_subnet`, mit den erwarteten Keys.
- Nur das Subnet mit `security_rules` erzeugt ein NSG und eine Association; die anderen nicht.
- `subnet_ids`-Output hat genau die Keys der Eingabe-Map.
- `service_endpoints` und `delegation` kommen an der richtigen Ressource an.
- Negativ: kaputtes CIDR, leere `subnets`-Map, `priority = 99`, `direction = "Sideways"`.

---

## 4. DoD

- `modules/resource-group/{main,variables,outputs,versions}.tf` + `README.md` vorhanden.
- `modules/networking/{main,variables,outputs,versions}.tf` + `README.md` vorhanden.
- Kein `provider`-Block in einem der beiden Module.
- `tofu init -backend=false && tofu validate` grün.
- `tofu -chdir=modules/resource-group test && tofu -chdir=modules/networking test` grün, inkl. der Negativ-Tests.
- `tflint --recursive` ohne Findings für beide Module.
- ~~`scripts/docs-check.sh` grün (READMEs generiert)~~ — entfällt, READMEs sind handgeschrieben.
