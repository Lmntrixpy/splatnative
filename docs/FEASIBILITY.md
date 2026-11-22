# FEASIBILITY – Machbarkeit

Bewertung: 🟢 machbar mit vorhandenem Code · 🟡 machbar, erheblicher Aufwand · 🔴 ungeklärt/blockiert

## Gesamturteil

Ein nativer Start von Splatoon 3 auf Apple Silicon ist **grundsätzlich machbar**,
weil Mush8 das schwierigste Problem – Ausführung von Switch-AArch64-Code auf
iOS ohne JIT – bereits für ein großes NVN-Spiel gelöst hat und dieser Teil
spielunabhängig ist. Der Weg zum Hauptmenü ist aber **kein Portierungs-,
sondern ein Kompatibilitätsprojekt**: jede fehlende NVN-Funktion, jeder
Shader-Opcode und jeder Dienst, den MK8 nie benutzt hat, muss ergänzt werden.
Seriöse Aufwandsschätzung: Wochen bis Monate, nicht Tage.

## Komponenten

| Komponente | Bewertung | Begründung / Risiko |
|---|---|---|
| Dump lesen (XCI+NSP) | 🟢 erledigt bis auf Keys | `s3fs` liest XCI; Entschlüsselung via nxfs, **braucht eigene prod.keys** |
| ARM64-Ausführung ohne JIT | 🟢 | Mush8-Modell (AOT-Rewrite + statisches Linken) ist generisch |
| Rewriter-Korrektheit | 🟡 | Splatoon-Code kann Muster enthalten, die nxpatch nicht kennt (z. B. Jump-Tables über umgeschriebene Bereiche) → `nxpatch verify` |
| Modulanzahl | 🟡 | Mush8 hardcodiert 3 Module; Splatoon hat ggf. mehr `subsdk*` |
| Speicher | 🟡 | 4-GB-Titel; braucht Extended-VA-Entitlement (bezahlter Dev-Account) oder sorgfältige Heap-Konfiguration; iPads mit ≥8 GB RAM |
| Horizon-Dienste | 🟡 | Basis da; Splatoon nutzt sehr wahrscheinlich zusätzlich bcat, olsc, friend, ns, pdm u. a. – Liste wird gemessen |
| NVN-API | 🟡 | ≈133 Procs vorhanden; neuere SDK-Version des Spiels kann weitere brauchen |
| Shader-Übersetzung | 🟡/🔴 | Größtes technisches Risiko: Tinte = Compute/Texturen-Feedback, viele Shader-Varianten, AOT-Pipeline-Liste muss neu aufgezeichnet werden |
| Tinten-Rendering korrekt | 🔴 | Splatoon-spezifische GPU-Nutzung (Render-to-texture der Tinten-Map, ggf. Compute) ist in Mush8 nicht erprobt |
| Audio | 🟢 | audren-DSP generisch |
| Controller/Gyro | 🟢 | vorhanden |
| Savedata | 🟢/🟡 | fsp-srv vorhanden, Pfade/Title-ID generalisieren |
| Nextendo-Verbindung | 🟡 | DNS-Umleitung + Zertifikatspatches existieren; Auth-Flow (dauth/aauth/baas) für NPLN muss im HLE stimmen |
| Online-Matches | 🔴 | NPLN-Server nicht öffentlich, nur Nextendos Instanz; Patches nur für bestimmte Build-IDs; P2P-UDP über iOS-Netz |
| Verteilung | 🔴 per Design | Spielcode wird in die App gelinkt → nur eigener Build auf eigenem Gerät |

## Harte iOS-Grenzen und Antwort darauf

1. **Kein JIT** → Spielcode wird offline umgeschrieben und als signiertes
   Mach-O-Segment gelinkt (Mush8-Modell). Kein Fallback-Interpreter nötig.
2. **Code-Signing** → jede Spielversion erfordert einen neuen App-Build am Mac.
3. **Speicherlimit** → `increased-memory-limit` + `extended-virtual-addressing`.
   Ohne bezahlten Account: kleineres Layout, für Splatoon evtl. zu klein (zu messen).
4. **Sandbox** → Spieldaten (RomFS, ~10 GB) über Files-App in Documents;
   alternativ vorbereitete RomFS vom Mac kopieren.

## Strategische Entscheidung

**Erst macOS (Apple Silicon), dann iPad.** Gleicher Code, gleiche CPU, gleiche
GPU-Familie, aber Debugger, schnelle Iteration, kein Signieren pro Versuch.
Das Mac-M2 in diesem Arbeitsplatz reicht dafür. Erst wenn Splatoon auf macOS
das Hauptmenü erreicht, lohnt der iOS-Build.

## Rechtliches (technische Einordnung, keine Rechtsberatung)
- Keine Keys, Firmware oder Spieldaten im Repo; `rom/` ist ignoriert.
- Keine Funktion zum Beschaffen von Keys; Entschlüsselung nur mit vom Nutzer
  bereitgestellten eigenen Keys (wie Mush8/Emulatoren).
- Prelude-Daten (PolyForm Shield) werden nicht kopiert, sondern aus dem
  Checkout bzw. dem signierten Katalog geladen. Nutzung von Nextendos eigenem
  Netz konkurriert nicht mit Nextendo.
