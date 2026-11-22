# IMPLEMENTATION_PLAN

Status: ✅ erledigt · ⏳ in Arbeit · ⛔ blockiert · ☐ offen

## Phase 1 – Analyse ✅
- ✅ Mush8, Prelude-Nextendo, Nextendo-Repos am Code analysiert (`RESEARCH.md`)
- ✅ Wiederverwendbarkeit bewertet (`REUSABLE_COMPONENTS.md`), Machbarkeit (`FEASIBILITY.md`)

## Phase 2 – Projektstruktur ✅
- ✅ Cargo-Workspace, Mush8/Prelude als Submodule, `.gitignore` für `rom/`, `work/`
- ✅ `s3fs`: XCI/HFS0-Reader, `Package` (NSP|XCI) über nxfs – Unit-Tests + gegen echte XCI geprüft
- ✅ `s3tool info|inspect|extract|analyze`

## Phase 3 – Splatoon-3-Binary vermessen ✅
1. ✅ `s3tool inspect` → Update ist **11.3.0**, Module main + sdk (+ rtld), kein subsdk
2. ✅ `s3tool extract` (ExeFS + control; RomFS noch nicht)
3. ✅ `s3tool analyze` → 14 weak Imports, 569 NVN-Procs (124 in Mush8), Dienste, Nextendo-Patches passen
4. ✅ `nxpatch rewrite` + `verify`: 65 277 Patches äquivalent, 0 Fehler
5. ✅ `docs/SPLATOON3_PROFILE.md`

## Phase 4 – Mush8 generalisieren (Patch-Serie `patches/mush8/`, `tools/apply-mush8-patches.sh`)
1. ✅ `0001` nxpatch: Jump-Tables über x18 per Muster statt Liste
2. ✅ `0002` nxfs: DT_RELR + DT_GNU_HASH
3. ✅ `0003` nxhost: Modulliste aus den Layouts (macOS + iOS build.rs, `cargo check` iOS mit Splatoon-Modulen grün)
4. ☐ Spielidentität (Title-ID, Versionstabelle `game.rs`, `mods.rs`, Savedata-Pfad) konfigurierbar
5. ☐ Speicherlayout für Splatoon (NPDM-Heap, Applet-Ressourcen)
6. ☐ ldrh-Jump-Tables: Basis weiter zurückverfolgen → Trampoline von 25 MiB verkleinern

## Phase 5 – Start auf macOS bis Nintendo-Logo/Hauptmenü ⏳
1. ⏳ `nxhost` mit Splatoon auf macOS starten, Stub-Log auswerten – SDK-Init komplett, `nnMain` läuft,
   Metal-GPU initialisiert, Display/Account/HID-Dienste werden geöffnet
   (Verlauf: `docs/SPLATOON3_PROFILE.md`, Boot-Protokoll; Mush8-Patches 0006–0015)
2. ☐ Fehlende Dienste minimal und korrekt implementieren (pro Dienst Test in `services/`)
3. ☐ Fehlende NVN-Procs, Shader-Opcodes ergänzen; erste Frames
4. ☐ Pipeline-Liste für Splatoon aufzeichnen (`work/pipelines.tsv`) → AOT
5. ☐ Savedata, Controller, Audio verifizieren; Hauptmenü erreichen

## Phase 6 – iPad
1. ☐ `make-ios.sh`-Äquivalent für Splatoon (Modulliste, Ressourcen, ~10 GB RomFS)
2. ☐ Entitlements/Speicher auf echtem M-iPad prüfen
3. ☐ Meilenstein: **Hauptmenü auf Apple-Silicon-iPad**

## Phase 7 – Nextendo (später)
1. ☐ Patch-Abdeckung der eigenen Build-ID prüfen (`analyze`), sonst bei Nextendo anfragen
2. ☐ Netzwerk-Regelsatz NPLN: DNS (inkl. `*.npln.nintendo.net`, TCP 7575), TLS-Ziele
3. ☐ Verbindungstest **ohne Spiel**: TLS/HTTP2 zu den Tenant-Hosts vom Mac
4. ☐ Auth (dauth/aauth/baas) im HLE gegen nx-dauth/nextendo-account
5. ☐ Lobby, dann Match

## Phase 8 – Stabilisierung
Performance (CPU/GPU), Speicher, Thermik, Crash-Reports, Netzwerkstabilität.
