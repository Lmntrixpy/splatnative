# RESEARCH – Quellcode-Analyse (Stand 2026-11-22)

Alle Aussagen hier sind am Quellcode verifiziert, nicht aus READMEs übernommen.
Geprüfte Stände:

| Projekt | Commit | Lizenz |
|---|---|---|
| Mush8 (`third_party/mush8`) | `89dc804` | GPL-3.0 |
| Prelude-Nextendo (`third_party/Prelude-Nextendo`) | `c406284` (v5.0.2, 2026-11-20) | PolyForm Shield 1.0.0 |
| nextendo-docs, nx-dauth, nextendo-account, nextendo-nex, nextendo-nncs, sni-router (`research/`) | shallow clones 2026-11-22 | je Repo |

## 1. Mush8

Rust-Workspace, ~47k Zeilen (ohne libvpx). Kein Emulator: der originale
AArch64-Code läuft **direkt auf der Apple-CPU**. Nur Instruktionen, die
außerhalb von Horizon nicht funktionieren, werden offline umgeschrieben.

### 1.1 nxpatch (`crates/nxpatch`) – Offline-Binary-Rewriter
- Findet per Capstone alle Stellen mit `x18`-Nutzung (auf Apple reserviert),
  `svc`, Systemregister (`tpidr_el0`, `tpidrro_el0`, `cntpct_el0`, `cntfrq`,
  `ctr_el0` …), Exclusive-Load/Store-Spinloops.
- Ersetzt sie durch Branches in Trampoline hinter dem Modul. Trampoline laden
  einen Kontextzeiger aus einer **Keypage** (`align_up(bss_end, 0x4000)`), die
  `x18`/TPIDR spiegelt und einen SVC-Gate-Pointer hält (`nxabi::keypage`).
- `equiv.rs` verifiziert jede Ersetzung mit Unicorn gegen das Original
  (`nxpatch verify`) – wertvoll für Splatoon 3.
- Unterstützt IPS/IPS32-Mods mit Build-ID-Matching (`ips.rs`).
- **Generisch**: `classify`, `rewrite`, `equiv`, `asm`, `spin`, `ips`.
- **MK8-spezifisch** (`rewrite.rs`): `JUMP_TABLES` (3 Einträge, 2 Module-IDs),
  `GAMES` (Keypage-Assertion), `PATCH_GROUPS`/`GAME_PATCHES` (Menü, 4K,
  Splitscreen), `NEXTENDO_SITES`, Aspect-Stores. Alles über Module-ID
  geschlüsselt → für andere Spiele inaktiv, aber nicht schädlich.

### 1.2 nxhost (`crates/nxhost`) – Horizon-HLE + NVN→Metal
- `kernel.rs`/`svc.rs`/`mem.rs`: SVCs, Threads = Host-Threads, Sync-Primitive,
  Adressraum per `mmap(MAP_FIXED)` + `mprotect`.
- `loader.rs`: lädt NSOs, löst dynamische Symbole auf, ersetzt Imports durch
  HLE (`hle.rs`: `nvnBootstrapLoader`, `nn::diag::detail::AbortImpl`), nicht
  aufgelöste Imports werden zu `UNIMPL`-Stubs (loggen, return 0).
- `ipc.rs` + `services/`: HIPC/CMIF-Dienste. Implementiert: `lm`, `fsp-srv`,
  `hid`, `pl:u/s`, `audren:u`, `mii:e/u`, `acc:u0/u1`, `time:*`, `vi:*`,
  `appletOE`, `nifm:*`, `bsd:u/s`, `csrng`, `friend:*`, `aoc:u`, `nfp:user`,
  `set`, `pctl*`, `apm*`; nur im Nextendo-Modus: `sfdnsres`, `nsd:*`, `ssl`,
  `prepo:*`. **Alles andere → `Stub`** (`services/mod.rs:65`).
- `nvn/`: NVN-API als Host-Funktionen (≈133 Proc-Namen als String-Literale),
  Command-Buffer-Decoder (`cmd.rs`), Draw-Pfad auf Metal (`draw/*`), Metal-4-
  Pipeline-Archive.
- `gfx/`: Metal-Präsentation, BC→ASTC-Transcoding für GPUs ohne BC.
- `audio/`: audren-DSP in Software (Voices, Mixer, Effekte) → AudioToolbox.
- `input.rs`, `motion.rs`, `haptics.rs`: GameController, CoreMotion, CoreHaptics.

### 1.3 nxshader (`crates/nxshader`)
Maxwell-(SM5x)-Shader-Disassembler/Decoder (`inst.rs`, 5k Zeilen) und
MSL-Generator (`msl.rs`). Arbeitet auf dem Maxwell-ISA → **spielunabhängig**,
Abdeckung aber nur so weit, wie MK8-Shader es erfordert haben.
`data/pipelines.tsv` ist die MK8-Pipeline-Liste für AOT-Kompilierung.

### 1.4 nxfs (`crates/nxfs`)
NCA (inkl. BKTR-Update-Patching), PFS0, RomFS, NSO, SARC/Yaz0, BNTX, MSBT.
Keys aus `prod.keys` des Nutzers. **Kein XCI/HFS0** → von uns ergänzt (`crates/s3fs`).

