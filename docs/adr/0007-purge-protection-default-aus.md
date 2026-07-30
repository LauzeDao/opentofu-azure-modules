# ADR 0007 — Key-Vault-Purge-Protection default aus

## Kontext

Azure Key Vault kennt zwei Löschschutz-Ebenen:

- **Soft Delete** — nicht abschaltbar. Ein gelöschter Vault bleibt 7–90 Tage wiederherstellbar, und
  **sein Name bleibt in dieser Zeit belegt**.
- **Purge Protection** (`purge_protection_enabled`) — verhindert zusätzlich das endgültige Löschen
  (`az keyvault purge`) vor Ablauf der Retention. **Einmal eingeschaltet, kann sie nicht mehr
  abgeschaltet werden** — auch nicht per Support-Ticket.

Jede Security-Baseline empfiehlt `purge_protection_enabled = true`. Checkov, Azure Policy und das
Microsoft Cloud Security Benchmark sind sich da einig.

Gleichzeitig gilt für dieses Repo: jeder Testlauf hat ein sauberes `destroy`, und es
hinterlässt keine verwaisten Azure-Ressourcen (Kosten!)."

## Entscheidung

`purge_protection_enabled` ist eine Variable mit Default **`false`**.

`soft_delete_retention_days` hat Default **`7`** — das Minimum, also der kürzeste Zeitraum, in dem ein
Name blockiert bleibt.

Das Beispiel-Root setzt zusätzlich im Provider:

```hcl
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
```

Das README des Moduls sagt in einem hervorgehobenen Block: **für Produktion einschalten**.

## Konsequenzen

- Der Apply/Destroy-Zyklus ist tatsächlich wiederholbar. Mit Purge Protection wäre der zweite
  CI-Lauf mit „vault name already in use" gescheitert — und zwar 7 Tage lang, ohne
  Umgehungsmöglichkeit. Das würde §7 und die globale DoD (§9: „lässt sich rückstandsfrei wieder
  zerstören") unmöglich machen.
- `purge_soft_delete_on_destroy = true` sorgt dafür, dass `tofu destroy` den Vault wirklich entfernt
  und nicht nur soft-deleted. Der Rückstands-Check in der Apply-Pipeline
  (`az keyvault list-deleted`) prüft genau das.
- Die Entscheidung ist umkehrbar: ein Consumer setzt `purge_protection_enabled = true` und hat den
  Produktionsschutz. Der umgekehrte Weg — Default `true` und ein Consumer will es aus — existiert
  nicht, weil der Schalter irreversibel ist.

Was dabei in Kauf genommen wird:

- Der Default ist **nicht** die sichere Variante. Ein Vault ohne Purge Protection kann von jemandem
  mit `Contributor` endgültig gelöscht werden, inklusive aller Secrets und Zertifikate.
- Wer das Modul unbesehen für Produktion übernimmt, bekommt eine schwächere Konfiguration als von
  jeder Baseline empfohlen. Gegenmaßnahmen: ein hervorgehobener Hinweis im Modul-README, die
  Nennung hier, und ein Kommentar an der Variable selbst.
- `soft_delete_retention_days = 7` ist ebenfalls das Minimum statt eines Kompromisses. Für
  Produktion sind 90 Tage die sinnvolle Wahl.

Das ist der einzige Ort im Repo, an dem ein Default bewusst gegen die Security-Baseline entschieden
wurde. Genau deshalb steht er in einem ADR und nicht in einem Kommentar.

## Verworfene Alternativen

**Default `true`.** Sicher, aber macht die Kern-DoD dieses Repos unerreichbar. Ein Repo, dessen
Beispiel-Root nach dem ersten CI-Lauf 7 Tage lang nicht mehr deployt werden kann, demonstriert
nichts.

**Default `true` und pro CI-Lauf ein zufälliger Vault-Name.** Löst die Namenskollision und behält den
sicheren Default. Verworfen, weil es die Namenskonvention aus §4 (`<project>-<env>-<resource>`)
aufweicht und weil die Vaults dann *tatsächlich* nicht mehr löschbar wären — sie würden sich in der
Subscription ansammeln, bis die Retention abläuft. Das verletzt §7 („keine verwaisten Ressourcen")
noch deutlicher.

**Ein zweites Root-Modul mit `purge_protection_enabled = true`.** Wäre die
didaktisch beste Lösung, sprengt aber den Scope: das Repo hat genau ein Root-Modul.
Denkbar für eine spätere Version.
