# Azure-DevOps-Pipelines

Zwei getrennte Pipelines, weil sie unterschiedliche Rechte und unterschiedliche Kosten haben.
Die Trennung ist keine Stilfrage, sondern die Umsetzung von
[ADR 0008](adr/0008-mock-provider-in-ci.md).

| Datei | Zweck | Trigger | Azure-Zugriff | Kosten |
|---|---|---|---|---|
| [`../pipelines/ci.yml`](../pipelines/ci.yml) | `fmt`, `validate`, `tofu test`, `tflint` | jeder Push auf `main`, jeder PR | **keiner** | 0 € |
| [`../pipelines/apply.yml`](../pipelines/apply.yml) | echter `apply` → `kubectl get nodes` → `destroy` | nur manuell | Service Connection | echte Cluster-Kosten |

Beide Definitionen sind bislang nicht gelaufen — sie sind gegen die dokumentierten
Azure-DevOps-Schemata geschrieben, aber ungeprüft. Der wahrscheinlichste Stolperstein beim
ersten Lauf ist die Authentifizierung über die Service Connection (§4).

---

## 1. Die CI-Pipeline

Läuft ohne jeden Azure-Zugriff. Das ist Absicht: das Repo ist öffentlich, und ein
Pull Request bestimmt den ausgeführten Code. Eine Pipeline mit Cloud-Credentials, die auf
`pr:` reagiert, ist eine Rechteausweitung — deshalb hat diese Pipeline keine Service
Connection und kann gar nichts in Azure anfassen.

Ein Job, sieben Gates:

1. **OpenTofu installieren** — feste Version, direkt aus dem GitHub-Release entpackt.
2. **Provider-Cache** (`Cache@2`), gekeyt auf die `.terraform.lock.hcl`-Dateien. Der
   azurerm-Provider ist entpackt **242 MB**, und es gibt sechs Verzeichnisse, die
   initialisieren — siehe §4 zum Zusammenspiel von `TF_PLUGIN_CACHE_DIR` und `Cache@2`.
3. **Guard: keine echten Azure-IDs** — bricht ab, wenn `subscription_id`, `tenant_id` oder
   `deployer_principal_id` in `terraform.tfvars` keine Null-Platzhalter mehr sind. Siehe §4.
4. **`tofu fmt -check -recursive -diff`**
5. **`tofu validate`** über Root und alle fünf Module, mit `-lockfile=readonly` (§4).
6. **`tofu test`** über Root und alle fünf Module.
7. **`tflint`** mit `--config="$PWD/.tflint.hcl"` (§4).

Einrichtung: keine Credentials nötig, nur die Pipeline anlegen und auf `/pipelines/ci.yml`
zeigen (der Pfad muss manuell gewählt werden, siehe [`deployment.md`](deployment.md) §B7).

Damit PRs tatsächlich blockiert werden, braucht es zusätzlich eine Branch Policy auf `main`.
Die `pr:`-Angabe in der YAML-Datei allein löst bei Azure Repos nichts aus — anders als bei
GitHub Actions.

---

## 2. Die Apply-Pipeline

### Was vorher existieren muss

Service Connection, Rollen, Variable Group, Environment und State-Backend — Schritt für
Schritt mit `az`-Kommandos in [`deployment.md`](deployment.md) §B. Kurzfassung:

| Was | Name | Wozu |
|---|---|---|
| Service Connection | frei, z. B. `azure-opentofu` | Azure-Login per Workload Identity Federation, ohne Secret |
| Variable Group | **`opentofu-azure`** | 5 Bezeichner: Service-Connection-Name, Subscription, State-Backend |
| Environment | **`azure-apply`** | trägt den Approval Check — die Kostenbremse |
| Storage Account | frei | Remote State, mit `allow-shared-key-access false` |

Die Rolle, die man vergisst: der Service Principal braucht neben `Contributor` auch
**`User Access Administrator`**. Die Module vergeben Role Assignments, und `Contributor` darf
das nicht — der Apply scheitert sonst erst *nach* dem Cluster-Bau.

### Ablauf

```
Approval → install → backend.tf schreiben → init+plan → apply
        → kubectl get nodes + az acr login
        → destroy (auch bei Fehlschlag)
        → Rückstands-Check (Resource Groups, soft-deleted Vaults)
```

Parameter beim Start: `environmentName` (`dev`/`test`) und `destroyAfterwards` (Default
**an**). Mit abgeschaltetem Destroy bleibt der Cluster stehen und die Pipeline warnt
ausdrücklich — das ist der einzige Weg, absichtlich Kosten zu erzeugen.

### Wann läuft sie?

**Nur wenn du sie startest.** `trigger: none` und `pr: none` bedeuten: kein Push, kein Pull
Request, kein Zeitplan löst sie aus. Du klickst *Run pipeline*, wählst die Parameter, und
gibst dann noch die Freigabe im Environment `azure-apply`.

Sinnvolle Anlässe:

- **Vor einem Versions-Tag.** Ein Tag, dessen Apply nie geprüft wurde, liefert einem Consumer
  eine kaputte Modulversion, die er nicht zurücknehmen kann.
- **Nach einem Provider-Upgrade** (`azurerm ~> 4.0` zieht neue Minor-Versionen).
- **Nach Änderungen an AKS-Defaults** — VM-Größen, Kubernetes-Version, Netzwerk-Modus. Genau
  da liegen die Dinge, die nur Azure selbst beurteilen kann.

Nicht sinnvoll: bei jedem Commit. Ein Lauf dauert ~30 Minuten und kostet echtes Geld.

---

## 3. Die Absicherungen aus ADR 0008

