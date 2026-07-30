# Deployment-Checkliste

Alles, was zwischen „Repo geklont" und „AKS-Cluster läuft" noch zu tun ist. Zwei Wege:

- **[Weg A: lokal](#weg-a-lokal-deployen)** — nur `az login`, keine Azure-DevOps-Einrichtung.
  Der schnellste Weg zum ersten Cluster.
- **[Weg B: über die Pipeline](#weg-b-über-die-pipeline)** — einmalige Einrichtung, danach ein
  Klick, mit Freigabe und automatischem Aufräumen.

Fang mit Weg A an. Wenn das läuft, weißt du, dass der Code funktioniert — und kannst
Pipeline-Probleme davon trennen.

---

## Weg A: lokal deployen

### A1 — Voraussetzungen

- [ ] `tofu` ≥ 1.9 (`tofu version`)
- [ ] Azure CLI (`az version`)
- [ ] `kubectl` (`az aks install-cli`)
- [ ] Eine Azure-Subscription, in der du Ressourcen anlegen darfst
- [ ] Auf der Subscription: **`Owner`** — oder `Contributor` **plus**
      `User Access Administrator`

> Die letzte Zeile ist der häufigste Stolperstein. Die Module vergeben Role Assignments
> (AcrPull an die Kubelet-Identität, Key Vault RBAC). **`Contributor` allein darf das
> nicht.** Ohne die zweite Rolle scheitert der Apply erst *nach* dem Cluster-Bau — nach
> etwa zehn Minuten, mit Ressourcen am Netz, die Geld kosten.

### A2 — Anmelden und Werte setzen

```bash
az login
az account set --subscription "<deine-subscription>"

export TF_VAR_subscription_id=`az account show --query id -o tsv`
export TF_VAR_tenant_id=`az account show --query tenantId -o tsv`
export TF_VAR_deployer_principal_id=`az ad signed-in-user show --query id -o tsv`
```

`terraform.tfvars` **nicht** bearbeiten — die Datei ist committet und enthält absichtlich nur
Null-Platzhalter. Die drei Environment-Variablen überschreiben sie. Siehe
[`pipeline.md` §4](pipeline.md#4-nicht-offensichtliche-details).

Optional anpassen (in `terraform.tfvars` oder per `TF_VAR_*`):

```bash
export TF_VAR_project=demo            # max. 8 Zeichen, klein
export TF_VAR_environment=dev         # dev | test | stage | prod
export TF_VAR_location=germanywestcentral
```

### A3 — Deployen

```bash
tofu init
tofu plan -out=tfplan
tofu apply tfplan
```

Der State liegt dabei **lokal** in `terraform.tfstate` (gitignored). Für einen Alleingang ist
das in Ordnung; für alles Geteilte siehe [B2](#b2--state-backend-anlegen).

### A4 — Nachweisen, dass es wirklich läuft

```bash
eval `tofu output -raw get_credentials_command`
kubectl get nodes
az acr login --name `tofu output -raw acr_name`
```

`kubectl get nodes` ist der eigentliche Beweis. Ein grüner `plan` sagt nur, dass die
Konfiguration in sich schlüssig ist — nicht, dass Azure die Kombination aus Region,
VM-Größe und Kubernetes-Version akzeptiert.

### A5 — Aufräumen

```bash
tofu destroy

az group list --query "[?starts_with(name,'rg-demo-dev')].name" -o tsv
az keyvault list-deleted --query "[?starts_with(name,'kv-demo-dev')].name" -o tsv
```

Beide Abfragen müssen **leer** sein. Ein soft-deleted Key Vault blockiert den Namen 7 Tage
und lässt den nächsten Apply scheitern.

---

## Weg B: über die Pipeline

### B1 — Azure DevOps vorbereiten

- [ ] Organisation und Projekt existieren
- [ ] Das Repo ist für Azure Pipelines erreichbar (Azure Repos, oder GitHub via
      Service Connection)

### B2 — State-Backend anlegen

Einmalig, außerhalb dieses Repos — der State darf nicht von der Infrastruktur abhängen, die
er beschreibt.

```bash
LOCATION=germanywestcentral
STATE_RG=rg-tfstate
STATE_SA=sttfstate$RANDOM          # global eindeutig, nur Kleinbuchstaben/Ziffern
STATE_CONTAINER=tfstate

az group create --name "$STATE_RG" --location "$LOCATION"

az storage account create \
  --name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false

az storage container create \
  --name "$STATE_CONTAINER" \
  --account-name "$STATE_SA" \
  --auth-mode login

echo "STATE_RG=$STATE_RG  STATE_SA=$STATE_SA  STATE_CONTAINER=$STATE_CONTAINER"
```

`--allow-shared-key-access false` ist Absicht: damit ist der RBAC-Pfad der einzige, und ein
versehentlich gesetzter Access Key kann nicht funktionieren.

### B3 — Service Connection erstellen

In Azure DevOps: **Project Settings → Service connections → New → Azure Resource Manager →
Workload Identity federation (automatic)**.

- [ ] Subscription auswählen, Namen vergeben (z. B. `azure-opentofu`)
- [ ] **Nicht** „Service principal (secret)" wählen — das wäre ein langlebiges Credential
      und widerspricht den Guardrails des Repos

Azure DevOps legt dabei selbst eine App-Registrierung an. Deren IDs brauchst du im nächsten
Schritt — sie stehen in den Details der Service Connection („Manage Service Principal"), oder:

```bash
SC_APP_ID=<Application (client) ID aus der Service Connection>
SP_OBJECT_ID=`az ad sp show --id "$SC_APP_ID" --query id -o tsv`
echo "$SP_OBJECT_ID"
```

### B4 — Rollen für die Service Connection

```bash
SUBSCRIPTION_ID=`az account show --query id -o tsv`

az role assignment create --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$STATE_RG/providers/Microsoft.Storage/storageAccounts/$STATE_SA/blobServices/default/containers/$STATE_CONTAINER"
```

| Rolle | Wofür | Wenn sie fehlt |
|---|---|---|
| `Contributor` | Ressourcen anlegen und löschen | Apply scheitert sofort |
| `User Access Administrator` | AcrPull- und Key-Vault-RBAC-Assignments | Apply scheitert **nach** dem Cluster-Bau |
| `Storage Blob Data Contributor` | Remote State lesen/schreiben | `tofu init` scheitert mit 403 |

`Contributor` auf Subscription-Ebene ist grob. Für ein Portfolio-Projekt vertretbar; produktiv
würde man auf eine Resource Group einschränken — dann muss die aber vorher existieren und die
Module dürfen sie nicht mehr anlegen.

### B5 — Variable Group

**Pipelines → Library → Variable groups → New**, Name exakt **`opentofu-azure`**:

- [ ] `AZURE_SERVICE_CONNECTION` = Name aus [B3](#b3--service-connection-erstellen), z. B. `azure-opentofu`
- [ ] `AZURE_SUBSCRIPTION_ID` = Subscription-GUID
- [ ] `TFSTATE_RESOURCE_GROUP` = `$STATE_RG`
- [ ] `TFSTATE_STORAGE_ACCOUNT` = `$STATE_SA`
- [ ] `TFSTATE_CONTAINER` = `$STATE_CONTAINER`

Keiner dieser Werte ist ein Secret — es sind Namen und Bezeichner. Nichts davon als „secret"
markieren, sonst sind sie in den Skripten nicht lesbar.

### B6 — Environment mit Freigabe

**Pipelines → Environments → New environment**, Name exakt **`azure-apply`**:

- [ ] Environment anlegen (Typ: None)
- [ ] **Approvals and checks → Approvals** hinzufügen, dich selbst als Genehmiger

Das ist die Kostenbremse. Ohne diesen Schritt legt jeder versehentliche Start einen Cluster an.

### B7 — Die beiden Pipelines registrieren

- [ ] **Pipelines → New pipeline** → Repo wählen → *Existing Azure Pipelines YAML file* →
      `/pipelines/ci.yml` → speichern
- [ ] Dasselbe für `/pipelines/apply.yml`
- [ ] Beide sinnvoll benennen, z. B. `opentofu-ci` und `opentofu-apply`

> Weil die Dateien in `pipelines/` liegen und nicht als `azure-pipelines.yml` im Root,
> erkennt Azure DevOps sie nicht automatisch — du wählst den Pfad einmal manuell aus. Das ist
> der ganze Preis für den aufgeräumten Repo-Root.

### B8 — Branch Policy

- [ ] **Repos → Branches → `main` → Branch policies → Build validation** → `opentofu-ci`

Ohne diesen Schritt blockiert die CI-Pipeline keine Pull Requests. Die `pr:`-Angabe in der
YAML-Datei allein reicht bei Azure Repos **nicht** — anders als bei GitHub Actions.

### B9 — Erster Lauf

- [ ] `opentofu-ci` manuell starten → muss grün werden, braucht keine Credentials
- [ ] `opentofu-apply` starten, `destroyAfterwards` **angeschaltet lassen**
- [ ] Freigabe erteilen
- [ ] Im Log prüfen: `kubectl get nodes` zeigt Nodes, letzter Schritt meldet
      „Clean: no orphaned resource groups"

Beim ersten Lauf ist Nacharbeit wahrscheinlich; die häufigsten Fehler stehen unten unter
[Troubleshooting](#troubleshooting).

---

## Troubleshooting

| Symptom | Ursache | Behebung |
|---|---|---|
| `AuthorizationFailed` bei `azurerm_role_assignment` | `User Access Administrator` fehlt | [B4](#b4--rollen-für-die-service-connection) |
| `tofu init`: 403 auf den State-Blob | `Storage Blob Data Contributor` fehlt, oder Rolle noch nicht propagiert (bis 5 min) | [B4](#b4--rollen-für-die-service-connection), dann warten |
| `A vault with the same name already exists in deleted state` | soft-deleted Key Vault aus einem früheren Lauf | `az keyvault purge --name <name>` |
| `idToken` ist leer, Auth scheitert | Service Connection ist nicht *Workload Identity federation* | neu anlegen, [B3](#b3--service-connection-erstellen) |
| CI meldet „terraform.tfvars holds a non-placeholder value" | echte Subscription-/Tenant-ID committet | zurücksetzen auf Nullen, `TF_VAR_*` benutzen |
| tflint meldet 10× `terraform_required_providers` | `--config` mit absolutem Pfad fehlt | [`pipeline.md` §4](pipeline.md#4-nicht-offensichtliche-details) |
| `init` bricht mit Checksummen-Fehler ab | Lock-Datei ohne `linux_amd64`-Hashes | `tofu providers lock` mit allen Plattformen, siehe [`pipeline.md` §4](pipeline.md#4-nicht-offensichtliche-details) |
| Cluster steht noch, Pipeline war rot | `destroyAfterwards` war aus, oder Destroy scheiterte | State-Key aus dem Log nehmen, lokal `tofu init -backend-config="key=<key>"` + `tofu destroy` |

## Kosten

Die Defaults sind auf „billig" getrimmt: `Standard_B2s`-Nodes, `Free`-Control-Plane,
`Basic`-Registry, `standard`-Vault. Der Löwenanteil sind die Node-VMs plus der Standard Load
Balancer.

Es kostet trotzdem, solange es läuft. Die Apply-Pipeline zerstört deshalb standardmäßig
sofort wieder — und prüft danach, dass nichts übrig ist.
