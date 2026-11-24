# Steuerung (macOS)

Gilt für den Mush8-Host (`nxhost`) mit den SplatNative-Patches ab 0035 (Steuerung) und 0036 (Diagnose). Tastatur und Maus
steuern Spieler 1 als Pro Controller. Ein angeschlossener Gamepad wird zusätzlich erkannt
(Bewegungssensoren eines echten Controllers nur mit `NX_MOTION=1`).

## Tastatur

| Switch-Taste | Taste(n) | Splatoon 3 |
|---|---|---|
| Linker Stick | W A S D | Laufen |
| Rechter Stick | J L (waagerecht), I K (senkrecht) | Kamera; I/K neigen zusätzlich den virtuellen Bewegungssensor |
| A | X, Enter | Bestätigen |
| B | Z, Rücktaste, **Leertaste** | Springen / Zurück |
| X | C | Karte |
| Y | V | Kamera zurücksetzen |
| L | Q | – |
| R | E | Sekundärwaffe |
| ZL | 1, **linke Umschalttaste** | Abtauchen (Tintenfisch) |
| ZR | 3 | Schießen |
| Linker Stick drücken | **G** | – |
| Rechter Stick drücken | **F** | Spezialwaffe |
| + | Tab, = | Menü |
| − | - (Bindestrich) | – |
| Steuerkreuz | Pfeiltasten | Signale / Emotes |

Fett: neu in Patch 0035. Cmd-F schaltet Vollbild, Cmd-Q/W beendet.

## Zielen mit der Maus (Bewegungssteuerung)

Splatoon 3 zielt standardmäßig mit dem Gyrosensor; senkrecht reagiert die Kamera dann nicht auf
den rechten Stick. Der Host meldet für Spieler 1 deshalb einen virtuellen Bewegungssensor, wenn
kein echter Controller Bewegungsdaten liefert:

- **M** im Spielfenster fängt die Maus ein (Zeiger ausgeblendet und festgehalten). Mausbewegung
  dreht den virtuellen Controller: links/rechts = Drehung, hoch/runter = Neigung.
- Maustasten, solange eingefangen: **links = ZR** (Schießen), **rechts = R** (Sekundärwaffe),
  **Mitte = rechter Stick drücken** (Spezialwaffe).
- **Esc** oder erneut **M** gibt die Maus frei; ebenso jeder Fensterwechsel (Cmd-Tab).
- Ohne Maus: **I/K** neigen den Sensor mit fester Geschwindigkeit.
- Nicht eingefangen bleibt der linke Mausklick der Touchscreen (wie bisher).

Die Neigung ist auf ±80° begrenzt; Y (Taste V) setzt im Spiel die Kamera zurück und richtet
den virtuellen Sensor wieder waagerecht aus (Patch 0040), damit die Grenze danach von der neuen
Mitte aus zählt.

## Gamepad (Patch 0040)

Splatoon 3 zielt senkrecht nur mit dem Bewegungssensor; der rechte Stick dreht im Gyro-Modus nur
waagerecht. Ein Gamepad ohne Bewegungsdaten (jedes Gamepad ohne `NX_MOTION=1`, oder ohne Gyro wie
Xbox-Controller) bekommt deshalb ebenfalls den virtuellen Sensor: **rechter Stick hoch/runter neigt
ihn** wie I/K, mit `NX_KEY_GYRO_RATE` bei Vollausschlag. Unter 15 % Ausschlag passiert nichts
(Stick-Drift soll die Kamera nicht langsam wegdrehen). Waagerecht liest das Spiel den Stick selbst.

- Echtes Gyro-Zielen mit Pro Controller/DualSense: `NX_MOTION=1`; dann ersetzt der echte Sensor
  den virtuellen und der Stick neigt nicht mehr.
- Wer im Spiel die Bewegungssteuerung ausschaltet, zielt mit dem Stick direkt; der virtuelle
  Sensor wird dann vom Spiel ignoriert.

### Einstellungen (Umgebungsvariablen)

| Variable | Standard | Bedeutung |
|---|---|---|
| `NX_MOUSE_SENS` | `0.003` | Drehung in Radiant pro Mauspunkt |
| `NX_KEY_GYRO_RATE` | `1.5` | Drehgeschwindigkeit für I/K und Skript-Zielen in rad/s |
| `NX_KEY_GYRO=0` | an | virtuellen Sensor abschalten (dann wie vorher: keine Bewegungsdaten) |

### Skript-Eingabe

`NX_AUTOINPUT` kennt zusätzlich `AIMUP`, `AIMDOWN`, `AIMLEFT`, `AIMRIGHT` (mit `*Sekunden`), die
den virtuellen Sensor mit `NX_KEY_GYRO_RATE` drehen, z. B. `NX_AUTOINPUT="336:AIMUP*0.5"`.

## Umsetzung

- `crates/nxhost/src/input.rs`: je Spieler ein `VirtualGyro` (Tastatur-Spieler, Gamepads und
  iPhone-Controller ohne eigene Bewegungsdaten); die Neigung kommt aus der senkrechten Achse des
  rechten Sticks nach Totzone (`stick_tilt`), I/K landen auf derselben Achse. `VirtualGyro` erzeugt Drehrate (rad/s) und eine dazu passende
  Schwerkraftrichtung (Beschleunigung `[0, −sin θ, −cos θ]` bei Neigung θ nach oben). Mausbewegung wird nicht
  in einem einzigen 5-ms-Abtastwert gemeldet, sondern mit einer Zeitkonstante von 12 ms verteilt,
  damit ein Spiel, das pro Bild nur den jüngsten Abtastwert liest, die ganze Drehung sieht
  (Summe bleibt erhalten; Unit-Test `virtual_gyro_delivers_the_whole_turn`).
- Die Werte laufen über den bestehenden Weg `MOTION` → `services/hid.rs` (`push_sixaxis`) als
  Smartphone-artige Quelle (reine Gyro-Integration ohne Beschleunigungskorrektur), damit die
  Neigung nicht von der Sensorfusion zurückgezogen wird.
- `crates/nxhost/src/gfx/mod.rs`: Einfangen über `CGAssociateMouseAndMouseCursorPosition` und
  `NSCursor hide/unhide`, Mausbewegung aus `NSEvent deltaX/deltaY`.
- Achsen (Switch-Sixaxis, Controller flach): in Splatoon 3 neigt eine Drehrate um +x die Kamera
  nach unten, um +z dreht sie nach links; Hochzielen meldet daher −x, Rechtsdrehen −z. Im Spiel
  per `NX_AUTOINPUT` geprüft (Läufe 92–94, `SPLATOON3_PROFILE.md`).
- `NX_TRACE_MOTION=1` (Patch 0036) protokolliert die geschriebenen Sensorwerte, solange er sich dreht.

## Noch nicht geprüft
- Das Einfangen mit echter Maus (M/Esc, Maustasten) ist gebaut, aber nur per Skript-Zielen im Spiel
  getestet, nicht mit physischer Mausbewegung.
- Die Neigung ist im Host auf ±80° begrenzt; das Spiel begrenzt die Kamera früher. Weiteres Hochziehen
  über die Grenze hinaus wird verworfen, Runterziehen wirkt sofort.
