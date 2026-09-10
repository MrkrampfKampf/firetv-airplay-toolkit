# firetv-airplay-toolkit

**AirPlay auf dem Fire TV Stick zum Laufen bringen. Einfach den Schritten folgen.**

> Deutsche Fassung. Die englische Hauptanleitung steht in [README.md](README.md).

Den Bildschirm von iPhone, iPad oder Mac auf einen Fire TV Stick spiegeln, mit
Bild und Ton. Ohne Apple TV, ohne Kauf-App, ohne Abo.

Fire TV kann AirPlay von sich aus nicht. Diese Anleitung bringt einen quelloffenen
AirPlay-2-Empfänger auf deinen Stick und dauert etwa zehn Minuten.

> [!IMPORTANT]
> **Dieses Repository ist die Installationshilfe, nicht der Empfänger.** Die
> eigentliche AirPlay-Arbeit macht
> [jqssun/android-airplay-server](https://github.com/jqssun/android-airplay-server)
> auf Basis von [UxPlay](https://github.com/FDH2/UxPlay). Beide stehen unter
> GPL-3.0 und stammen von anderen Leuten. Von hier kommen die Windows-Skripte, die
> Geräterecherche und diese Anleitung.

## Was du vorher brauchst

* Einen Fire TV Stick, siehe [Schritt 1](#schritt-1--prüfen-ob-dein-fire-tv-stick-mitmacht)
* Einen Windows-10- oder -11-PC mit installiertem [Git](https://git-scm.com/download/win)
* Fire TV Stick und Apple-Gerät im **selben WLAN**
* Kein Gäste-WLAN, und AP-Isolation im Router ausgeschaltet

Der letzte Punkt ist der häufigste Stolperstein. Wenn sich Handy und Stick im Netz
nicht sehen können, findet AirPlay nichts, ganz egal was installiert ist.

## Schritt 1 — Prüfen ob dein Fire TV Stick mitmacht

Such dein Modell in der Tabelle. Alles mit „ja" funktioniert.

| Dein Fire TV Stick | Fire OS | Läuft |
|---|---|:-:|
| Fire TV Stick HD, 2024 | 7 | ja |
| Fire TV Stick Lite, 2020 | 7 | ja |
| Fire TV Stick 3. Generation, 2020 | 7 | ja |
| Fire TV Stick 4K, 2018 | 6 | ja |
| Fire TV Stick 4K Max | 7 oder 8 | ja |
| Fire TV Cube, 2. oder 3. Generation | 7 oder 8 | ja |
| Fire TV Stick 1. Generation, 2014 | 5 | nein |
| Fire TV Stick 2. Generation, 2016 | 5 | nein |
| Fire TV Stick 4K Select, 2025 | Vega OS | nein |

Warum die drei nicht gehen:

* Die **Sticks von 2014 und 2016** laufen mit Fire OS 5, also Android 5.1. Die App
  braucht mindestens Android 7.0, die Installation scheitert deshalb sofort.
* Der **Fire TV Stick 4K Select von 2025** läuft mit Amazons Vega OS. Das ist kein
  Android und führt überhaupt keine Android-Apps aus. Dagegen hilft nichts.

Bestätigt läuft es auf einem Fire TV Stick HD von 2024 mit Fire OS 7.

Du weißt nicht, welches Modell du hast? Es steht unter `Einstellungen`, dann
`Mein Fire TV`, dann `Info`.

## Schritt 2 — ADB auf dem Fire TV Stick einschalten

Am Fernseher, mit der Fernbedienung:

1. `Einstellungen` öffnen
2. Zu `Mein Fire TV` gehen
3. `Entwickleroptionen` öffnen
4. **ADB-Debugging** auf An stellen

Fehlen die `Entwickleroptionen`, dann `Einstellungen`, `Mein Fire TV`, `Info`
öffnen, den Gerätenamen markieren und sieben Mal die Auswahltaste drücken. Danach
ist das Menü da.

## Schritt 3 — Die IP-Adresse deines Fire TV Sticks finden

Weiter am Fernseher:

1. `Einstellungen` öffnen
2. Zu `Mein Fire TV` gehen
3. `Info` öffnen
4. `Netzwerk` auswählen

Notier dir die Angabe bei **IP-Adresse**. Sie besteht aus vier durch Punkte
getrennten Zahlen. Du brauchst sie in Schritt 7.

## Schritt 4 — Repository auf den PC holen

PowerShell auf dem PC öffnen und ausführen:

```powershell
git clone --recursive https://github.com/MrkrampfKampf/firetv-airplay-toolkit.git
```

```powershell
cd firetv-airplay-toolkit
```

Das `--recursive` ist wichtig. Ohne bleibt der Ordner `airplay-server` leer.

## Schritt 5 — adb installieren

`adb` ist das Werkzeug, das über das Netzwerk mit dem Stick redet. Das hier lädt
es herunter, etwa 8 MB, in einen Ordner `toolchain` im Repository:

```powershell
.\scripts\00a-get-adb.ps1
```

Es wird nichts systemweit installiert und nichts in der Registry verändert.

## Schritt 6 — Die Empfänger-App herunterladen

```powershell
.\scripts\00-get-prebuilt-apk.ps1
```

Das holt die Veröffentlichung des Upstream-Entwicklers, dieselbe Fassung, die auch
F-Droid ausliefert, und vergleicht deren SHA-256 mit dem Wert, den GitHub für die
Datei angibt. Die App landet im Ordner `dist`.

Lieber selbst kompilieren? Dann weiter beim
[optionalen Abschnitt](#optional--die-app-selbst-bauen) und danach zurück zu
Schritt 7.

## Schritt 7 — Die App auf dem Fire TV Stick installieren

```powershell
.\scripts\03-sideload-firetv.ps1
```

Das Skript fragt nach der IP-Adresse aus Schritt 3. Eintippen, Enter drücken.

**Jetzt auf den Fernseher schauen.** Beim ersten Verbinden erscheint dort eine
Rückfrage, ob Debugging von deinem Computer erlaubt sein soll. Mit der
Fernbedienung bestätigen. Wenn das Skript `unauthorized` meldet, wartet es genau
darauf. Bestätigen und das Skript erneut starten.

Danach zeigt das Skript, welches Gerät es gefunden hat, installiert die App und
startet sie.

## Schritt 8 — iPhone, iPad oder Mac spiegeln

Die App läuft jetzt auf dem Fernseher und wartet.

Auf **iPhone oder iPad**: Kontrollzentrum aufziehen, auf
`Bildschirmsynchronisierung` tippen, den Empfänger aus der Liste wählen.

Auf dem **Mac**: Kontrollzentrum in der Menüleiste öffnen, auf
`Bildschirmsynchronisierung` klicken, den Empfänger wählen.

Fertig. Dein Bildschirm erscheint auf dem Fernseher, mit Ton.

Die App liegt außerdem auf dem Fire-TV-Startbildschirm bei deinen Apps. Beim
nächsten Mal kannst du sie einfach von dort starten.

## Optional — Die App selbst bauen

Lohnt nur, wenn du einen eigenen Signaturschlüssel willst oder einen Build, den du
Zeile für Zeile nachvollziehen kannst. Dabei wird eine komplette Android-Toolchain
geladen, das dauert.

```powershell
.\scripts\01-setup-toolchain.ps1 -AcceptSdkLicenses
```

```powershell
.\scripts\02-build-apk.ps1
```

Danach normal mit Schritt 7 weitermachen.

| | |
|---|---|
| Downloads | etwa 3 GB, nämlich JDK 21, Android SDK, NDK 27 und CMake |
| Speicherplatz | etwa 12 GB |
| Erster Build | 30 bis 120 Minuten, überwiegend FFmpeg und OpenSSL |
| Späterer Build | wenige Minuten |

Alles landet in einem Ordner `toolchain` im Repository. Wenn auf dem Systemlaufwerk
wenig Platz ist, leg es woanders ab:

```powershell
.\scripts\01-setup-toolchain.ps1 -AcceptSdkLicenses -ToolchainRoot E:\android-toolchain
```

Der Schalter `-AcceptSdkLicenses` ist Absicht. Das Android SDK zu installieren
bedeutet, [Googles SDK-Bedingungen](https://developer.android.com/studio/terms)
zuzustimmen, und diese Zustimmung soll von dir kommen und nicht stillschweigend
von einem Skript.

Standardmäßig werden beide ARM-Architekturen gebaut. Nur eine zu nennen halbiert
die Bauzeit etwa, und jeder Fire TV Stick bis zum 4K Max ist 32-Bit:

```powershell
.\scripts\02-build-apk.ps1 -Abis armeabi-v7a
```

Beim ersten Build entsteht ein Signaturschlüssel im Ordner `keystore`. Behalte
ihn. Android erlaubt das Aktualisieren einer installierten App nur bei gleicher
Signatur, ohne den Schlüssel müsstest du vorher deinstallieren.

## Was nicht funktioniert

* **Alles was durch DRM geschützt ist.** Netflix, Disney+, Prime Video, die
  Apple-TV-App und jede Website, die über FairPlay oder Widevine ausliefert. Der
  Empfänger enthält keinerlei DRM-Unterstützung. Beim Spiegeln würde sie auch
  nichts nützen: iPhone und Mac schwärzen die geschützte Videoebene, bevor sie
  überhaupt etwas senden, diese Bilder erreichen den Fernseher also nie. Die
  Einschränkung sitzt im sendenden Gerät, nicht hier. Nur ein echtes Apple TV kann
  solche Inhalte zeigen. Zu erwarten ist ein schwarzes Bild, oft mit weiterhin
  hörbarem Ton, oder gar nichts.
* **Schnelle Spiele.** Spiegeln erzeugt merkliche Verzögerung. Für Video, Fotos,
  Präsentationen und Surfen ist das kein Problem.
* **Ruckelfreies 1080p60 auf Einstiegssticks.** Die haben 1 GB RAM und kaum
  Reserven beim Dekodieren. Bei Rucklern in den App-Einstellungen Auflösung oder
  Bildrate senken.

## Was du stattdessen tun kannst, wenn eine App blockiert

Spiegeln ist für geschütztes Video das falsche Werkzeug. Es gibt einen besseren
Weg, und der liefert ein schärferes Bild als Spiegeln je könnte.

**Installier die App des Anbieters direkt auf dem Fire TV.** Netflix, Disney+,
Prime Video, YouTube und die meisten großen Sender haben Fire-TV-Apps im
Amazon-Appstore. Der Stick spielt den Stream dann selbst ab, mit funktionierendem
DRM, voller Auflösung und ohne die Verzögerung des Spiegelns. Such den Anbieter
auf dem Fire-TV-Startbildschirm und installier ihn dort. Das Handy brauchst du nur
noch zum Suchen und Tippen, über Amazons Fire-TV-Fernbedienungs-App.

Das ist kein Trostpreis. Bei nativer Wiedergabe dekodiert der Stick den
Originalstream, beim Spiegeln wird dein Handybildschirm neu kodiert und über WLAN
geschoben. Die native App gewinnt bei der Qualität immer.

**Für eine Website ohne Fire-TV-App** öffne die Seite im Silk Browser auf dem
Stick selbst, den es im Amazon-Appstore gibt. Normales HTML5-Video läuft meist.
Seiten mit DRM verweigern trotzdem oft, gehen auf niedrige Qualität herunter oder
nicht in den Vollbildmodus, weil sie eine eigene App erwarten. Ein Versuch lohnt,
eine Garantie ist es nicht.

**Für Video ohne Kopierschutz** nimm den AirPlay-Knopf im Videoplayer statt der
Bildschirmsynchronisierung. Dein Gerät übergibt dann nur die Adresse des Streams,
und der Empfänger holt und dekodiert ihn selbst. Das ist schärfer als Spiegeln und
belastet dein Handy kaum.

**Für alles andere, was scheitert**, führ die Diagnose im nächsten Abschnitt aus.
Sie unterscheidet einen geschützten Stream von einem echten Fehler.

## Wenn etwas nicht klappt

| Was du siehst | Was zu tun ist |
|---|---|
| Der Empfänger erscheint nicht am iPhone | Beide Geräte ins selbe WLAN. Kein Gäste-WLAN. AP-Isolation im Router abschalten. |
| Das Skript meldet `unauthorized` | Die Rückfrage am Fernseher mit der Fernbedienung bestätigen, dann Skript neu starten. |
| Das Skript meldet `offline` | Stick neu starten über `Einstellungen`, `Mein Fire TV`, `Neu starten`. |
| Installation scheitert mit Signaturfehler | Eine ältere Version mit anderem Schlüssel ist installiert. `adb uninstall io.github.jqssun.airplay` ausführen, dann neu installieren. |
| `INSTALL_FAILED_OLDER_SDK` | Dein Stick läuft mit Fire OS 5. Siehe Schritt 1, dieses Modell kann die App nicht ausführen. |
| Das Bild ruckelt oder reißt | In den App-Einstellungen am Fernseher Auflösung oder Bildrate senken. |
| Ein bestimmtes Video läuft nicht und du willst wissen warum | Die Diagnose unten ausführen. |

### Herausfinden, warum ein Video nicht läuft

Manche Videos scheitern an behebbaren Ursachen, andere daran, dass sie geschützt
sind. Das hier sagt dir, welcher Fall vorliegt:

```powershell
.\scripts\04-diagnose-playback.ps1 -Label name-der-website
```

Das Skript zeichnet den Empfänger auf, während du das Problem nachstellst, und
sortiert das Ergebnis nach geschütztem Inhalt, verweigerndem Decoder oder
Netzwerkfehler. Das vollständige Protokoll liegt in `logs`, das von Git
ausgeschlossen ist, weil darin die besuchten Adressen stehen können.

Findet die Diagnose gar nichts, ist das schon die Antwort: es kamen keine Bilder
an, und genau so sieht geschütztes Video aus der Sicht des Empfängers aus.

Mitlesen, was der Empfänger beim Spiegeln tut:

```powershell
adb logcat -s AirPlay:V *:S
```

## Was die Skripte tun

| Skript | Aufgabe |
|---|---|
| `00a-get-adb.ps1` | Lädt nur adb, etwa 8 MB, ohne systemweite Installation |
| `00-get-prebuilt-apk.ps1` | Holt die Upstream-App und prüft deren Checksumme |
| `01-setup-toolchain.ps1` | Installiert JDK 21, Android SDK, NDK 27 und CMake zum Bauen |
| `02-build-apk.ps1` | Kompiliert die App und signiert sie mit einem erzeugten Schlüssel |
| `03-sideload-firetv.ps1` | Verbindet sich mit dem Stick, installiert die App und startet sie |
| `04-diagnose-playback.ps1` | Zeichnet den Empfänger bei einem Fehler auf und nennt die Ursache |

Jedes Skript lässt sich gefahrlos erneut ausführen. Vorhandene Downloads werden
weiterverwendet, fertige Arbeit wird nicht wiederholt.

## Danksagung

* [UxPlay](https://github.com/FDH2/UxPlay) von FDH2 und Mitwirkenden, die AirPlay- und RAOP-Umsetzung
* [android-airplay-server](https://github.com/jqssun/android-airplay-server) von jqssun, die Android-App und die JNI-Brücke
* [FFmpeg](https://ffmpeg.org) für die verlustfreie Audiodekodierung
* Modell- und API-Angaben aus [Amazons Fire-TV-Gerätespezifikationen](https://developer.amazon.com/docs/device-specs/device-specifications-fire-tv-streaming-media-player.html)

## Lizenz

GPL-3.0, passend zu den Upstream-Projekten, die dieses Toolkit baut. Siehe
[LICENSE](LICENSE).

Der Ordner `airplay-server` ist ein Submodul, das auf den Upstream-Code unter
dessen eigenem Urheberrecht zeigt. Er ist auf einen festen Commit gepinnt und
nicht hierher kopiert, und dieses Repository liefert keine Binärdateien aus. Wer
eine mit diesen Skripten gebaute App weitergibt, muss laut GPL-3.0 auch den
zugehörigen Quellcode zugänglich machen.

---

Steht in keiner Verbindung zu Apple Inc. oder Amazon.com, Inc. AirPlay ist eine
Marke von Apple Inc. Fire TV ist eine Marke von Amazon.com, Inc.
