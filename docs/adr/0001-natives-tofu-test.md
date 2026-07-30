# ADR 0001 — Natives `tofu test` statt Terratest

## Kontext

Jedes Modul soll einen automatisierten Test haben. Zur Wahl standen Terratest (Go, ruft
`apply` gegen echte Cloud-Ressourcen), das eingebaute `tofu test` mit `*.tftest.hcl`, oder
nur `validate` — was kein Test ist, sondern ein Syntaxcheck.

Randbedingung: hinter dem Repo steht eine privat bezahlte Azure-Subscription, und ein
AKS-Cluster braucht rund eine Viertelstunde pro `apply`.

## Entscheidung

Natives `tofu test` mit `mock_provider "azurerm"` für alle Modultests. Kein Go, keine zweite
Sprache im Repo. Der echte Apply/Destroy-Zyklus läuft separat und manuell, siehe
[ADR 0008](0008-mock-provider-in-ci.md).

## Konsequenzen

Die Tests brauchen keine Azure-Credentials und kosten nichts. Bei einem öffentlichen Repo ist
das auch ein Sicherheitsgewinn: es gibt kein Cloud-Credential, das ein fremder Pull Request
erreichen könnte. Und weil ein Lauf Sekunden statt Minuten dauert, wird er tatsächlich
ausgeführt statt umgangen.

`expect_failures` macht die `validation`-Blocks negativ prüfbar. Das ist der Teil des
Contracts, der sonst nie getestet wird — von 168 Testfällen dienen 91 genau dazu.

Was dabei fehlt: `mock_provider` prüft Konfigurationslogik, nicht Cloud-Realität. Ob Azure
eine Kombination aus Region, VM-Größe und Kubernetes-Version akzeptiert, sagt kein Mock. Es
gibt außerdem keine Assertions gegen laufende Infrastruktur — das übernimmt im Apply-Lauf ein
schlichtes `kubectl get nodes`.

## Warum nicht Terratest

Der einzige echte Vorteil wären Assertions gegen laufende Infrastruktur. Der Preis: eine
Go-Toolchain im Repo, Azure-Credentials in der PR-Validierung (oder ein Test-Gate, das nie
läuft), plus Kosten und Wartezeit bei jedem Lauf. Für fünf Module mit überwiegend
deklarativer Logik stimmt das Verhältnis nicht. Bei nicht-trivialer Laufzeitlogik —
Provisioner, externe Datenquellen — würde ich anders entscheiden.