### 1.5 iOS-Ausführungsmodell (der entscheidende Punkt)
`crates/nxhost/build.rs`: Beim iOS-Build werden die **gepatchten NSOs per
`.incbin` als eigene Mach-O-Segmente** (`__NX{i}_X` rx, `_D` rw, `_T` rx) an
fixe Adressen ab `0x1_0400_0000` in die App gelinkt und mit der App signiert.
→ Kein JIT, kein `MAP_JIT`, keine unsignierten Pages. Läuft auf normalen
iOS-Geräten. Konsequenzen:
- Pro Spielversion muss die App auf einem Mac neu gebaut werden.
- Die IPA enthält Spielcode → nur für den eigenen Gebrauch, nie verteilen.
- Relocations dürfen nicht in Code-Segmenten liegen (build.rs prüft das).
Hardcodiert: `MODULES = ["main", "subsdk0", "sdk"]` (build.rs, main.rs:347/374,
loader.rs:302).

Auf macOS wird der gepatchte Code zur Laufzeit geladen (`mprotect` mit
`PROT_EXEC`) → **schneller Entwicklungszyklus auf dem Mac**, gleicher Code.

### 1.6 Entitlements
`com.apple.developer.kernel.extended-virtual-addressing` und
`increased-memory-limit`. Ohne (Free-Account/Sideload) nur „5 GB Layout“.

### 1.7 MK8-spezifische Stellen in nxhost
`game.rs` (Versionstabelle per Build-ID), `mods.rs` (TITLE_ID), `nexweb.rs`,
`friend.rs`, `mii.rs`, `nextendo.rs` (NEX-Hosts von MK8), `am.rs`, `prepo.rs`.

## 2. Nextendo / Prelude – Splatoon 3

### 2.1 Protokoll
Splatoon 3 nutzt **kein NEX**, sondern **NPLN (gRPC über HTTP/2, TLS)**
(Kommentar und Hosts in `Prelude-Nextendo/source/nextendo_apply.c:156ff`).
Mush8s Nextendo-Integration ist NEX/PRUDP-spezifisch für MK8 und nicht
übertragbar – nur DNS-Umleitung, Token-Handling und Sign-in-Flow sind
wiederverwendbar.

### 2.2 Hosts (alle → Nextendo-Server `51.178.29.194`, identisch in Mush8 `nextendo.rs` und Prelude `nextendo_config.h`)
- `t-dce9377b-lp1.lp1.t.npln.srv.nintendo.net`, `t-adf89f68-lp1.lp1.t.npln.srv.nintendo.net` (NPLN-Tenants)
- `*.npln.nintendo.net`, `gamesync.npln.nintendo.net` – **Session-Host,
  bidirektionaler gRPC-Stream `KeepUserSession` auf TCP/7575**
- `dragons.hac.lp1.dragons.nintendo.net`, `lp1.nso.nintendo.net`,
  `app.lp1.five.nintendo.net`, BCAT-Hosts (`bcat-list-lp1.cdn.nintendo.net` …),
  `dauth-lp1.ndas.srv.nintendo.net`, `aauth.hac.lp1.ndas.srv.nintendo.net`
  sowie `*.srv.nintendo.net`.

### 2.3 ExeFS-Patches (Splatoon 3 bringt eigenes BoringSSL mit)
`romfs/sd/atmosphere/exefs_patches/`:
- `s3certbypass/<build>.ips`: IPS32, 1 Record `0x157b20: 2A008052`
  (`ldrb w10,[x21,#0x38]` → `mov w10,#1`).
- `s3peername/<build>.ips`: `0x14e1b0: 1F2003D5` (`cbz w0` → `nop`),
  `0x14dd80: F4031F2A` (`mov w20,w0` → `mov w20,wzr`).
- Offsets inkl. 0x100-NSO-Header (`offset_basis: nso_header_included`).
- Vorhanden für Build-IDs `28C4287A…` (11.3.0), `6830B3A1…`, `726D2B88…`.
- Zusätzlich signierter Katalog `https://nextendo.network/service-catalog/v1/npln-patches`
  (Ed25519, Key-ID `npln-patches-key-1`); Fixture rev. 10 enthält für
  `28C4287A` einen 4. Guard `0x4179e2c: 0E000014`.
→ Ob unsere 12.0.0-Dump-Build-ID abgedeckt ist, kann erst nach Entschlüsselung
  geprüft werden (`s3tool analyze` macht das).

### 2.4 Server
Der NPLN-Server für Splatoon 3 (`nplns3-gamesync` u. a.) ist **nicht öffentlich**.
`nextendo-docs` erwähnt NPLN nicht. Auth-Kette öffentlich: `nx-dauth`
(Device-Auth, selbstsignierte Kette), `nextendo-account` (Identitäten,
Freunde, Presence, BCAT, `npln_friends.go`), `baas-jwks`.

## 3. Lokale Spieldaten (`rom/`)

Gemessen mit `s3tool info` (ohne Keys):

| Datei | Container | Inhalt |
|---|---|---|
| `Splatoon 3 [0100C2500FC20000][v0][US].xci` | XCI, Header bei 0x0 | secure: Program 4.71 GB, Control, LegalInfo(?), Meta |
| `Splatoon 3 [0100C2500FC20800][v2752512].nsp` | NSP | Patch v2752512, Program 7.27 GB, KeyGeneration 14, Ticket |

KeyGeneration 14 → zum Entschlüsseln werden die eigenen `prod.keys` (bis
mindestens `master_key_0d`/Keygen 14) und `title.keys` bzw. das Ticket benötigt.
**`prod.keys` liegen nicht vor** (`~/.switch` existiert nicht).
