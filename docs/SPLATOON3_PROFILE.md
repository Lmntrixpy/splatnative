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
| 14–15 | nvdrv, vi:m/s/u, acc:u0, hid, `nvnDeviceInitialize` | SIGSEGV (Nullzeiger +0x20) in main+0x452c7b8 unter `nnMain+0x688` | Ursache: `nvnDeviceGetInteger` API-Version 53/105 (MK8) statt 55/15 → Spiel überspringt den Aufbau seines Grafiksystems |
| 16 | Grafiksystem wird aufgebaut (Queue, Pools, Sampler) | `nn::vi::GetNativeWindow` auf Null-Layer | Patch 0017: API-Version pro Treiber (55/15, aus `0x4c7400`) |
| 17–18 | `ISelfController` 44 liefert Layer 0 → `CreateLayer` bricht vor `OpenLayer` ab | | Patch 0018: Layer-IDs (1, 2) |
| 19–20 | Fenster, 53 Pools, 98 Buffer, 36 Texturen | Host-SIGBUS in `nvnWindowInitialize` | Patch 0017: neue NVN-Strukturlayouts über Treiber-Getter (`nvn/abi.rs`); Patch 0019 Host-Symbole |
| 21 | Shader-Programme | `nvnProgramSetShadersExt` nur Stub | Patch 0017: Ext = SetShaders mit 0x18-Einträgen |
| 22 | Audio-Renderer REV15 | `RequestUpdateAudioRenderer` 0x5299 | Patch 0020: Effekt-Status v2 (0x90) ab REV9 |
| 23 | bcat, nifm | SIGSEGV in `nn::os::SetDyingMessageRegion` | Patch 0021: GetInfo 20 (User-Exception-Context) |
| 24–26 | Kein Absturz mehr; Hauptthread pollt Eingaben | Endlosschleife in `nn::hid::detail::GetNpadStates`/`GetSixAxisSensorStates` | Patch 0022: Seqlock-Stempel in den HID-Lifos |
| 27 | Command-Buffer werden aufgezeichnet, Textur-/Sampler-Getter echt | Hauptthread wartet dauerhaft (`WaitLightEvent`) im Job-System | Ursache: `GetCurrentProcessorNumber` lieferte für jeden Thread Kern 0 |
| 28–39 | **Assets laden (972 Texturen, ~2,5 GB), 3D-Renderpipeline läuft (Schatten, HDR, Blur), 60 fps Present** | Ausgabe schwarz | Patch 0023 (Kern aus Affinität), 0024 (Occlusion-Queries „sichtbar“), 0025 (Diagnose); Bild offen, siehe unten |
| 40–56 | **Erstes Bild: 3D-Szene des Erststart-Bildschirms mit UI, 60 fps** | wartet auf Eingabe | Patch 0026: Zähler-Reports wie der Treiber (Zeitstempel nur im Zeitstempel-Feld), bedingtes Rendern ausgewertet, Clears mit Scissor/Kanalmaske |
| 57–64 | Eingabe per `NX_AUTOINPUT` wirkt; **Texte und Menüs sichtbar** („Wähle einen Style!“) | — | Patch 0027: nxshader übersetzt `BRX`, `ICMP`, `R2P` (≈25 Programme, u. a. Layout-Text); 0028 `NX_TRACE_UBO` |
| 65–71 | **Style gewählt, Charakter erstellt, Spielstand geschrieben; spielbares Tutorial** (Laufen, Schwimmen, Schießen per Skript) | Tutorial-Parcours braucht gezielte Steuerung | Patch 0029 `LEA.HI`; 0030 Halten/Stick in `NX_AUTOINPUT`; 0031 `NX_BACKGROUND`, protokollierte Beenden-Pfade |
| 72–st75 | Ladebildschirm hängt sporadisch (~1 von 5 Starts, auch beim Nutzer) | — | Patch 0032: `SignalToAddress` (ModifyByWaitingCount) wie Horizon; 0033 `NX_THREAD_DUMP_AT`, sichere Probes. Danach 15/15 Starts ohne Hänger |
| 86–94 | **Zielen per Bewegungssteuerung ohne Gyro-Controller**: Spiel liest den virtuellen Sensor, Kamera folgt (hoch/runter, links/rechts geprüft) | — | Patch 0035: virtueller Sechsachsensensor (Maus/I-K), vollständige Tastenbelegung (`docs/STEUERUNG.md`); 0036 `NX_TRACE_MOTION` |
| 95–116 | **Tutorial ohne Geometriefehler** (keine flachen Keile/Balken mehr), alle Compute-Shader laufen | Beine/Arme der Figur fehlen; 2 Shader mit >16 Texturen | Patch 0037: Compute-Programmkopf, `LDS`/`STS`, unausgerichtete Vertex-Attribute; 0038/0039 Draw-Diagnose (`NX_DUMP_EACH_DRAW`, `NX_DUMP_DRAW_BUFFERS`) |

