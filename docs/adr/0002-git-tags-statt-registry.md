# ADR 0002 — Ein Git-Tag für das ganze Repo

## Kontext

Versionierung läuft über Git-Tags, eine eigene Registry ist nicht im Scope. Offen bleibt:
ein Tag pro Repo oder ein Tag pro Modul (`aks/v1.2.0`, `networking/v0.4.1`, …)?

## Entscheidung

Ein Tag pro Repo. `v1.2.0` heißt „alle Module in dem Zustand, in dem sie bei `v1.2.0` waren":

```hcl
module "aks" {
  source = "git::https://github.com/<owner>/opentofu-azure-modules.git//modules/aks?ref=v1.2.0"
}
```

## Begründung

Die Contracts hängen voneinander ab: `modules/acr` erwartet eine
`kubelet_identity_object_id` in der Form, in der `modules/aks` sie ausgibt. Ein repo-weiter
Tag garantiert, dass ein Consumer eine zusammenpassende Kombination zieht. Bei unabhängigen
Tags kann er `aks/v2.0.0` mit `acr/v1.0.0` mischen und bekommt einen Fehler, den niemand
getestet hat — und die Menge testbarer Kombinationen wächst kombinatorisch.

Der Preis: eine Änderung nur an `modules/networking` erhöht die Version aller Module, und ein
Breaking Change in einem Modul erzwingt einen Major-Bump für alle. Bei fünf gemeinsam
entwickelten Modulen ist das verkraftbar. Bei vierzig wäre die Abwägung anders.

`?ref=main` ist in jedem Fall ausgeschlossen — damit ist kein Consumer-Apply reproduzierbar.
