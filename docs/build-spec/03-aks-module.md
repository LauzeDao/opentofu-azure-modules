# Phase 3 — `modules/aks` (Kernstück)

Schema-Referenz: azurerm **4.x**. Die 4.0-Umbenennungen sind eingearbeitet —
`enable_auto_scaling` → `auto_scaling_enabled`, `enable_host_encryption` → `host_encryption_enabled`,
`enable_node_public_ip` → `node_public_ip_enabled`.

---

## 1. Contract — Inputs

### Pflicht

| Input | Typ | Zweck |
|---|---|---|
| `name` | `string` | Cluster-Name |
| `resource_group_name` | `string` | Aus `module.resource_group.name` |
| `location` | `string` | Region |
| `system_node_pool` | `object` | Siehe unten — der `default_node_pool` |

### Cluster-Ebene

| Input | Typ | Default | Zweck |
|---|---|---|---|
| `dns_prefix` | `string` | `null` → fällt auf `name` zurück | |
| `kubernetes_version` | `string` | `null` = Azure-Default | `null` ist bewusst erlaubt, siehe Entscheidungen |
| `sku_tier` | `string` | `"Free"` | `Free`/`Standard`/`Premium`; Kostenbewusstsein (§5) |
| `automatic_upgrade_channel` | `string` | `"patch"` | `none`/`patch`/`rapid`/`stable`/`node-image` |
| `node_os_upgrade_channel` | `string` | `"NodeImage"` | |
| `local_account_disabled` | `bool` | `false` | Bei `true` ist Entra-RBAC Pflicht |
| `tags` | `map(string)` | `{}` | |

### Add-ons

Diese vier existieren, weil ein Consumer sie sonst **gar nicht** einschalten könnte — der
Contract soll exponieren, was realistisch gebraucht wird (§4). Defaults bleiben aus, weil jedes
Add-on zusätzliche System-Pods auf den `Standard_B2s`-Nodes bedeutet.

| Input | Typ | Default | Zweck |
|---|---|---|---|
| `azure_policy_enabled` | `bool` | `false` | Gatekeeper/OPA-Constraints im Cluster |
| `key_vault_secrets_provider` | `object` | `null` | Secrets-Store-CSI-Driver; bei Opt-in ist `secret_rotation_enabled` per Default `true` |
| `disk_encryption_set_id` | `string` | `null` | CMK-Verschlüsselung der Node-Disks |
| `image_cleaner_enabled` / `_interval_hours` | `bool` / `number` | `false` / `48` | Entfernt unbenutzte Images von den Nodes |

### Identität

| Input | Typ | Default | Zweck |
|---|---|---|---|
| `identity_type` | `string` | `"SystemAssigned"` | `SystemAssigned` oder `UserAssigned` |
| `identity_ids` | `list(string)` | `[]` | Nur bei `UserAssigned`, dann Pflicht |

### Netzwerk

| Input | Typ | Default | Zweck |
|---|---|---|---|
| `network_plugin` | `string` | `"azure"` | `azure`/`kubenet`/`none` |
| `network_plugin_mode` | `string` | `"overlay"` | Overlay spart VNet-IPs massiv |
| `network_policy` | `string` | `"calico"` | `calico`/`azure`/`cilium` |
| `network_data_plane` | `string` | `null` | Für `cilium` erforderlich |
| `service_cidr` | `string` | `"10.0.0.0/16"` | Darf sich nicht mit dem VNet überschneiden |
| `dns_service_ip` | `string` | `"10.0.0.10"` | Muss *innerhalb* `service_cidr` liegen |
| `pod_cidr` | `string` | `"10.244.0.0/16"` | Nur bei Overlay/kubenet relevant |
| `load_balancer_sku` | `string` | `"standard"` | |
| `outbound_type` | `string` | `"loadBalancer"` | |

### API-Server-Zugriff

| Input | Typ | Default | Zweck |
|---|---|---|---|
| `private_cluster_enabled` | `bool` | `false` | Default offen, damit CI den Cluster erreicht |
| `api_server_authorized_ip_ranges` | `set(string)` | `[]` | Leer = offen; **im Produktivbetrieb setzen** |

### Entra-ID-RBAC

| Input | Typ | Default |
|---|---|---|
| `azure_rbac_enabled` | `bool` | `true` |
| `admin_group_object_ids` | `list(string)` | `[]` |
| `tenant_id` | `string` | `null` |

