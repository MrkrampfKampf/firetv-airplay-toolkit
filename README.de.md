# AirPlay-Empfänger für Fire TV Stick

> Deutsche Fassung. Die englische Hauptdokumentation steht in [README.md](README.md).

Baut eine sideloadbare APK, die einen Fire TV Stick in einen vollwertigen
AirPlay-2-Empfänger verwandelt: Screen Mirroring, Video, Audio.

## Was hier drin ist

| Pfad | Inhalt |
|---|---|
| `airplay-server/` | Git-Submodul mit dem Upstream-Code: [jqssun/android-airplay-server](https://github.com/jqssun/android-airplay-server), GPL-3.0 |
| `scripts/00-get-prebuilt-apk.ps1` | Schneller Weg: fertige, vom Maintainer signierte APK holen |
| `scripts/00a-get-adb.ps1` | Nur ADB, 8 MB, das Minimum fürs Sideloaden |
| `scripts/01-setup-toolchain.ps1` | JDK 21 + Android SDK + NDK 27 + CMake nach `D:\android-toolchain` |
| `scripts/02-build-apk.ps1` | Selbst bauen und signieren |
| `scripts/03-sideload-firetv.ps1` | Per ADB auf den Stick installieren und starten |
| `dist/` | Fertige APKs (wird angelegt) |

## Warum dieses Projekt und keine Eigenentwicklung

AirPlay-Mirroring ist nicht frei implementierbar. Der Sender verlangt einen
FairPlay-Handshake, dessen Schlüssel aus der Apple-TV-Firmware stammen. Die
einzige funktionierende freie Umsetzung ist **UxPlay**, geschrieben in C.

Genau das nutzt dieses Projekt: UxPlay als natives Modul plus JNI-Brücke in eine
Android-App. Deshalb braucht der Build das NDK und deshalb funktioniert es
wirklich, statt nur die Geräteerkennung hinzubekommen.

## Gerätekompatibilität

Entscheidend sind drei Dinge: das API-Level (die App verlangt mindestens 24),
die CPU-Architektur und ob überhaupt Android läuft.

| Modell | Kennung | Fire OS | API | ABI | Läuft? |
|---|---|---|---|---|---|
| Fire TV Stick HD, 2024 | AFTSS | Fire OS 7 (Android 9) | 28 | armeabi-v7a | ja |
| Fire TV Stick Lite / 3. Gen, 2020 | AFTSSS / AFTKA | Fire OS 7 (Android 9) | 28 | armeabi-v7a | ja |
| Fire TV Stick 4K, 2018 | AFTMM | Fire OS 6 (Android 7.1) | 25 | armeabi-v7a | ja |
| Fire TV Stick 4K Max | AFTKMST12 | Fire OS 7/8 | 28/30 | arm64-v8a | ja |
| Fire TV Stick 1. Gen, 2014 | AFTM | Fire OS 5 (Android 5.1) | 22 | armeabi-v7a | **nein**, unter minSdk 24 |
| Fire TV Stick 2. Gen, 2016 | AFTT | Fire OS 5 (Android 5.1) | 22 | armeabi-v7a | **nein**, unter minSdk 24 |
| Fire TV Stick 4K Select, 2025 | AFTCA002 | **Vega OS** | kein Android | – | **nein**, führt keine APKs aus |

Der Fire TV Stick HD von 2024 ist der Zielfall hier: Android 9, 32-Bit, und
H.264 sowie HEVC werden bis 1080p60 in Hardware dekodiert. Mit 1 GB RAM ist er
allerdings knapp bestückt. Wenn das Bild ruckelt, in den App-Einstellungen auf
720p oder 1080p30 heruntergehen.

Welches Gerät wirklich vorliegt, sagt der Stick selbst:

```powershell
adb -s 192.168.1.42:5555 shell getprop ro.product.model
adb -s 192.168.1.42:5555 shell getprop ro.build.version.sdk
adb -s 192.168.1.42:5555 shell getprop ro.product.cpu.abi
```

## Voraussetzungen

* Fire TV Stick und Apple-Gerät im **selben Subnetz**, kein Gäste-WLAN
* AP-Isolation im Router aus, sonst scheitert die mDNS-Erkennung
* Geklont wird mit Submodul: `git clone --recursive`, sonst bleibt `airplay-server/` leer
* Auf dem Stick: `Einstellungen` → `Mein Fire TV` → `Entwickleroptionen` →
  `ADB-Debugging` einschalten
* IP des Sticks: `Einstellungen` → `Mein Fire TV` → `Info` → `Netzwerk`

Zum Selbstbauen zusätzlich rund 12 GB Platz und ein Git, das schon installiert ist.

## Weg A: fertige APK (Minuten)

```powershell
.\scripts\00-get-prebuilt-apk.ps1
.\scripts\03-sideload-firetv.ps1 -FireTvIp 192.168.1.42
```

Die APK ist die Release-Binary des Maintainers, identisch zu der auf F-Droid.
Sie enthält alle drei ABIs und läuft auf jeder Stick-Generation.

## Weg B: aus dem Quellcode bauen (Stunden)

```powershell
.\scripts\01-setup-toolchain.ps1 -AcceptSdkLicenses
.\scripts\02-build-apk.ps1
.\scripts\03-sideload-firetv.ps1 -FireTvIp 192.168.1.42
```

Der erste Durchlauf kompiliert FFmpeg und OpenSSL nativ, das dauert 45 bis 120
Minuten. Danach sind Rebuilds schnell. Standardmäßig werden nur `arm64-v8a` und
`armeabi-v7a` gebaut, weil es keine x86-Fire-TVs gibt. Bei einem 32-Bit-Stick
wie dem HD von 2024 reicht eine Architektur, das halbiert die Build-Zeit:

```powershell
.\scripts\02-build-apk.ps1 -Abis armeabi-v7a
```

Beim ersten Lauf entsteht ein eigener Signaturschlüssel unter `keystore\`.
Der muss erhalten bleiben, sonst lässt sich die App später nicht mehr über die
installierte Version aktualisieren.

## Benutzung auf dem Apple-Gerät

Nach dem Start lauscht die App auf dem Stick. Am iPhone oder iPad
`Kontrollzentrum` → `Bildschirmsynchronisierung` öffnen und den Empfänger
auswählen. Am Mac dasselbe über das Kontrollzentrum.

## Grenzen

* **DRM-Inhalte gehen nicht.** Netflix, Disney+ oder die Apple-TV-App
  verweigern die Ausgabe. Das ist keine Lücke im Build, sondern Absicht des
  Senders. Kein AirPlay-Empfänger außer einem echten Apple TV kann das.
* Mirroring erzeugt Latenz. Für Videos und Fotos ist das egal, für schnelle
  Spiele nicht.
* Ältere Sticks dekodieren 1080p60 nur knapp. Im App-Menü lassen sich Auflösung
  und Framerate senken.

## Fehlersuche

| Symptom | Ursache |
|---|---|
| Empfänger taucht am iPhone nicht auf | anderes Subnetz, Gäste-WLAN oder AP-Isolation |
| `adb devices` zeigt `unauthorized` | Dialog auf dem Fernseher mit der Fernbedienung bestätigen |
| `adb devices` zeigt `offline` | Stick neu starten |
| Installation scheitert mit Signaturfehler | vorher `adb uninstall io.github.jqssun.airplay` |
| Bild ruckelt | Auflösung oder Framerate in den App-Einstellungen senken |

Live-Log mitlesen:

```powershell
adb -s 192.168.1.42:5555 logcat -s AirPlay:V *:S
```

## Lizenz

Der Quellcode unter `airplay-server/` steht unter GPL-3.0 und stammt nicht von
mir. Die Skripte hier drumherum sind reine Build-Automatisierung. Wer die
gebaute APK weitergibt, muss den Quellcode mitliefern.
