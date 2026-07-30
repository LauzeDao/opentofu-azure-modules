# Phase 7 — Politur

Diese Phase produziert kaum Terraform-Code. Sie produziert Verständlichkeit — und ist bei einem
Portfolio-Repo der Teil, der über die Wirkung entscheidet.

---

## 1. Root-`README.md`

Zielgruppe ist explizit **nicht** der Autor. Reihenfolge nach abnehmender Wichtigkeit für einen
Erstleser:

1. **Ein Satz, was das ist** — Modul-Bibliothek für Azure/AKS, mit OpenTofu, als
   Portfolio-Arbeitsprobe.
2. **Modul-Tabelle** mit Links und je einem Satz Zweck.
3. **Quickstart** — vier Kommandos bis zum `validate`. Muss ohne Azure-Account funktionieren.
4. **Consumer-Snippet** mit gepinntem `?ref=vX.Y.Z`.
5. **Was dieses Repo bewusst anders macht** — die 4–6 Entscheidungen, die es von einem generierten
   Modul-Skeleton unterscheiden, jede mit einem Satz Begründung und Link zum ADR.
6. **Test-Strategie in drei Zeilen** — mock vs. echt, und warum PR-CI nichts kostet.
7. **Repo-Layout** als Baum.
8. **Status/Nicht-im-Scope** — Ehrlichkeit über Grenzen wirkt kompetenter als Verschweigen.

Anti-Ziele: kein Badge-Teppich, keine Feature-Liste, die Selbstverständliches feiert
(„✅ uses variables!"), keine ASCII-Art-Logos.

---

## 2. ADRs

Ein ADR pro Entscheidung, die ein Reviewer sonst als Fehler lesen würde. Format kurz und fix:
**Kontext → Entscheidung → Konsequenzen → Alternativen**.

| ADR | Entscheidung |
|---|---|
| [0001](../adr/0001-natives-tofu-test.md) | Natives `tofu test` statt Terratest |
| [0002](../adr/0002-git-tags-statt-registry.md) | Repo-weite Git-Tags statt Registry oder Per-Modul-Tags |
| [0004](../adr/0004-oidc-workload-identity-immer-aktiv.md) | OIDC/Workload Identity hartkodiert, kein Feature-Flag |
| [0005](../adr/0005-acr-ohne-admin-konto.md) | Kein ACR-Admin-Konto, kein Passwort-Output |
| [0006](../adr/0006-kubelet-identity-statt-vorab-identity.md) | SystemAssigned + Kubelet-Identity statt vorab erzeugter UAMI |
| [0007](../adr/0007-purge-protection-default-aus.md) | Key-Vault-Purge-Protection default aus |
| [0008](../adr/0008-mock-provider-in-ci.md) | `mock_provider` im PR-Gate, echter Apply getrennt |

Ein ADR wird **nicht** nachträglich umgeschrieben, wenn sich die Entscheidung ändert — dann kommt
ein neues mit `Status: ersetzt ADR-000X`.

---

## 3. Konsistenz-Durchlauf

Handarbeit, die man leicht überspringt und die dann auffällt:

- Jedes Modul-README: der handgeschriebene Teil über `<!-- BEGIN_TF_DOCS -->` erklärt
      **Zweck + ein Anwendungsbeispiel + die nicht-offensichtlichen Defaults**. Der generierte Teil
      allein ist eine Tabelle ohne Aussage.
- Alle internen Links auflösbar (kein Link auf eine Datei, die nie entstanden ist).
- Terminologie einheitlich: „Modul" nicht „Component", „Consumer" nicht „User", OpenTofu nicht
      Terraform (außer wo wirklich Terraform gemeint ist).
- Kein TODO/FIXME/„tbd" mehr im committeten Stand.
- `docs/architecture.md` beschreibt den **gebauten** Zustand, nicht den geplanten — Diagramme
      gegen den echten Code prüfen.
- Alle Spec-Links zeigen auf existierende Dateien.
- Keine Platzhalter wie `<owner>` mehr in Snippets, die man kopieren soll — oder falls doch,
      dann sichtbar als Platzhalter markiert.

---

## 4. Abschluss-Verifikation

Ein Durchlauf über alles, aus einem sauberen Clone:

```bash
tofu init -backend=false && tofu validate
tofu test / tofu -chdir=modules/<name> test
tflint --init && tflint --recursive
```

Zusätzlich manuell:

- `git grep -nE 'subscription_id\s*=\s*"[0-9a-f]{8}-'` → keine Treffer (keine echte
      Subscription-ID im Repo).
- `git grep -niE '(client_secret|password)\s*=\s*"'` → keine Treffer.
- `git ls-files | grep -E '\.tfstate|\.tfvars$'` → keine Treffer.
- Ein `mermaid`-Render-Check der Diagramme (GitHub-Preview), keine Syntax-Fehler.

---

## 5. DoD

- Root-`README.md` nach §1, ohne Badge-Teppich.
- Alle acht ADRs aus §2 vorhanden und verlinkt.
- Konsistenz-Checkliste §3 abgearbeitet.
- Verifikations-Kommandos §4 alle grün, Secret-Greps leer.
- Mindestens ein Versions-Tag gesetzt (`v0.1.0`), Consumer-Snippet im README zeigt darauf.