### Gelöst: Befund aus Lauf 15
Der Schreiber `main+0x4529ca8` liegt in der Grafik-Initialisierung hinter der Prüfung
`nvnDeviceGetInteger(API_MAJOR) == 55 && API_MINOR >= 15` (main+0x4529bf4). Mush8 lieferte die
Werte des MK8-Treibers; der Splatoon-Treiber meldet 55/15.

### Gelöst: Befund aus Lauf 27
Das Job-System (main+0x4ad6ca0) übergibt Jobs an den Worker mit Affinitätsmaske `1 << aktueller Kern`
und wartet auf ihn. Mush8 meldete für alle Threads Kern 0 → Warten auf einen selbst wartenden Worker.

### Gelöst: schwarzes Bild (Läufe 32–56)
- Das Spiel rendert seinen Frame vollständig nach f61 (1920×1080, RGB10A2) und löscht ihn danach zweimal
  unter `SetRenderEnableConditional(!=)`; verglichen wird das Zählerfeld eines Reports vom Typ 16 mit 0.
- Im Treiber (ReportCounter 0x4ef450) schreibt Typ 16 eine 16-Byte-Semaphore mit Payload 0, Typ 0 einen
  Report mit Payload 0 (Steuerwort 0xf002): das Zählerfeld ist 0, die Zeit steht bei +8. Mush8 schrieb
  die Zeit ins Zählerfeld → Bedingung wahr → Frame vor dem Anzeigen gelöscht.
- Gefunden mit Render-Target-Dumps, einem Konstantfarben-Experiment (Fragment-Shader → Magenta) und
  Dumps unmittelbar vor jedem Clear; alle Experimente sind wieder entfernt.

### Aktueller Stand (Lauf 56)
- Erststart-Bildschirm (keine Speicherdaten → Intro/Charaktereinrichtung) mit 3D-Szene, Schatten,
  Tiefenunschärfe und UI-Ebene, 60 fps. Bilder per `NX_DUMP_AT` in `work/frame/` (nicht im Repo).
- Vermeintlicher UI-Skalierungsfehler geklärt: die schrägen Tafeln links oben sind das Layout des Spiels
  (Positionen aus den Konstantenpuffern nachgerechnet); es fehlten Texte, weil ihre Shader `BRX`/`ICMP`/`R2P`
  enthielten (Patch 0027).
- Stand Lauf 71: Speicherdaten vorhanden (`work/save-0100c2500fc20000`), das Spiel startet im Tutorial.
  Nächster Schritt: Tutorial durchspielen (manuell oder per Skript) bis zur Stadt/zum Hauptmenü.

