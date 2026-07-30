# ADR 0004 — OIDC-Issuer und Workload Identity hartkodiert, kein Feature-Flag

## Kontext

`azurerm_kubernetes_cluster` kennt zwei Schalter:

```hcl
oidc_issuer_enabled       = true|false   # default false
workload_identity_enabled = true|false   # default false
```

Beide sind Voraussetzung für Azure Workload Identity — das Verfahren, mit dem ein Pod sich über
einen federierten ServiceAccount-Token gegen Entra ID authentisiert, **ohne** ein Secret im Cluster.

Die reflexhafte Modul-Design-Entscheidung wäre, beide als Variablen mit Default `true` zu exponieren.
Die Vorgabe für dieses Repo ist eindeutig: OIDC-Issuer und Workload Identity **immer aktiv**, kein
optionales Feature-Flag)".

## Entscheidung

Beide Werte stehen **hartkodiert** auf `true` in `modules/aks/main.tf`. Es gibt keine
Modul-Variable, mit der ein Consumer sie abschalten könnte.

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  # Bewusst NICHT als Variable exponiert — ADR 0004.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  # ...
}
```

Ein Test in [`modules/aks/tests/`](../../modules/aks/tests/) nagelt das fest: er prüft bei minimaler
Consumer-Konfiguration, dass beide Werte `true` sind. Wer das Flag später „nur mal kurz"
konfigurierbar macht, bekommt einen roten Test.

## Konsequenzen

- Die sichere Variante ist die einzige Variante. Ein Flag, das auf `false` gestellt werden *kann*,
  wird irgendwann auf `false` gestellt — typischerweise unter Zeitdruck, mit der Begründung „geht
  erstmal auch mit einem Secret". Danach hat man langlebige Client-Secrets im Cluster, was §5
  („keine Client-Secrets für Identitäten") direkt verletzt.
- Der `oidc_issuer_url`-Output ist damit **immer** verfügbar. Consumer müssen nicht defensiv prüfen,
  ob der Cluster OIDC überhaupt kann.
- Weniger Contract-Oberfläche: zwei Variablen weniger, über die niemand nachdenken muss.

Was dabei in Kauf genommen wird:

- Das Modul kann keinen Cluster ohne OIDC-Issuer bauen. Wer das braucht (z. B. um exakt eine
  bestehende Legacy-Konfiguration zu reproduzieren), kann dieses Modul nicht verwenden.
- Das Aktivieren von `oidc_issuer_enabled` auf einem **bestehenden** Cluster ist bei Azure eine
  Änderung, die den Control Plane neu konfiguriert. Für Neuanlagen — der Fall dieses Moduls —
  irrelevant.
- Marginale Kosten: der OIDC-Issuer-Endpoint selbst ist kostenlos, aber ein Cluster mit
  Workload Identity Webhook hat zwei zusätzliche System-Pods. Bei `Standard_B2s`-Nodes messbar,
  aber vertretbar.

## Verworfene Alternativen

**Variablen mit Default `true`.** Der naheliegende Kompromiss. Verworfen, weil er den eigentlichen
Zweck nicht erfüllt: die Möglichkeit zum Abschalten ist genau das Risiko, das §5 ausschließen will.
Ein Default ist eine Empfehlung, eine Hartkodierung ist eine Garantie.

**Nur `oidc_issuer_enabled` hartkodieren, `workload_identity_enabled` als Variable.** Inkonsistent —
der OIDC-Issuer ohne Workload-Identity-Webhook nützt niemandem, das ist keine sinnvolle Kombination.

**`local_account_disabled = true` ebenfalls hartkodieren.** Naheliegend („nur Entra-Auth"), aber
verworfen: ohne `admin_group_object_ids` sperrt man sich damit komplett aus dem Cluster aus, und der
CI-Apply-Test käme nicht mehr an `kubectl`. Bleibt als Variable mit Default `false` und einem
entsprechenden Hinweis im README.
