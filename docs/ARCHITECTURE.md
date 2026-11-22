# ARCHITECTURE

```
 ┌──────────────────────── Mac (Build-Zeit) ─────────────────────────┐
 │ rom/*.xci + *.nsp + eigene prod.keys                              │
 │   │  s3tool extract   (s3fs: XCI/HFS0 → nxfs: NCA/BKTR/PFS0/RomFS) │
 │   ▼                                                               │
 │ work/exefs/{main,subsdk*,sdk,main.npdm}    work/romfs/…           │
 │   │  s3tool analyze   → Bedarf: Imports, NVN-Procs, Dienste, Patches│
 │   │  nxpatch rewrite [--patch s3certbypass,s3peername .ips]        │
 │   ▼                                                               │
 │ work/patched/{*.bin,*.layout}  (x18/svc/sysreg → Trampoline)      │
 │   │  Shader-AOT (nxshader → MSL → metallib, Pipeline-Liste)       │
 │   ▼                                                               │
 │ cargo build nxhost --target aarch64-apple-ios                     │
 │   build.rs: .incbin patched/*.bin als Mach-O-Segmente (rx/rw/rx)  │
 └───────────────────────────────┬───────────────────────────────────┘
                                 ▼
 ┌──────────────────────── iPad (Laufzeit) ──────────────────────────┐
 │ SwiftUI-Launcher  ──►  nxhost (Rust)                              │
 │                         ├ loader: Module, dyn. Symbole, HLE       │
 │                         ├ kernel/svc: Threads, Sync, Speicher     │
 │   Original-Splatoon-3-  ├ services/: fsp-srv, hid, audren, acc,   │
 │   Code läuft nativ auf  │   time, vi, applet, nifm, bsd, ssl, …   │
 │   der CPU; SVC/x18 über ├ nvn/ → Metal (Command-Buffer-Decoder)   │
 │   Trampoline → nxhost   ├ audio/ → AudioToolbox                   │
 │                         └ net: bsd-Sockets + DNS-Umleitung        │
 │                                   └► Nextendo (NPLN/gRPC, TCP 7575)│
 └───────────────────────────────────────────────────────────────────┘
```

## Repository-Struktur (tatsächlich)

Die vorgeschlagene Struktur aus der Aufgabenstellung (`Runtime/`, `Horizon/`,
`Graphics/` …) wurde **bewusst nicht** angelegt: diese Schichten existieren
bereits als Mush8-Crates, und leere Parallelordner würden genau die doppelte
Implementierung erzeugen, die vermieden werden soll.

```
splatnative/
├── Cargo.toml            Workspace (GPL-3.0)
├── crates/
│   ├── s3fs/             XCI/HFS0 + Package-Abstraktion über nxfs   [neu]
│   └── s3tool/           info / inspect / extract / analyze         [neu]
├── third_party/
│   ├── mush8/            Submodul, unverändert (89dc804)
│   └── Prelude-Nextendo/ Submodul, unverändert (c406284) – nur gelesen
├── patches/mush8/        nachvollziehbare Änderungen an Mush8 (Serie)
├── docs/                 diese Dokumente
├── research/             Referenz-Clones (gitignored)
├── rom/                  Spieldaten des Nutzers (gitignored)
└── work/                 Build-Artefakte aus Spieldaten (gitignored)
```

Spätere Crates entstehen erst, wenn es echten Code dafür gibt, z. B.
`crates/s3net` (NPLN-spezifische Netzwerkregeln) oder eine iOS-App unter `app/`.

## Austauschbares Netzwerk-Backend

Mush8 kennt bereits `vnet::Mode` (LAN, lan-play, Wireless, Nextendo). Für
Splatoon wird ein Backend als **Regelsatz** beschrieben: DNS-Umleitungen,
erlaubte TLS-Ziele, zusätzliche IPS-Patches. Nextendo-NPLN ist ein solcher
Regelsatz; ein anderer Server ist nur ein anderer Satz – kein neuer Code.

## Technische Entscheidungen

| Entscheidung | Begründung |
|---|---|
| Rust + Mush8-Crates statt C++-Neuentwicklung | funktionierender Code, gleiche Sprache, kein Doppelstack |
| AOT-Rewrite + statisches Linken | einziges Modell ohne JIT auf Standard-iOS |
| macOS zuerst | gleicher Code, schnelle Iteration, Debugger |
| Mush8 unverändert + Patch-Serie | Upstream-Updates bleiben einspielbar, jede Änderung begründet |
| Prelude-Daten zur Laufzeit lesen | Lizenz (PolyForm Shield), Aktualität bei Spiel-Updates |