### Node Pools

`system_node_pool` (Objekt, wird zum `default_node_pool`):

| Attribut | Typ | Default | Zweck |
|---|---|---|---|
| `name` | `string` | `"system"` | |
| `vm_size` | `string` | `"Standard_B2s"` | Kleinste sinnvolle SKU (§5) |
| `node_count` | `number` | `1` | Ignoriert wenn Autoscaling an |
| `auto_scaling_enabled` | `bool` | `false` | |
| `min_count` / `max_count` | `number` | `null` | Pflicht wenn Autoscaling an |
| `only_critical_addons_enabled` | `bool` | `false` | Setzt den `CriticalAddonsOnly`-Taint |
| `vnet_subnet_id` | `string` | `null` | Aus `module.networking.subnet_ids["system"]` |
| `zones`, `os_disk_size_gb`, `os_disk_type`, `os_sku`, `max_pods`, `node_labels` | | | Durchgereicht |

`user_node_pools` — **Map** `name → object` (gleiche Begründung wie bei den Subnets in Phase 2:
stabile Keys, idempotentes `for_each`). Zusätzlich zu den obigen Attributen:

| Attribut | Typ | Default | Zweck |
|---|---|---|---|
| `mode` | `string` | `"User"` | |
| `node_taints` | `list(string)` | `[]` | |
| `priority` | `string` | `"Regular"` | `Spot` für billige Batch-Pools |
| `eviction_policy`, `spot_max_price` | | | Nur bei `Spot` |

**Nicht** als Input exponiert: `oidc_issuer_enabled`, `workload_identity_enabled`. Beide sind im
Code fest `true`. Siehe [ADR 0004](../adr/0004-oidc-workload-identity-immer-aktiv.md).

---

## 2. Contract — Outputs

| Output | Sensitiv | Zweck |
|---|---|---|
| `id`, `name` | | Referenzen, Role-Assignment-Scopes |
| `fqdn` | | API-Server-Endpoint |
| `node_resource_group` | | Die `MC_…`-RG, für Ressourcen-Lookups |
| `oidc_issuer_url` | | **Für Federated Credentials** — der Kern von Workload Identity |
| `kubelet_identity_object_id` | | **Für AcrPull** — geht an `modules/acr` |
| `kubelet_identity_client_id` | | |
| `kubelet_identity_id` | | Die UAMI-Resource-ID |
| `cluster_identity_principal_id` | | Control-Plane-Identität, z. B. für Network Contributor |
| `kube_config_raw` | ja | Vollständige kubeconfig |
| `host`, `client_certificate`, `client_key`, `cluster_ca_certificate` | ja | Für den `kubernetes`-Provider im Consumer |

Alle `kube_config`-Outputs sind `sensitive = true`. Das ist nicht Kosmetik: ohne das Flag landen
Client-Zertifikate im CI-Log.

---

## 3. Entscheidungen

- **`kubernetes_version` darf `null` sein.** Eine harte Default-Version veraltet und macht das Modul
  binnen Monaten unbenutzbar (Azure entfernt alte Minor-Versionen). `null` heißt „nimm den
  Azure-Default"; wer reproduzierbar sein will, pinnt im Root. Die `validation` erzwingt lediglich
  das Format `X.Y` oder `X.Y.Z`, keine Versionsliste.
- **`only_critical_addons_enabled` erzwingt einen User-Pool.** Ist der Taint gesetzt und es gibt
  keinen `user_node_pools`-Eintrag, hat der Cluster nirgends Platz für Workloads. Das prüft eine
  Cross-Variable-`validation` — Fehler beim `plan`, nicht 20 Minuten später beim `apply`.
- **`temporary_name_for_rotation` ist gesetzt.** Ohne dieses Feld schlägt jede Änderung am
  `default_node_pool`, die einen Rebuild erzwingt (z. B. `vm_size`), mit einem sperrigen
  Provider-Fehler fehl. Mit ihm rotiert der Pool sauber durch.
- **`network_plugin_mode = "overlay"` als Default.** Azure CNI ohne Overlay vergibt pro Pod eine
  VNet-IP; ein `/22`-Subnet ist damit bei ~1000 Pods erschöpft. Overlay entkoppelt Pod-IPs vom VNet.
