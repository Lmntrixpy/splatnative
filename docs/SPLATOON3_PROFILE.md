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
