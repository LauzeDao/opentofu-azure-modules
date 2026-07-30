# ADR 0008 — Gemockte Tests im schnellen Gate, echter Apply getrennt

Verwandt: [ADR 0001](0001-natives-tofu-test.md) (Wahl des Test-Frameworks).

## Kontext

ADR 0001 legt `tofu test` als Framework fest. Offen bleibt, **wann** welcher Test läuft —
insbesondere, ob der echte Apply/Destroy-Zyklus gegen Azure in der PR-Validierung stattfindet.

Randbedingungen: das Repo ist öffentlich, die Subscription privat bezahlt, ein AKS-Cluster
braucht rund 15 Minuten pro Richtung. Trotzdem verlangt die globale DoD den echten Nachweis —
`kubectl get nodes`, danach rückstandsfreier Destroy.

## Entscheidung

Zwei getrennte Pipelines unter [`../../pipelines/`](../../pipelines/):

| | `ci.yml` | `apply.yml` |
|---|---|---|
| Trigger | Push auf `main`, jeder Pull Request | nur manuell |
| Azure-Zugriff | keiner | Service Connection, Environment mit Freigabe |
| Prüft | `mock_provider`, `command = plan` | echter `apply` → `kubectl` → `destroy` |
| Laufzeit | ~2 Minuten | ~30 Minuten |
| Blockiert Merge | ja | nein |

`apply.yml` reagiert nie auf `pull_request`.

## Begründung

Der wichtigste Punkt: es gibt kein Azure-Credential, das ein fremder Pull Request erreichen
kann. Eine PR-Pipeline mit Cloud-Zugang in einem öffentlichen Repo ist eine bekannte
Rechteausweitung — der PR-Autor kontrolliert den ausgeführten Code. Nebeneffekt: kein
Kostenrisiko durch Fremd-PRs.

Dazu ist das schnelle Gate schnell genug, um wirklich benutzt zu werden. Ein
30-Minuten-Gate wird umgangen.

## Wo die Lücke bleibt

Ein Merge kann grün sein, obwohl der echte Apply bricht. Ein Provider-Bug, eine
zurückgezogene Kubernetes-Version, eine in der Region nicht verfügbare VM-Größe: nichts davon
sieht das schnelle Gate. Gegenmaßnahme ist Disziplin, nicht Technik — der Apply-Lauf gehört vor
jeden Versions-Tag, weil ein Tag mit ungeprüftem Apply einem Consumer eine kaputte
Modulversion liefert, die er nicht zurücknehmen kann.

„Alle Tests grün" heißt hier ausdrücklich nicht „funktioniert in Azure". Das steht deshalb auch
in [`../architecture.md` §6](../architecture.md#6-test-strategie-mock-vs-echt) und im README.

## Absicherung gegen verwaiste Ressourcen

Weil der Apply-Lauf eben *nicht* bei jedem Push läuft, bleibt ein Fehlschlag länger unbemerkt.
Vier Vorgaben an die Pipeline:

- `destroy` unter `condition: always()` — nach einem auf halber Strecke gescheiterten `apply`
  existieren schon Ressourcen. Deckt auch den Abbruch durch den Benutzer ab.
- Keine parallelen Läufe auf demselben State-Key.
- Eigener State-Key pro Lauf, damit ein hängender Blob-Lease den nächsten nicht blockiert.
- Abschluss-Check auf `az group list` und `az keyvault list-deleted`. Ein Destroy, der
  „erfolgreich" meldet und einen soft-deleted Vault hinterlässt, ist nicht rückstandsfrei.

## Verworfene Alternativen

**Echter Apply im PR-Gate, nur für PRs aus demselben Repo.** Technisch machbar, schützt aber
nicht gegen einen kompromittierten Branch, kostet bei jedem eigenen Push Geld, und die
Bedingung ist eine einzeilige Fehlerquelle mit hohem Schadenspotenzial.

**Nightly statt manuell.** Nicht grundsätzlich verworfen, aber nicht standardmäßig aktiv: ein
nächtlicher AKS-Cluster kostet auch dann, wenn gerade niemand am Repo arbeitet.
