# Phase 5 — das Root-Modul

Das ist **kein** Pseudo-Code-Beispiel. Es muss `tofu apply` überleben, `kubectl get nodes` liefern
und sich rückstandsfrei zerstören lassen.

---

## 1. Dateien

| Datei | Committed | Zweck |
|---|---|---|
| `main.tf` | ja | Die fünf Modul-Aufrufe + Naming-Locals |
| `variables.tf` | ja | Nur das, was ein Consumer wirklich entscheiden muss |
| `outputs.tf` | ja | Cluster-Zugriff, ACR-Login-Server, Vault-URI |
| `versions.tf` | ja | Provider-Pins + `provider "azurerm"`-Block (hier ist er richtig!) |
| `terraform.tfvars.example` | ja | Vorlage mit Platzhaltern |
| `backend.tf.example` | ja | Backend-Vorlage; die echte `backend.tf` ist gitignored |
| `terraform.tfvars` | nein | Echte Werte — gitignored (§5) |
| `README.md` | ja | Handgeschrieben (kein Modul → kein terraform-docs) |

---

## 2. Naming — zentral im Root

Die Konvention `<project>-<env>-<resource>` wird aus dem Root per Locals gesteuert, **nicht** in
den Modulen. Also:

```hcl
locals {
  prefix = "${var.project}-${var.environment}"

  names = {
    resource_group = "rg-${local.prefix}"
    vnet           = "vnet-${local.prefix}"
    aks            = "aks-${local.prefix}"
    key_vault      = "kv-${local.prefix}"
    # ACR erlaubt KEINE Bindestriche → eigene Normalisierung
    acr = substr(replace("acr${local.prefix}", "-", ""), 0, 50)
  }

  common_tags = merge(var.tags, {
    project     = var.project
    environment = var.environment
    managed_by  = "opentofu"
    repository  = "opentofu-azure-modules"
  })
}
```

Die ACR-Zeile ist der interessante Teil: die generische Konvention **bricht** bei ACR (nur
alphanumerisch, max. 50). Statt das im ACR-Modul zu verstecken, korrigiert es das Root sichtbar —
genau da, wo Naming laut Contract hingehört. Der Kommentar im Code sagt warum.

Key Vault hat dieselbe Enge (max. 24 Zeichen). `var.project` und `var.environment` bekommen daher
`validation`-Blocks mit Längengrenzen, damit ein zu langer Projektname *hier* auffällt und nicht in
einem abgeschnittenen Vault-Namen endet.

---

## 3. Komposition

```hcl
module "resource_group" {
  source   = "../../modules/resource-group"
  name     = local.names.resource_group
  location = var.location
  tags     = local.common_tags
}

module "networking" {
  source              = "../../modules/networking"
  name                = local.names.vnet
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  address_space       = [var.vnet_address_space]

  subnets = {
    system = {
      address_prefixes  = [cidrsubnet(var.vnet_address_space, 6, 0)]
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    }
    user = {
      address_prefixes = [cidrsubnet(var.vnet_address_space, 6, 1)]
    }
  }

  tags = local.common_tags
}

module "aks" { /* system_node_pool.vnet_subnet_id = module.networking.subnet_ids["system"] */ }

module "acr" {
  # ...
  role_assignments = {
    aks_kubelet = {
      principal_id   = module.aks.kubelet_identity_object_id
      role           = "AcrPull"
      principal_type = "ServicePrincipal"
    }
  }
}

module "key_vault" {
  # ...
  role_assignments = {
    # Der Deployer braucht die Rolle, um überhaupt Secrets schreiben zu können —
    # bei RBAC-Vaults ist "Contributor" dafür NICHT ausreichend.
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
}
```

`cidrsubnet` statt hartkodierter Subnet-CIDRs: der Consumer gibt *ein* VNet-CIDR an, die Aufteilung
ist deterministisch. Kommentiert, weil §5 „kein `count`/`for_each`-Wildwuchs ohne Kommentar" auch
für Rechen-Cleverness gilt.

---

## 4. Variablen

| Variable | Typ | Default | Anmerkung |
|---|---|---|---|
| `project` | `string` | — | ≤ 8 Zeichen (Key-Vault-Namenslänge) |
| `environment` | `string` | — | ≤ 6 Zeichen, ∈ {dev, test, stage, prod} |
| `location` | `string` | `"germanywestcentral"` | |
| `subscription_id` | `string` | — | Für den `provider`-Block; **nie** hartkodiert (§10) |
| `tenant_id` | `string` | — | Für das Key-Vault-Modul |
| `deployer_principal_id` | `string` | — | Objekt-ID der ausführenden Identität |
| `vnet_address_space` | `string` | `"10.42.0.0/16"` | |
| `kubernetes_version` | `string` | `null` | |
| `system_node_vm_size` | `string` | `"Standard_B2s"` | Kostenbewusstsein (§5) |
| `user_node_vm_size` | `string` | `"Standard_B2s"` | |
| `enable_user_node_pool` | `bool` | `true` | |
| `admin_group_object_ids` | `list(string)` | `[]` | |
| `api_server_authorized_ip_ranges` | `set(string)` | `[]` | |
| `tags` | `map(string)` | `{}` | |

---

## 5. Provider-Block

Hier — und **nur** hier — steht `provider "azurerm"`:

```hcl
provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  features {
    key_vault {
      # Passend zu purge_protection_enabled = false: der destroy-Pfad muss sauber sein (§7).
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
```

Das `features`-Block-Detail ist der Grund, warum ein `destroy` beim zweiten CI-Lauf nicht am
„Vault-Name bereits vergeben (soft-deleted)"-Fehler scheitert.

---

## 6. Verifikation

Ohne Azure-Credentials (das, was lokal und in PR-CI möglich ist):

```bash
tofu -chdir=examples/aks-cluster init -backend=false
tofu -chdir=examples/aks-cluster validate
```

Mit Credentials — der echte DoD-Nachweis:

```bash
cd examples/aks-cluster
cp terraform.tfvars.example terraform.tfvars   # ausfüllen
tofu init -backend-config=...
tofu plan -out=tfplan
tofu apply tfplan
az aks get-credentials --resource-group rg-<prefix> --name aks-<prefix>
kubectl get nodes                              # ← der eigentliche Beweis
tofu destroy -auto-approve
```

`plan` allein reicht als Nachweis **nicht**. Ein Plan bestätigt nur, dass die Konfiguration
in sich schlüssig ist — nicht, dass Azure die Kombination aus Region, VM-SKU und
Kubernetes-Version akzeptiert oder dass das AcrPull-Assignment greift.

---

## 7. DoD

- `` komplett, `terraform.tfvars.example` und `backend.tf.example` dabei.
- Genau **ein** `provider "azurerm"`-Block im ganzen Repo, und der steht hier.
- Naming ausschließlich über `locals`; kein Modul erzeugt Namen selbst.
- ACR- und Key-Vault-Namensgrenzen im Root behandelt, mit Kommentar.
- `tofu validate` grün.
- Echter `apply` → `kubectl get nodes` erfolgreich → `destroy` rückstandsfrei, mindestens
      einmal nachweislich durchlaufen (CI-Run-Link im PR).
- Nach dem `destroy`: `az group list` zeigt keine verwaiste RG, `az keyvault list-deleted`
      keinen soft-deleted Vault (§7 — CI hinterlässt keine Kosten).
