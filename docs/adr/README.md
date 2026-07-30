# Architecture Decision Records

Eine Notiz pro Entscheidung, die ein fremder Leser sonst plausibel als **Fehler** lesen würde.
Selbstverständliches steht hier nicht.

| # | Entscheidung |
|---|---|
| [0001](0001-natives-tofu-test.md) | Natives `tofu test` statt Terratest |
| [0002](0002-git-tags-statt-registry.md) | Ein Git-Tag für das ganze Repo |
| [0004](0004-oidc-workload-identity-immer-aktiv.md) | OIDC-Issuer und Workload Identity hartkodiert |
| [0005](0005-acr-ohne-admin-konto.md) | Kein ACR-Admin-Konto, kein Passwort-Output |
| [0006](0006-kubelet-identity-statt-vorab-identity.md) | SystemAssigned statt vorab erzeugter UAMI |
| [0007](0007-purge-protection-default-aus.md) | Key-Vault-Purge-Protection default aus |
| [0008](0008-mock-provider-in-ci.md) | Gemockte Tests im Gate, echter Apply getrennt |
| [0009](0009-vereinfachtes-repo-layout.md) | Kein Tooling-Beiwerk, keine Kommentare im Code |

0003 lag hier einmal und begründete, warum die Testdateien am Repo-Root liegen. Das gilt nicht
mehr — die Tests sind in die Modulverzeichnisse gewandert, damit `tofu test` ohne Flags läuft.
Die Begründung dafür steht in 0009.