### Gelöst: Lade-Hänger im Datei-Cache (Läufe 72–st75)
- Symptom: Ladebildschirm (Tinten-Animation) läuft endlos; ein Ladethread wartet in
  `FileDataCacheSystem::ReserveFreePagesByGatherCompaction` (sdk+0x10a328) auf das `LightEvent` bei
  Cache+0x68, bis andere Threads reservierte Seiten committen (`CommitCachePages` signalisiert immer).
- `NX_THREAD_DUMP_AT` zeigte: kein anderer Thread im Cache, alle Speicher-Lesezugriffe erfolgreich
  (Probe hinter `IStorage::Read`) → verlorenes Wecken, nicht verlorene Reservierung.
- Das SDK-`LightEvent` (Auto-Clear) nutzt den Zustand 0 = frei, 1 = Wartende, 2 = signalisiert und
  `SignalToAddress(SignalAndModifyByWaitingCountIfEqual, 1, count 1)`. Horizon (Atmosphere
  `KAddressArbiter`): ohne Wartende +1, sonst −1 nur wenn alle weiteren Wartenden mit geweckt werden,
  sonst unverändert. Mush8 setzte bei zwei Wartenden 0 und weckte nur einen → der zweite schlief für
  immer, spätere Signale setzten nur 2 ohne Syscall.
- Patch 0032 rechnet wie Horizon (Unit-Tests inkl. Zwei-Wartende-Szenario).

### Spielstand: warum jeder Start bei der Style-Wahl beginnt (Läufe 80–85)
- `NX_TRACE_FS` (Patch 0034): beim Start liest das Spiel `save.dat` und schreibt sie sofort zurück
  (verschlüsselt, jedes Mal anders). Nach Style-Wahl, Charaktererstellung und bis in den
  Ballon-Abschnitt des Tutorials (330 s) folgt **kein** weiterer Schreibzugriff.
- Im Spielcode liegt der Zustand `State::CreateSaveData` in der Erststart-Sequenz
  `IntroduceFest → NetworkAnalyze → SelectFestRegion → ConfirmFestRegion(_Reboot) → CreateSaveData`
  (main+0x3b02xxx): der Charakter wird erst nach Tutorial und Wahl der Splatfest-Region gespeichert.
- Kein Host-Fehler gefunden (Lesen/Schreiben/Commit korrekt, kein hängender Speicher-Thread,
  alte Arbiter-Semantik ändert nichts). Die frühere Beobachtung „Start direkt im Tutorial“ (Lauf 66)
  ist nicht reproduzierbar.
- Offen: Mush8s Speicher-Dateisystem schreibt direkt in die Datei, `Commit` ist ein No-op (Horizon:
  transaktional). Bei Abbruch während eines Schreibvorgangs könnte der Spielstand beschädigt werden.

### Bewegungssteuerung (Läufe 86–94)
- Splatoon 3 startet den Sensor des Pro Controllers (`StartSixAxisSensor`, Handle 0x00020003) und
  liest ihn über `nn::hid::detail::GetSixAxisSensorStates` (sdk+0x50bf60) aus dem Lifo bei 0x1758
  im Npad-Block – dieselben Offsets und dasselbe Seqlock-Format, die Mush8 schreibt.
- Ohne Bewegungsdaten driftete die Kamera in Lauf 87 im Ballon-Abschnitt (t245); mit dem
  virtuellen Sensor blieb sie stabil.
- Vorzeichen im Spiel geprüft: Drehrate um +x neigt die Kamera nach **unten** (Lauf 92: „Langsam
  nach oben neigen.“ nach skriptiertem Hochzielen mit der ersten Vorzeichenwahl), um +z nach
  **links**. Nach Korrektur (Lauf 93/94) führt `AIMUP` die Kamera nach oben, `AIMRIGHT` dreht wie
  `RRIGHT` nach rechts. 0,45 rad Neigung reichen schon für die Hinweisanzeige „zu weit“: das Spiel
  setzt Sensor-Drehung etwa 1:1 oder stärker in Kamera-Drehung um.