- **Kein `service_principal`-Block.** Der Provider unterstützt ihn noch; er bedeutet einen
  langlebigen Client-Secret im State. Verboten durch §5 („keine Client-Secrets für Identitäten").
- **`lifecycle { ignore_changes = [default_node_pool[0].node_count] }` wird *nicht* gesetzt.**
  Das ist bei Autoscaling ein verbreiteter Reflex, aber `node_count` ist bei aktivem Autoscaling
  bereits computed — das `ignore_changes` verdeckt dann echte Drifts an anderer Stelle.

---

## 4. Validierungen

| Variable | Regel | Warum |
|---|---|---|
| `name` | 1–63 Zeichen, alphanumerisch + `-`/`_`, Start/Ende alphanumerisch | Azure-Regel |
| `kubernetes_version` | `null` oder `^\d+\.\d+(\.\d+)?$` | Tippfehler wie `1.30-lts` früh fangen |
| `sku_tier` | ∈ {Free, Standard, Premium} | |
| `automatic_upgrade_channel` | ∈ {none, patch, rapid, stable, node-image} | |
| `identity_ids` | nicht leer, *wenn* `identity_type == "UserAssigned"` | Cross-Variable |
| `service_cidr`, `pod_cidr` | gültiges CIDR | |
| `dns_service_ip` | liegt innerhalb `service_cidr` | Cross-Variable; sonst startet CoreDNS nie |
| `network_plugin` / `_mode` / `network_policy` | erlaubte Werte | |
| `network_data_plane` | gesetzt auf `cilium` *wenn* `network_policy == "cilium"` | Cross-Variable |
| `system_node_pool` | `min_count`/`max_count` gesetzt gdw. `auto_scaling_enabled`; `min ≤ max` | |
| `system_node_pool.only_critical_addons_enabled` | verlangt ≥1 `user_node_pools` | Cross-Variable |
| `user_node_pools` | `priority == "Spot"` ⟹ `eviction_policy` gesetzt | |
| `api_server_authorized_ip_ranges` | jedes Element gültiges CIDR | |

---

## 5. Tests — `modules/aks/tests/`

Alles mit `mock_provider "azurerm"`, `command = plan`.

**Positiv**
- Minimal-Konfiguration (nur Pflicht-Inputs) plant durch.
- `oidc_issuer_enabled` **und** `workload_identity_enabled` sind `true` — auch wenn der Consumer
  nichts dazu gesagt hat. Das ist der Test, der ADR 0004 durchsetzt.
- `dns_prefix` fällt korrekt auf `name` zurück.
- Drei `user_node_pools` → drei `azurerm_kubernetes_cluster_node_pool`, Keys wie in der Eingabe.
- `only_critical_addons_enabled = true` + ein User-Pool → plant durch, Taint gesetzt.
- Autoscaling-Pfad: `min_count`/`max_count` landen an der Ressource.
- `identity_type = "UserAssigned"` mit `identity_ids` → `identity.type` korrekt.
- Spot-Pool mit `eviction_policy` → plant durch.

**Negativ (`expect_failures`)**
- `kubernetes_version = "1.30-lts"`.
- `dns_service_ip` außerhalb `service_cidr`.
- `identity_type = "UserAssigned"` ohne `identity_ids`.
- `only_critical_addons_enabled = true` ohne User-Pool.
- Autoscaling an, `min_count` fehlt.
- `min_count > max_count`.
- `network_policy = "cilium"` ohne `network_data_plane`.
- `sku_tier = "Gratis"`.
- Kaputtes CIDR in `api_server_authorized_ip_ranges`.

---

## 6. DoD

- `modules/aks/{main,variables,outputs,versions}.tf` + generiertes `README.md`.
- Kein `provider`-Block, kein `service_principal`-Block, kein `depends_on` nach außen.
- `oidc_issuer_enabled = true` und `workload_identity_enabled = true` **hartkodiert**.
- Alle `kube_config`-nahen Outputs `sensitive = true`.
- `tofu -chdir=modules/aks test` grün, Positiv- **und** Negativ-Tests.
- `tofu init -backend=false && tofu validate` und `tflint --recursive` grün.
- ~~`checkov` ohne unerklärte Findings, jeder Skip in `.checkov.yaml` begründet~~ —
      entfällt, siehe [ADR 0009](../adr/0009-vereinfachtes-repo-layout.md).
