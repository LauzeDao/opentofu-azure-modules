# ADR 0006 — SystemAssigned + Kubelet-Identity statt vorab erzeugter UAMI

## Kontext

`modules/acr` und `modules/key-vault` brauchen die **Object-ID der Kubelet-Identität**, um ihr
`AcrPull` bzw. `Key Vault Secrets User` zuzuweisen. Diese Identität entsteht aber erst, wenn AKS
angelegt wird — daraus ergibt sich die Reihenfolge
`resource_group → networking → aks → {acr, key_vault}`.

Das wirkt zunächst falsch: ACR und Key Vault fühlen sich wie „Basis-Infrastruktur" an, die *vor* dem
Cluster stehen sollte. Die verbreitete Alternative ist, die Identitäten vorab zu erzeugen:

```hcl
resource "azurerm_user_assigned_identity" "kubelet" { /* ... */ }

resource "azurerm_kubernetes_cluster" "main" {
  identity { type = "UserAssigned", identity_ids = [azurerm_user_assigned_identity.cp.id] }
  kubelet_identity {
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
  }
}
```

## Entscheidung

Default ist **`identity { type = "SystemAssigned" }`** ohne vorab erzeugte Identitäten. Die
Kubelet-Identität wird von Azure angelegt und über
`azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id` als Modul-Output
`kubelet_identity_object_id` herausgereicht.

`identity_type` und `identity_ids` bleiben als Variablen erhalten, sodass ein Consumer auf
`UserAssigned` umstellen kann — der `kubelet_identity`-Block wird vom Modul aber nicht gesetzt.

## Konsequenzen

- Deutlich weniger Ressourcen und weniger Contract. Kein zusätzliches Modul für Identitäten, keine
  vier extra Variablen, keine Role Assignments nur damit AKS seine eigene Identität nutzen darf.
- Azure verwaltet den Lebenszyklus. Die Identität verschwindet mit dem Cluster — passend zu §7
  („rückstandsfrei zerstörbar"). Vorab erzeugte UAMIs überleben ein `destroy` des Clusters, wenn sie
  in einem anderen Modul liegen, und sammeln sich still an.
- Die Abhängigkeitsrichtung ist ehrlich sichtbar: `aks → acr` steht so im
  [Abhängigkeitsgraph](../architecture.md#1-modul-abhängigkeitsgraph) und ist damit erklärt statt
  versteckt.

Was dabei in Kauf genommen wird:

- **Der Cluster kann nicht gleichzeitig mit einem ACR angelegt werden, das ihn bereits kennt.** Für
  einen Erst-Apply heißt das: der Cluster existiert einige Minuten, bevor sein AcrPull greift. Bei
  einem leeren Cluster ohne Workloads irrelevant.
- Wer die Kubelet-Identität **vor** dem Cluster braucht — etwa um ein Role Assignment in einer
  fremden Subscription vorzubereiten, für das ein anderes Team zuständig ist — kann das mit dem
  Default nicht. Dafür ist die `UserAssigned`-Variante vorgesehen; das vorab erzeugte UAMI liegt dann
  im Consumer, nicht in diesem Repo.
- Ein `destroy`/`apply` des Clusters erzeugt eine **neue** Kubelet-Identität. Die Role Assignments in
  `acr`/`key_vault` werden dadurch mit-ersetzt — sichtbar im Plan, korrekt, aber ein Reviewer muss
  wissen, warum plötzlich Role Assignments im Diff stehen.

## Verworfene Alternativen

**Vorab erzeugte UAMI für Control Plane und Kubelet (siehe Kontext).** Der „saubere" Weg vieler
Enterprise-Setups, und für Multi-Subscription- oder Multi-Team-Szenarien tatsächlich besser. Preis:
ein weiteres Modul, mindestens zwei zusätzliche Ressourcen plus ein `Managed Identity Operator`- und
ein `Virtual Machine Contributor`-Assignment (AKS braucht die, um eine fremde Kubelet-Identität
überhaupt verwenden zu dürfen) — und ein Lebenszyklus, der nicht mehr am Cluster hängt. Für den
Umfang dieses Repos ist das mehr Komplexität als Erkenntnis.

**`data "azurerm_user_assigned_identity"`-Lookup nach dem Cluster-Apply.** Zwei-Phasen-Apply, damit
grundsätzlich abzulehnen: ein Root-Modul, das nur mit `-target` oder in zwei Läufen funktioniert, ist
kein „echtes, deploybares Root-Modul" im Sinne von §1.6.
