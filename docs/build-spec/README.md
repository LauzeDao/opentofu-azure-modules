# Build-Specs

Ein Arbeitspaket pro Bau-Phase. Jede Spec ist für sich lesbar — man muss die anderen nicht
gelesen haben.

| Spec | Phase | Liefert |
|---|---|---|
| — | 1 | Doku & Kontext: [`architecture.md`](../architecture.md), diese Specs, ADRs, Tooling-Configs |
| [`02-base-modules.md`](02-base-modules.md) | 2 | `modules/resource-group`, `modules/networking` |
| [`03-aks-module.md`](03-aks-module.md) | 3 | `modules/aks` — das Kernstück |
| [`04-acr-keyvault.md`](04-acr-keyvault.md) | 4 | `modules/acr`, `modules/key-vault` |
| [`05-example-root.md`](05-example-root.md) | 5 | das Root-Modul |
| [`06-tests-ci.md`](06-tests-ci.md) | 6 | die Testdateien und das CI-Gate |
| [`07-polish.md`](07-polish.md) | 7 | README, ADRs, Konsistenz-Durchlauf |

## Aufbau jeder Spec

1. **Ziel** — ein Satz.
2. **Contract** — Inputs/Outputs tabellarisch, *bevor* Code entsteht (Contract-first, §2).
3. **Entscheidungen** — was bewusst so und nicht anders gebaut wird, mit Begründung.
4. **DoD** — abhakbar, jeder Punkt maschinell oder per Kommando prüfbar.

## Konventionen für alle Phasen

- Kein Modul ohne mindestens einen `tofu test` und ein generiertes README (§9).
- `variables.tf`: getypt, `description` immer, `validation` wo eine falsche Eingabe erst spät
  (beim `apply`) auffallen würde.
- Alle Unit-Tests laufen mit `mock_provider "azurerm"` — keine Credentials, keine Kosten.
- Verifikation nach jeder Phase:
  ```bash
  tofu init -backend=false && tofu validate && tofu test / tofu -chdir=modules/<name> test && tflint --recursive
  ```