Das ist der eigentliche Inhalt der Apply-Pipeline. Ohne diese vier Punkte ist sie eine
Kostenfalle.

**`condition: always()` auf dem Destroy.** Wenn der Apply auf halber Strecke scheitert,
existieren trotzdem schon Ressourcen. Eine Pipeline, die dann einfach abbricht, hinterlässt
einen laufenden AKS-Cluster. `always()` deckt auch den Abbruch durch den Benutzer ab —
genau das Szenario, das sonst Ressourcen zurücklässt.

**Eigener State-Key pro Lauf** (`ci-$(Build.BuildId).tfstate`). Ein hängender Blob-Lease aus
einem abgebrochenen Lauf blockiert damit den nächsten nicht. Preis: ein Lauf, dessen Destroy
nicht durchkam, hinterlässt eine State-Datei, die niemand mehr aufräumt. Deshalb der nächste
Punkt.

**Rückstands-Check nach dem Destroy.** `az group list` und `az keyvault list-deleted` müssen
leer sein. Ein Destroy, der „erfolgreich" meldet, aber einen soft-deleted Key Vault
hinterlässt, ist nicht rückstandsfrei — und blockiert den Vault-Namen beim nächsten Lauf 7
bis 90 Tage lang ([ADR 0007](adr/0007-purge-protection-default-aus.md)).

**Kein Trigger auf `pr:`.** Die Apply-Pipeline hat `trigger: none` und `pr: none`. Ein
fremder Pull Request kann sie nicht starten.

---

## 4. Nicht offensichtliche Details

**Der Provider-Cache arbeitet auf zwei Ebenen.** Der azurerm-Provider ist entpackt 242 MB,
und dieses Repo hat sechs Verzeichnisse, die initialisieren (Root + fünf Module).

- `TF_PLUGIN_CACHE_DIR` sorgt dafür, dass es **innerhalb** eines Laufs nur *eine* echte Kopie
  gibt: OpenTofu legt in jedem `.terraform/providers` einen Symlink darauf. Ohne die Variable
  werden 6 × 242 MB ≈ 1,5 GB entpackt und sechsmal heruntergeladen.
  (Unter Windows kopiert OpenTofu statt zu verlinken — dort belegt es tatsächlich 1,5 GB.)
- `Cache@2` hebt dieses eine Verzeichnis **zwischen** Läufen auf. Ab dem zweiten Lauf entfällt
  der Download vollständig.

Das ist nicht nur Tempo: Provider-Downloads scheitern gelegentlich mit einer
zurückgesetzten Verbindung. Weniger Downloads heißt weniger rote Läufe aus Gründen, die
nichts mit dem Code zu tun haben.

**`$( )` ist in Azure DevOps Makro-Syntax, nicht Command-Substitution.** Azure DevOps ersetzt
`$(name)` *vor* dem Start des Skripts. Bei `$(az account show --query id -o tsv)` bleibt der
Text zwar meist unangetastet, weil keine Variable so heißt — aber es ist ein stiller
Fußschuss, sobald der Inhalt doch einmal auf einen Variablennamen passt. Die Inline-Skripte
verwenden daher durchgängig Backticks für Command-Substitution. Aus demselben Grund kommt
`AZURE_SUBSCRIPTION_ID` aus der Variable Group statt aus `az account show`.

**`tflint --recursive` braucht `--config="$PWD/.tflint.hcl"`.** Bei `--recursive` wechselt
tflint in jedes Unterverzeichnis und sucht dort eine eigene `.tflint.hcl`. Ohne absoluten
Pfad greift die Root-Config in `modules/*` nicht, und `terraform_required_providers` sowie
`terraform_required_version` melden zehn Falschtreffer — sie erwarten ein `versions.tf` je
Modul, das dieses Repo bewusst nicht hat ([ADR 0009](adr/0009-vereinfachtes-repo-layout.md)).

**`-lockfile=readonly` beim `init`.** Die committeten `.terraform.lock.hcl` enthalten Hashes
für `linux_amd64`, `linux_arm64`, `darwin_arm64` und `windows_amd64`. Der Flag erzwingt, dass
der Linux-Agent die Datei nicht stillschweigend umschreibt. Fehlt eine Plattform, bricht der
Schritt ab statt eine Lock-Datei zu erzeugen, die nur auf einem Rechner funktioniert.
Neu erzeugen mit:

```bash
tofu -chdir=<dir> providers lock \
  -platform=linux_amd64 -platform=linux_arm64 \
  -platform=darwin_arm64 -platform=windows_amd64
```

**Der Guard auf `terraform.tfvars`.** Die Datei wird committet, damit die Konfiguration
sichtbar ist — enthält aber nur Null-GUIDs. Subscription- und Tenant-ID sind keine
Credentials, identifizieren aber die Azure-Umgebung, und dieses Repo ist öffentlich. Der
Guard-Schritt bricht die CI ab, sobald dort ein echter Wert landet. Lokal überschreibt man
ohne die Datei anzufassen:

```bash
export TF_VAR_subscription_id=`az account show --query id -o tsv`
export TF_VAR_tenant_id=`az account show --query tenantId -o tsv`
export TF_VAR_deployer_principal_id=`az ad signed-in-user show --query id -o tsv`
```

---

## 5. Was noch fehlt

Ein Lauf, der durchgeht. Dazu die Branch Policy auf `main`, ohne die die CI-Pipeline keine
Pull Requests blockiert. Und damit dann der eigentliche Nachweis — ein Apply, der
`kubectl get nodes` liefert und rückstandsfrei zerstört. Bis dahin ist das Root-Modul
kohärent, aber nicht nachweislich deploybar.
