# Konventionen

Was in diesem Repo gilt, wenn ein Modul dazukommt oder sich eines ändert. Der Überblick über
das Projekt steht im [README](README.md), die Diagramme in
[`docs/architecture.md`](docs/architecture.md), die Entscheidungen in
[`docs/adr/`](docs/adr/).

## Leitlinien

**Ein Modul, ein Zweck.** Netzwerk, AKS, Registry, Secrets — jedes mit klarem In-/Output-Contract.
Keine Module, die alles können.

**Contract vor Implementierung.** `variables.tf` mit Typen und `validation`-Blocks entsteht vor
`main.tf`. Jede Variable und jeder Output trägt eine `description`; das *ist* die Dokumentation
des Contracts.

**Getestet, nicht nur validiert.** Kein Modul ohne mindestens eine Testdatei. Jede
`validation`-Regel braucht einen Negativtest — eine Regel, die nie negativ geprüft wurde, gibt
keine Garantie, weil ein Tippfehler in der `condition` nie auffällt.

**Keine Kommentare in `.tf`-Dateien.** Erklärungen gehören in `description`-Felder, in die
Modul-READMEs oder nach `docs/`. Ein Kommentar an der Codestelle verrottet dort, wo ihn niemand
sucht. Siehe [ADR 0009](docs/adr/0009-vereinfachtes-repo-layout.md).

**Lesbarkeit vor Cleverness.** Kein `count`/`for_each`-Wildwuchs, keine ungeprüften
`dynamic`-Blöcke.

**Sprache richtet sich nach der Zielgruppe.** Was ein *Nutzer* der Bibliothek liest, ist
englisch: [README](README.md), Modul-READMEs, alle `description`-Felder, alle
Test-Fehlermeldungen. Was ein *Maintainer* liest, ist deutsch: diese Datei,
[`docs/architecture.md`](docs/architecture.md), [`docs/deployment.md`](docs/deployment.md),
[`docs/pipeline.md`](docs/pipeline.md) und die ADRs. Eine neue Datei folgt der Linie ihrer
Zielgruppe, nicht der des Nachbarverzeichnisses.

## Modul-Contract

Genau drei `.tf`-Dateien plus README und Tests:

```
modules/<name>/
├─ main.tf
├─ variables.tf
├─ outputs.tf
├─ README.md
└─ tests/*.tftest.hcl
```

Kein `versions.tf` — `required_providers` und `required_version` stehen ausschließlich in
[`provider.tf`](provider.tf) am Root. Die committeten `.terraform.lock.hcl` halten die
Provider-Version fest, auch wenn ein Modul einzeln getestet wird.

- **Kein `provider`-Block im Modul.** Provider-Konfiguration ist Sache des Root-Moduls.
- **Variablen** getypt, mit `validation` überall, wo eine falsche Eingabe sonst erst beim
  `apply` auffällt. Sinnvolle Defaults, aber keine versteckte Magie.
- **Outputs** für alles, was ein Consumer realistisch braucht: IDs, Namen, Principal-IDs,
  bei `aks` die kubeconfig-relevanten Werte. Alles Geheime `sensitive = true`.
- **Kollektionen als Map, nicht als Liste.** Bei einer Liste verschiebt ein Einfügen alle
  weiteren Indizes und OpenTofu will jede nachfolgende Ressource ersetzen. Stabile String-Keys
  machen `for_each` idempotent.
- **Namen werden nicht im Modul gebaut.** Das Schema `<resource>-<project>-<env>` lebt in den
  Locals von [`main.tf`](main.tf). Zwei Azure-Dienste brechen die Konvention — Registries
  erlauben keine Bindestriche, Vaults enden bei 24 Zeichen — und das wird dort sichtbar
  korrigiert, wo Naming hingehört.

## Guardrails

- **State:** Azure Storage mit RBAC statt Storage-Account-Keys. Kein State im Repo,
  `backend.tf` ist gitignored.
- **AKS:** OIDC-Issuer und Workload Identity sind hartkodiert aktiv, kein Feature-Flag
  ([ADR 0004](docs/adr/0004-oidc-workload-identity-immer-aktiv.md)). Keine
  `service_principal`-Blöcke, keine Client-Secrets für Identitäten.
- **Keine Secrets, keine echten Bezeichner.** `terraform.tfvars` wird committet, enthält aber
  nur Platzhalter. Subscription- und Tenant-ID sind keine Credentials, identifizieren aber die
  Umgebung — und das Repo ist öffentlich. Lokal per `TF_VAR_*` überschreiben; die CI-Pipeline
  bricht ab, wenn dort ein echter Wert landet.
- **Kosten:** kleinste sinnvolle SKUs als Default, damit ein Testlauf günstig bleibt.
- **Aufräumbar:** jeder Testlauf muss sich rückstandsfrei zerstören lassen. Keine verwaisten
  Resource Groups, keine soft-deleted Key Vaults.

## Ein Modul hinzufügen

1. Verzeichnis unter `modules/<name>/` anlegen, die vier Dateien plus `tests/`.
2. `variables.tf` zuerst schreiben, mit `description` und `validation`.
3. Positiv- und Negativtests unter `modules/<name>/tests/`. Alle Tests nutzen
   `mock_provider "azurerm"`, brauchen also keinen Azure-Zugang.
4. README mit Zweck, einem Anwendungsbeispiel und den nicht offensichtlichen Defaults.
5. Falls das Modul im Root-Modul komponiert wird: Verdrahtung in `main.tf` und einen
   Kompositionstest unter `tests/`.
6. Die Kommandos unten durchlaufen lassen.

Weicht etwas von diesen Konventionen ab, gehört die Begründung als ADR nach
[`docs/adr/`](docs/adr/) — nicht in einen Kommentar.

## Kommandos

```bash
tofu fmt -recursive
tofu fmt -check -recursive

tofu init -backend=false && tofu validate
tofu test                                   # Kompositionstests des Root-Moduls

tofu -chdir=modules/aks init -backend=false
tofu -chdir=modules/aks test                # Tests eines Moduls, ohne Flags

tflint --init
tflint --recursive --config="$PWD/.tflint.hcl"
```

Der `--config`-Pfad ist nicht optional: bei `--recursive` wechselt tflint in jedes
Unterverzeichnis und sucht dort eine eigene `.tflint.hcl`. Ohne absoluten Pfad greift die
Root-Config in `modules/*` nicht, und `terraform_required_providers` sowie
`terraform_required_version` melden zehn Falschtreffer — sie erwarten ein `versions.tf` je
Modul, das es hier nicht gibt.

Alle Tests laufen gegen `mock_provider "azurerm"`: kein Azure-Zugang, keine Kosten. Sie prüfen
Konfigurationslogik, nicht ob Azure die Konfiguration akzeptiert. Der echte Nachweis läuft über
[`pipelines/apply.yml`](pipelines/apply.yml), siehe [`docs/deployment.md`](docs/deployment.md).

## Versionierung

Ein Git-Tag `vX.Y.Z` gilt für das ganze Repo, nicht pro Modul
([ADR 0002](docs/adr/0002-git-tags-statt-registry.md)). Vor jedem Tag sollte die Apply-Pipeline
einmal grün durchgelaufen sein — ein Tag mit ungeprüftem Apply liefert einem Consumer eine
Modulversion, die er nicht zurücknehmen kann.
