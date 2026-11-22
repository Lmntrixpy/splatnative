# SplatNative

Native Apple-Silicon-Laufzeit (macOS → iPadOS) für das originale Splatoon 3,
aufgebaut auf [Mush8](https://github.com/c22dev/mush8). Der originale
AArch64-Spielcode läuft direkt auf der CPU; Horizon-Dienste und NVN werden
nativ (Metal) bereitgestellt. Kein JIT.

Keine Spieldaten, Keys oder Firmware im Repo. Benötigt werden eigene Dumps
in `rom/` und die eigenen `prod.keys` unter `~/.switch/prod.keys`.

```
git submodule update --init
cargo build --release
./target/release/s3tool info rom/*.xci rom/*.nsp            # ohne Keys
./target/release/s3tool inspect rom/*.xci rom/*.nsp         # mit Keys
./target/release/s3tool extract --base rom/<base>.xci --update rom/<update>.nsp --out work
./target/release/s3tool analyze work/exefs
cargo test
```

Dokumentation: `docs/ARCHITECTURE.md`, `docs/FEASIBILITY.md`,
`docs/RESEARCH.md`, `docs/REUSABLE_COMPONENTS.md`, `docs/IMPLEMENTATION_PLAN.md`.

Lizenz: GPL-3.0-or-later (Ableitung von Mush8). Prelude-Nextendo-Daten
(PolyForm Shield 1.0.0, Required Notice: Copyright 2026 Nextendo Network)
werden nur gelesen, nicht mitverteilt.
