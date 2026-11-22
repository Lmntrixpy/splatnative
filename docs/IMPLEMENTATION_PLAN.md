# IMPLEMENTATION_PLAN

Status: ✅ erledigt · ⏳ in Arbeit · ⛔ blockiert · ☐ offen

## Phase 1 – Analyse ✅
- ✅ Mush8, Prelude-Nextendo, Nextendo-Repos am Code analysiert (`RESEARCH.md`)
- ✅ Wiederverwendbarkeit bewertet (`REUSABLE_COMPONENTS.md`), Machbarkeit (`FEASIBILITY.md`)

## Phase 2 – Projektstruktur ✅
- ✅ Cargo-Workspace, Mush8/Prelude als Submodule, `.gitignore` für `rom/`, `work/`
- ✅ `s3fs`: XCI/HFS0-Reader, `Package` (NSP|XCI) über nxfs – Unit-Tests + gegen echte XCI geprüft
- ✅ `s3tool info|inspect|extract|analyze`

## Phase 3 – Splatoon-3-Binary vermessen ⛔ (braucht eigene `prod.keys`)
1. ☐ `s3tool inspect rom/*.xci rom/*.nsp` → Display-Version, Module, Build-IDs
2. ☐ `s3tool extract --base rom/*.xci --update rom/*.nsp --out work`
3. ☐ `s3tool analyze work/exefs` → fehlende Imports, NVN-Procs, Dienste, Nextendo-Patch-Status
4. ☐ `nxpatch classify` + `nxpatch rewrite` + `nxpatch verify` auf alle Module
   → Rewriter-Probleme (unbekannte Muster, Jump-Tables) identifizieren
5. ☐ Ergebnisse in `docs/SPLATOON3_PROFILE.md`

## Phase 4 – Mush8 generalisieren (Patch-Serie `patches/mush8/`)
1. ☐ `0001` Modulliste aus ExeFS statt `["main","subsdk0","sdk"]` (main.rs, loader.rs, build.rs)
2. ☐ `0002` Spielidentität (Title-ID, Versionen) konfigurierbar statt `game.rs`/`mods.rs`-Konstanten
3. ☐ `0003` MK8-spezifische HLE/Patches nur für MK8-Module-IDs aktiv (ist großteils schon so – prüfen)
4. ☐ Speicherlayout für Splatoon (NPDM-Heapgröße, Applet-Ressourcen)

## Phase 5 – Start auf macOS bis Nintendo-Logo/Hauptmenü
1. ☐ `nxhost` mit Splatoon auf macOS starten, `[hle] UNIMPL`/Stub-Log auswerten
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