- Der Ablauf der Erststart-Sequenz schwankt zwischen Läufen stark (Lauf 86 blieb bei
  „Gefällst du dir?“, Lauf 87 erreichte die Ballons nach 140 s); ohne Eingaben läuft das Tutorial
  teils von selbst weiter (Läufe 88/89).

### Shader- und Geometriefehler (Läufe 95–116)
- **Compute-Shader:** Splatoon 3 nutzt fünf Compute-Programme. Ihr Code beginnt mit einem 0x100-Byte-Kopf
  (Magic 0x12345679, sonst Nullen); Mush8 (für MK8DX gebaut, dort ohne Kopf) übersetzte den Kopf als
  Code → „invalid instruction 0 at 0x8“. Jetzt wird der Kopf übersprungen; zwei der Programme nutzen
  Shared Memory (`LDS`/`STS`, ohne `BAR`), das auf ein Threadgroup-Feld (32 KiB) abgebildet wird.
- **Flache Keile/dunkle Balken im Tutorial:** Mit `NX_DUMP_EACH_DRAW` (Farb- und Tiefenpuffer nach jedem
  Draw) gefunden: Gelände-Meshes (VS `a5e31b877f634132`) haben 69 Byte Vertex-Abstand. Die meisten Positionen
  liegen dadurch nicht auf 4-Byte-Grenzen; Wortladen von solchen Adressen lieferte auf der Apple-GPU falsche
  Werte (auf der CPU gelesen waren die Positionen korrekt). Riesige Dreiecke schrieben nur Tiefe (Vorpass),
  der Farbpass mit Tiefentest EQUAL traf sie nie → alter Bildinhalt blieb stehen. `fetch_attr` sammelt
  unausgerichtete Attribute jetzt byteweise; das Tutorial wird sauber dargestellt.
- Der Shader-Cache-Schlüssel enthält jetzt den Prelude-Hash, damit geänderte Hilfsfunktionen nicht mit
  alten Bibliotheken gemischt werden.
- **Fehlende Beine/Arme (offen):** Kein Draw schreibt dort Tiefe. Der Körper-Draw (VS `9661f455…`/`7532a2e0…`,
  3204 Indizes) nutzt laut ausgelesenen Puffern (`NX_DUMP_DRAW_BUFFERS`) nur die Knochen 26/27, die das Spiel
  selbst auf 1 % skaliert (so blendet Splatoon verdeckte Körperteile aus); auf der CPU nachgerechnet landen
  die Vertices zusammengefallen im Beinbereich. Kein Übersetzungsfehler in diesem Draw; welcher Draw die
  sichtbaren Beine liefern müsste, ist noch nicht gefunden. Ausgeschlossen: bedingtes Rendern, Culling,
  Tiefentest EQUAL, fehlgeschlagene Draws.
- **Offen:** Zwei Fragment-Shader (`a791e3bcb93355bb`, `11c0b56ba2312e14`, ab ca. 200 s) nutzen mehr als 16
  Texturen; Metal erlaubt 16 Sampler pro Stufe, die Draws fallen aus. Lösung braucht Sampler im
  Argument-Buffer.

### Beobachtet, noch nicht umgesetzt: Kernzuordnung
- Threads mit idealem Kern −2 („Prozesswert“) behalten im Host −2, obwohl das Spiel später Masken 0x2/0x4
  setzt; der Host-Scheduler (`sched_core`) ordnet sie alle Kern 0 zu. Horizon löst −2 beim Erzeugen auf
  den Prozesskern auf und wählt bei `SetThreadCoreMask(-3, Maske)` einen Kern aus der Maske. Kein Hänger,
  aber weniger Parallelität; Korrektur später (betrifft Leistung, v. a. auf dem iPad).

### Bekannt offen (nicht blockierend)
- Audio REV15: Voice-Eingabe ist 0x188 statt 0x170 Byte pro Voice; Mush8s Parser nimmt 0x170.
