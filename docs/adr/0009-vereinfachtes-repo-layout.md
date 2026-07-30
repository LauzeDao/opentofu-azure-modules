# ADR 0009 — Kein Tooling-Beiwerk, keine Kommentare im Code

## Kontext

Die erste Fassung dieses Repos folgte den üblichen Empfehlungen für eine Modul-Bibliothek und
brachte damit eine ganze Werkzeugkette mit: `versions.tf` je Modul, generierte READMEs per
`terraform-docs`, Wrapper-Skripte unter `scripts/`, `checkov` mit begründeter Ausnahmeliste,
`pre-commit`-Hooks, `.gitattributes`. Dazu ein separates `examples/aks-cluster` als Root-Modul
und Testdateien am Repo-Root unter `tests/<modul>/`.

Jede einzelne dieser Entscheidungen ist verteidigbar. Zusammen bedeuteten sie: neun
Konfigurationsdateien und vier externe Werkzeuge, die man installieren und verstehen muss,
bevor man fünf Module lesen kann. Bei einem Repo, dessen Aussage „sauberes Modul-Design" ist,
konkurriert dieses Beiwerk mit der eigentlichen Aussage.

## Entscheidung

| Weg | Ersatz |
|---|---|
| `modules/*/versions.tf` | `required_providers` und `required_version` nur in `provider.tf` |
| `examples/aks-cluster/` | Root-Modul im Repo-Wurzelverzeichnis |
| `tests/<modul>/` am Root | `modules/<modul>/tests/` — `tofu test` läuft dadurch ohne Flags |
| `scripts/` | direkte `tofu`-Aufrufe, siehe [CONTRIBUTING.md](../../CONTRIBUTING.md) |
| `terraform-docs` + generierte README-Blöcke | handgeschriebene READMEs, Contract in den `description`-Feldern |
| `checkov`, `pre-commit`, `.gitattributes` | entfallen |
| Kommentare in `.tf`-Dateien | `description`-Felder, Modul-READMEs, `docs/` |

`.tflint.hcl` bleibt, mit deaktivierten `terraform_required_providers`,
`terraform_required_version` und `terraform_standard_module_structure` — diese drei Regeln
setzen ein `versions.tf` je Modul voraus.

## Konsequenzen

Ein Leser braucht `tofu` und nichts weiter. Genau drei `.tf`-Dateien je Modul, die Struktur ist
auf einen Blick erfassbar. `tofu test` läuft ohne `-test-directory`-Pfadakrobatik — das war der
einzige echte Grund, aus dem die Wrapper-Skripte existierten. Und kommentarfreier Code erzwingt,
dass Erklärungen an einen auffindbaren Ort wandern statt an der Stelle zu verrotten, an der sie
geschrieben wurden.

Was das kostet:

- **Die README-Tabellen können veralten.** Genau davor schützte `terraform-docs`. Deshalb sind
  sie entfernt statt eingefroren; verbindlich sind die `description`-Felder, und die veralten
  nicht, weil sie im Code stehen.
- **Kein automatischer Security-Scan.** Der letzte Checkov-Lauf war grün, aber künftige
  Regressionen fallen nicht auf. Die inhaltlichen Entscheidungen dahinter stehen weiterhin in
  ADR 0005 und ADR 0007.
- **Kein Gate vor dem Commit.** `tofu fmt` und die Tests laufen manuell, bis die Pipeline greift.
- **Ein einzeln getestetes Modul hat keinen `required_version`-Constraint.** Die Module nutzen
  Cross-Variable-`validation`, das OpenTofu ≥ 1.9 braucht; auf einer älteren Version gibt es
  eine unklare Fehlermeldung. Die Provider-Version bleibt dagegen über die committeten
  `.terraform.lock.hcl` gepinnt.
- **`terraform.tfvars` wird committet.** Widerspricht der verbreiteten Regel, tfvars niemals
  einzuchecken. Vertretbar nur, weil die Datei ausschließlich Platzhalter enthält — die
  CI-Pipeline bricht ab, sobald dort ein echter Wert landet.

Der Vollständigkeit halber: die Tests lagen vorher am Repo-Root, damit ein Consumer bei
`?ref=…//modules/aks` keine Testdateien mitzieht. Das passiert nun. Es sind wenige Kilobyte
HCL, die nie ausgeführt werden — der Preis für „`tofu test` ohne Flags" ist es wert.

## Verworfene Alternativen

**Nur die Kommentare entfernen.** Hätte die Werkzeugkette intakt gelassen und am eigentlichen
Problem nichts geändert — die Einstiegshürde liegt nicht bei den Kommentaren.

**`terraform-docs` behalten, alles andere streichen.** Der stärkste Einzelkandidat, weil
generierte Tabellen echten Nutzen haben. Verworfen, weil es ein weiteres Pflicht-Werkzeug plus
Marker-Blöcke in jedem README bedeutet — und ein `description`-Feld trägt dieselbe Information
ohne Generierungsschritt.
