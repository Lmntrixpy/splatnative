# SPLATOON3_PROFILE – gemessen am lokalen Dump (2026-11-23)

Erzeugt mit `s3tool inspect/extract/analyze` und `nxpatch classify/rewrite/verify`.
Rohdaten: `work/analyze.txt`, `work/verify.txt` (nicht im Repo).

## Version

| | Basis (XCI) | Update (NSP v2752512) |
|---|---|---|
| Display-Version | 1.0.0 | **11.3.0** |
| `main` Build-ID | `19FE149D…` | `28C4287AEE36F7499DA60F3E68B54C70DA382D75` |
| `sdk` Build-ID | `F748F74B…` | `574284B40C06CF1821A44857939083BEE5716820` |
| `rtld` | vorhanden | vorhanden (wird von Mush8 nicht ausgeführt) |

Hinweis: Das Update ist 11.3.0, nicht 12.0.0.

## Module (11.3.0)

| Modul | text | ro | data | bss | Symbole | Relocations |
|---|---|---|---|---|---|---|
| main | 0x4e8f680 (78 MiB) | 0xc37e68 | 0x53db98 | 0x1f3468 | 1292 | 535 826 (528 692 RELATIVE, **RELR**) |
| sdk | 0x663700 | 0x4cbe70 | 0x554e8 | 0xcfb18 | 23 065 | 34 059 (**DT_GNU_HASH**, kein DT_HASH) |

Kein `subsdk*`. NPDM: 64-Bit, Hauptthread-Priorität 44, Core 0, Stack 0x100000.

## Binary-Rewrite (Mush8 nxpatch + SplatNative-Patches 0001)

| | main | sdk |
|---|---|---|
| x18-Stellen | 48 360 | 15 564 |
| Systemregister | 804 | 174 |
| SVC | 165 | 58 |
| Exclusive-Regionen | 38 | 4 |
| Spinloops | 49 | 1 |
| Jump-Tables über x18 | 102 (ldrb/ldrh, neu) | 8 |
| Trampoline | 25 114 KiB | 650 KiB |
| **`nxpatch verify` (Unicorn)** | **49 469 äquivalent, 0 Fehler** | **15 808 äquivalent, 0 Fehler** |

Gefundene und behobene Mush8-Lücken:
1. `br x18` über komprimierte Clang-Switch-Tabellen → `patches/mush8/0001`
2. DT_RELR (main) und DT_GNU_HASH (sdk) → `patches/mush8/0002`
3. Modulliste `main,subsdk0,sdk` hardcodiert → `patches/mush8/0003`

Bekannt: ldrh-Tabellen ohne lokal auffindbare Basis bekommen den vollen
65536er-Pad-Bereich (≈ 23 MiB der Trampoline). Korrekt, aber groß → Optimierung offen.

## Imports ohne Definition
14, **alle weak**: `glslc*` (Laufzeit-GLSL-Compiler, 8), `nn::pia::ZSTD_trace_*` (4),
gRPC-TLS-Init-Funktionen (2). Unkritisch, Mush8 stubbt sie.

## NVN
569 Proc-Namen im Spiel, 124 davon in Mush8 implementiert. Unbekannte Procs
liefert Mush8 als zählende Stubs aus (`nvn/mod.rs proc_for`). Welche wirklich
aufgerufen werden, zeigt erst der Laufzeit-Report (`nvn::summary`).
Fehlende nach Objektklasse: CommandBuffer 106, Texture 74, Sampler 40, Queue 28,
Device 28, MultisampleState 23, MemoryPool 21, Window 19, BlendState 15, …

## Horizon-Dienste (als Namen referenziert)
Von Mush8 implementiert: acc, aoc, appletOE, audren, bsd, friend, fsp-srv, hid,
lm, mii, nfp, nifm, nsd, pctl, pl, prepo, set, sfdnsres, ssl, time, vi.
Nicht implementiert (Stub): appletAE, audin, audout, audrec, bcat, caps,
ectx, hid:sys/dbg, hidbus, hwopus, ldn, nfc, nim, notif, ntc, nvdrv, set:sys,
es, ngct. Ein Name im Binary heißt nicht zwingend, dass das Spiel den Dienst
öffnet – maßgeblich ist das Laufzeit-Log.

## Nextendo
Für `main` 28C4287A… liegen beide Prelude-Patches vor; die Originalbytes im
Dump stimmen mit den Katalog-Guards überein:

| Patch | Stelle (text) | Original | Neu |
|---|---|---|---|
| s3certbypass | 0x157a20 | `AAE24039` ldrb w10,[x21,#0x38] | `2A008052` mov w10,#1 |
| s3peername | 0x14e0b0 | `C0020034` cbz w0 | `1F2003D5` nop |
| s3peername | 0x14dc80 | `F403002A` mov w20,w0 | `F4031F2A` mov w20,wzr |

Beide wenden sich mit `nxpatch rewrite --patch` sauber an.

## Boot-Protokoll auf macOS (M2), `nxhost` mit SplatNative-Patch-Serie

Jeder Lauf ist auf 120–150 s begrenzt; Logs in `work/runN.log`.

| Lauf | Erreicht | Abbruch | Lösung |
|---|---|---|---|
| 1 | Spiel erkannt, RomFS 10,06 GB direkt aus XCI+NSP, Adressraum | ungenutzter MK8-Movie-Override → Abbruch | Patch: nur `nvnBootstrapLoader` ist Pflicht |
| 2 | Module geladen + relocated (528k RELR) | `nn::init::Start` (4 Argumente) fehlt | Patch: 5-Argument-`nn::init::Start` (Fini-Callback in x4) |
| 3 | Einstiegspunkt gefunden | `nvn::init`: unbekannter sdk-Build | Patch: NVN-Treibertabellen für Splatoon-sdk (534 Procs, Format-Stride 0x30) |
| 4 | NVN-Treibertabellen geladen | `movie::init`-Panic (Bibliothek fehlt) | Patch: Movie-Hooks überspringen |
| 5 | **Gastcode läuft**: `nn::init::Start` → `nninitInitializeSdkModule` → `nn::lm::Initialize` | `sm:` Nachrichtentyp 16/17 (TIPC) | Patch: TIPC in `ipc.rs` |
| 6 | sm: vergibt lm, apm, appletOE, aoc, ectx, pctl, time | `nn::time::Initialize`: `time:u` 20 (Shared Memory) nur Stub | Patch: Time-Shared-Memory |
| 7 | Time ok; **`nnMain` läuft**, Metal erkennt Apple M2, GPU-Heap angelegt | `nn::oe::TryPopLaunchParameter`: leerer Kanal als 0x2680 statt 0x480 | Patch: am-Ergebnis 0x480 (nicht-MK8) |
| 8 | – | `MapSharedMemory` 0xcc01 (zufällig, 3 von 4 Läufen) | Patch: 16-KiB-Host-Seiten → InvalidCurrentMemory, SDK versucht andere Adresse |
| 9–13 | RomFS-Lesezugriffe, Sprache `de`, Version 11.3.0, Betriebsmodus | Hänger, 100 % CPU: `TryWaitSystemEvent` auf Handle 0, `IApplicationFunctions` 210 ohne Event | Patch: Event für cmd 210; Diagnose per `sample` + `NX_TRACE_SVC` |
| 14 | nvdrv, vi:m/s/u, acc:u0, hid, `nvnDeviceInitialize` | SIGSEGV (Nullzeiger +0x20) in main+0x452c7b8 unter `nnMain+0x688`, nach hid-Stubs 1004/11 | offen |

