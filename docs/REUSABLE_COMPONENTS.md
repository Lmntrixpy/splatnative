# REUSABLE_COMPONENTS

Legende: **Ü** = unverändert übernehmen · **A** = anpassen · **N** = neu entwickeln

| Komponente | Quelle | Status | Begründung |
|---|---|---|---|
| NCA/BKTR/PFS0/RomFS/NSO | Mush8 `nxfs` | **Ü** | spielunabhängig, als Path-Dependency eingebunden |
| XCI/HFS0 | – | **N** (erledigt) | `crates/s3fs`; Mush8 kann nur NSP |
| Binary-Rewriter (x18/svc/sysreg/spin) | Mush8 `nxpatch` | **Ü** | generisch; MK8-Tabellen per Module-ID inaktiv |
| Rewriter-Äquivalenzprüfung | Mush8 `nxpatch verify` | **Ü** | auf Splatoon-Module anwenden |
| IPS32-Patches (Nextendo) | Mush8 `nxpatch --patch` | **Ü** | Prelude-IPS sind IPS32 mit Build-ID → direkt nutzbar |
| Kernel/SVC/Threads/Sync | Mush8 `nxhost/kernel.rs, svc.rs` | **Ü/A** | generisch; Lücken zeigen sich erst beim Start |
| Speicherlayout | Mush8 `nxhost/mem.rs` | **A** | Splatoon 3 braucht mehr Heap (4-GB-Titel) |
| Loader | Mush8 `nxhost/loader.rs` | **A** | Modulliste hardcodiert `main,subsdk0,sdk` |
| iOS-Code-Embedding | Mush8 `nxhost/build.rs` | **A** | Modulliste + Segmentanzahl generalisieren |
| HIPC/CMIF-IPC | Mush8 `ipc.rs` | **Ü** | |
| fsp-srv, hid, time, set, acc, vi, appletOE, audren, nifm, bsd | Mush8 `services/` | **Ü/A** | Spiel-ID/Savedata-Pfade generalisieren |
| fehlende Dienste (bcat, olsc, ns, pdm, ldn, …) | – | **N** | erst nach `s3tool analyze` festlegen |
| NVN→Metal | Mush8 `nvn/`, `gfx/` | **Ü/A** | ≈133 Procs; fehlende messen (`s3tool analyze`) |
| Maxwell→MSL | Mush8 `nxshader` | **Ü/A** | ISA-generisch; Coverage für Splatoon-Shader erweitern |
| Pipeline-Liste | Mush8 `data/pipelines.tsv` | **N** | MK8-spezifisch; für Splatoon auf dem Mac aufzeichnen |
| Audio-DSP | Mush8 `audio/` | **Ü** | |
| Input/Motion/Haptics | Mush8 | **Ü** | Gyro ist für Splatoon wichtig, ist vorhanden |
| Video (Movies) | Mush8 `movie/` (WebM/VP8, MP4) | **?** | Splatoon-Formate prüfen |
| MK8-Patches, Menüs, Mii-, Ghost-, Flaggen-Code | Mush8 | **nicht** übernehmen | spielspezifisch |
| Launcher (SwiftUI) | Mush8 `ios/`, `launcher/` | **A** | MK8-Texte/Mod-Browser entfernen |
| Nextendo DNS-Umleitung, OAuth-Login, Token in Keychain | Mush8 `nextendo.rs`, `Nextendo.swift` | **A** | Host-Regeln für NPLN erweitern (inkl. TCP 7575) |
| NEX/PRUDP (MK8 online) | Mush8 `nextrace.rs`, `vnet` | **nicht** | Splatoon 3 nutzt NPLN |
| NPLN-Hosts, S3-Zertifikatspatches | Prelude | **Ü** (zur Laufzeit lesen) | PolyForm Shield: nicht ins Repo kopieren, aus Nutzer-Checkout/Katalog laden |

## Einbindungsstrategie

- Mush8 liegt als Git-Submodul unverändert unter `third_party/mush8` (Commit `89dc804`).
- Eigene Crates hängen per Path-Dependency an `nxfs`/`nxabi`.
- `nxhost` ist ein Binary-Crate mit MK8-Annahmen. Notwendige Änderungen werden
  als nachvollziehbare Patch-Serie in `patches/mush8/NNNN-*.patch` geführt,
  jeweils mit Begründung im Header, und per `Tools/apply-mush8-patches.sh`
  auf einen Arbeitszweig angewendet. Das Upstream-Checkout bleibt sauber.
- Lizenz: SplatNative ist durch die Mush8-Ableitung **GPL-3.0**.
