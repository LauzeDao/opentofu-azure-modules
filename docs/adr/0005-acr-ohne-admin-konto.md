# ADR 0005 — Kein ACR-Admin-Konto, keine Passwort-Outputs

## Kontext

`azurerm_container_registry` hat ein `admin_enabled`-Flag. Ist es gesetzt, exportiert die
Ressource `admin_username` und `admin_password` — ein statisches Benutzer/Passwort-Paar mit
Push- und Pull-Rechten auf die gesamte Registry. Das ist der bequemste Weg, einen Cluster oder
eine Pipeline an eine Registry zu hängen, und entsprechend häufig in Beispielen zu finden.

## Entscheidung

`admin_enabled` bleibt eine Variable mit Default `false`. `admin_username` und
`admin_password` werden **nicht** als Modul-Output exponiert — auch nicht `sensitive`. Zugriff
läuft über Role Assignments (`AcrPull`, `AcrPush`) auf Managed Identities.

Das Flag bleibt absichtlich vorhanden: es gibt Werkzeuge, die nur Basic Auth sprechen. Wer es
einschaltet, bekommt das Konto — aber die Credentials nicht durch den Modul-Contract.

## Konsequenzen

Kein geteiltes Passwort. Das Admin-Konto ist *ein* Credential für alle Nutzer: nicht
zurückverfolgbar, nicht einzeln entziehbar, nicht rotierbar ohne alle Consumer zu brechen.

Nichts Geheimes im State. Ein exponierter `admin_password`-Output landet im OpenTofu-State und
potenziell in Pipeline-Logs. Was nicht im Contract steht, kann nicht auslaufen.

AKS braucht das Konto ohnehin nicht — das `AcrPull`-Assignment auf die Kubelet-Identität ist
der vorgesehene Weg und funktioniert ohne jedes Secret im Cluster. Und Least Privilege wird
damit überhaupt erst möglich: `AcrPull` für Nodes, `AcrPush` nur für die Pipeline-Identität.
Mit dem Admin-Konto hat jeder beides.

Unbequemer wird ein lokaler Login: `az acr login --name <registry>` statt Benutzer/Passwort,
also mit Azure-CLI-Session.

## Verworfene Alternativen

**`admin_enabled` hartkodiert `false`** — konsequenter, und analog zu
[ADR 0004](0004-oidc-workload-identity-immer-aktiv.md) vertretbar. Verworfen, weil das
eigentliche Risiko nicht das Flag ist, sondern das Herausreichen der Credentials. Genau das
verhindert die fehlende Output-Definition.

**Outputs als `sensitive = true`** — `sensitive` verhindert die Anzeige im CLI-Output, nicht
die Speicherung im State und nicht die Weitergabe durch einen Consumer, der den Wert in eine
unmarkierte Ressource schreibt. Es ist eine Anzeige-Eigenschaft, kein Schutzmechanismus.
