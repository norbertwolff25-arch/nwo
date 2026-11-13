# Reisemanager

Lokale macOS-App für Dienstreisen und Sachkosten: Zahlungen und Belege einsammeln, Reisen erkennen, Belege zuordnen, Lücken finden und Abrechnungen in SAP Concur als Entwurf vorbereiten. Eingereicht wird nie von der App.

**Stand: Etappe 5 von 5 begonnen – Concur.** Es gibt den Kern als Swift-Paket, eine Kommandozeile, eine SwiftUI-App und den Concur-Teil bis zur Vorschau. Die Browserschritte gegen das echte Concur sind noch nicht abgebildet.

> Die SwiftUI-App ist unter Linux geschrieben und dort nur auf Syntax geprüft. Der erste Bau auf dem Mac steht aus und kann Korrekturen brauchen. Kern und Kommandozeile sind gebaut und getestet.

## Persönliche Daten

Dieses Repository enthält nur Code und erfundene Testdaten. Privatadresse, Concur-Kopfdaten, Zahlungen, Belege und der Startbestand liegen ausschließlich lokal:

| Datei | Inhalt | Vorlage |
|---|---|---|
| `einstellungen.json` | Privatadresse, Concur-Kopfdaten, Belegordner | `beispiel/einstellungen.beispiel.json` |
| `startbestand.json` | Reisen, Positionen, Sachkosten, Belegverzeichnis aus der Arbeitsmappe | entsteht mit `werkzeuge/mappe_zu_startbestand.py` |
| `startbestand-zusatz.json` | Concur-Entwürfe, offene Punkte, persönliche Regeln | `beispiel/startbestand-zusatz.beispiel.json` |
| `ereignisse.json` | Reiseverläufe mit Uhrzeiten, Hotelaufenthalte, Termine | `beispiel/ereignisse.beispiel.json` |
| `concur-bestand.json` | gelesener Concur-Stand: Abrechnungen und verfügbare Ausgaben | `beispiel/concur-bestand.beispiel.json` |

`.gitignore` schließt diese Dateien und die Datenbank aus. Kartennummern werden nie gespeichert, nur die letzten vier Ziffern.

## Bauen und testen

Voraussetzung: Swift 6 (Xcode 16 oder neuer). Der Kern baut auch unter Linux.

```sh
cd reisemanager
swift test
swift build
```

## Erster Lauf

```sh
# Startbestand aus der Arbeitsmappe erzeugen (braucht Python mit openpyxl)
python3 werkzeuge/mappe_zu_startbestand.py Reisen_2026.xlsx lokal/startbestand.json

# Einlesen: erst die Mappe, dann Concur-Entwürfe und offene Punkte
swift run reisemanager import startbestand lokal/startbestand.json lokal/startbestand-zusatz.json

# Zahlungen und Belege
swift run reisemanager import nwopay NWO_Pay_2026_Zahlungen.csv
swift run reisemanager import amex activity.csv
swift run reisemanager import paypal paypal.csv
swift run reisemanager import belege ~/Pfad/zum/Belegordner

swift run reisemanager status
```

## App starten (nur macOS)

```sh
mkdir -p ~/Library/Application\ Support/Reisemanager
cp lokal/einstellungen.json ~/Library/Application\ Support/Reisemanager/
swift run ReisemanagerApp
```

Die App nutzt dieselbe Datenbank wie die Kommandozeile.

- **Dashboard:** alle Reisen und Sachkosten mit Ampel, Summe, Status und Concur-Nummer.
- **Reise:** Beginn und Ende mit Quelle und Sicherheitsstufe, Nachfragen als Schaltflächen, Befunde, Positionen mit Belegbild-Ampel, Besorgungsliste, offene Punkte, Status.
- **Drag & Drop:** Eine Position auf eine andere Reise oder Sachkostenabrechnung in der Seitenleiste ziehen.
- **Vorschläge:** übernehmen, anderer Reise zuordnen, als privat merken oder verwerfen.
- **Was ich noch besorgen muss:** nach Fundort gruppiert.
- **Einlesen:** alle Importe über den Dateidialog, mit Protokoll.
- **Bericht speichern:** Kurzbericht je Reise als Markdown. Die PDF-Fassung folgt.

## Erkennen und prüfen

```sh
export REISEMANAGER_EINSTELLUNGEN=lokal/einstellungen.json

# Reiseverläufe, Hotelaufenthalte und Termine einlesen
swift run reisemanager import ereignisse lokal/ereignisse.json

# Beginn und Ende vorbelegen, Zahlungen zuordnen. Es entstehen nur Vorschläge.
swift run reisemanager erkennen
swift run reisemanager vorschlaege
swift run reisemanager annehmen 12            # Vorschlag übernehmen
swift run reisemanager annehmen 15 D09        # mit anderem Ziel
swift run reisemanager annehmen 17 --regel    # privat, und als Regel merken
swift run reisemanager ablehnen 18

# Plausi-Prüfer
swift run reisemanager pruefen                # alle Reisen und Sachkosten mit Ampel und Nachfragen
swift run reisemanager pruefen D10            # eine Reise mit allen Befunden
swift run reisemanager antwort D10:hotel 2    # Nachfrage beantworten
swift run reisemanager besorgen               # „Was ich noch besorgen muss“, nach Fundort
swift run reisemanager bericht D10 D10.md     # Kurzbericht als Markdown
```

Die Datenbank liegt unter `~/Library/Application Support/Reisemanager/reisemanager.sqlite`. Ein anderer Ort geht über `--db <Pfad>` oder `REISEMANAGER_DB`. Jeder Import darf wiederholt werden, bekannte Einträge entstehen nicht doppelt.

## Concur

Die App legt in Concur nur Entwürfe an und reicht nie ein. Die Anmeldung machst immer du.

```sh
swift run reisemanager import concur lokal/concur-bestand.json   # gelesenen Concur-Stand übernehmen
swift run reisemanager concur abgleich                           # eigene Positionen gegen Concur
swift run reisemanager concur plan D05                           # Vorschau der Schreibvorgänge, schreibt nichts
```

Feste Regeln, alle durch Tests belegt:

- **Kein Senden:** Die Schnittstelle `ConcurZugang` kennt nur Lesen und einzelne Schreibschritte. Einen Schritt „senden“ gibt es nicht.
- **Erst abgleichen:** Ohne gelesenen Concur-Stand ist jeder Plan gesperrt. Positionen, die schon in einer anderen Abrechnung stehen, etwa in „Ausgaben im Juli“, werden nicht noch einmal erfasst. Verfügbare Ausgaben werden zugeordnet statt neu angelegt.
- **Kein zweiter Entwurf:** Fehlt lokal die Concur-Nummer und liegt in Concur ein Entwurf mit demselben Titel, wird dessen Nummer übernommen.
- **Vorschau vor dem Schreiben:** Geschrieben wird nur ein Plan, dessen Vorschau bestätigt ist. Ändert sich der Plan, braucht er eine neue Bestätigung, außer im Modus „Stapel“.
- **Löschen** läuft nie über einen Plan, sondern nur einzeln mit ausdrücklicher Bestätigung.
- **Nichts geraten:** Die Namen der Concur-Ausgabentypen stehen in `einstellungen.json` unter `ausgabentypen`. Fehlt einer, ist der Plan gesperrt.

### Browserzugang (`concur/`)

```sh
cd concur && npm install && npx playwright install chromium
npm test                                   # Schutzregeln an einer nachgestellten Seite
node concur.js anmelden                    # öffnet EU2 und wartet auf deine Anmeldung
node concur.js erkunden seite.json         # nimmt die Bedienelemente einer Seite auf, ohne Feldinhalte
```

Das Skript klickt nie auf Senden oder Einreichen und füllt nie Passwort- oder MFA-Felder. Es nutzt ein eigenes Browserprofil unter `~/Library/Application Support/Reisemanager/concur-profil`.

Noch offen: Lesen der Abrechnungen und die Schreibschritte in der echten Concur-Oberfläche. Dafür müssen die Seiten einmal mit `erkunden` aufgenommen werden. Auswahlpfade werden nicht geraten.

## Was der Kern kann

- **Datenmodell** (SQLite über GRDB): Zahlung mit allen Fundstellen, Reise, Reiseabschnitt, Position, Sachkostenabrechnung, Beleg, Belegbild, Regel, Entscheidung, offener Punkt.
- **Importe:** NWO-Pay-CSV, Amex `activity.csv`, PayPal-Export, Startbestand, Belegordner.
- **Dubletten:** Ein Amex-Umsatz, der schon aus NWO-Pay bekannt ist, ergänzt nur Kartendaten. Eine PayPal-Zahlung, die NWO-Pay schon kennt, wird nicht neu angelegt. Belegbilder mit gleichem Inhalt gelten als Dublette.
- **Paarung PayPal ↔ Amex:** gleicher Betrag, Datum ±3 Tage, Händler. Jedes Paar trägt die Stufe „sicher“ oder „wahrscheinlich“. Bei mehreren Kandidaten ohne Händlertreffer wird nicht gepaart.
- **Fremdwährung:** Fremdbetrag und Euro-Betrag stehen getrennt. Fehlt der Euro-Betrag, bleibt das Feld leer.
- **Abrechnungstitel:** Muster `<Anlass> <Ort> TT.-TT.MM.JJ`, höchstens 32 Zeichen. Zu lange Titel werden gemeldet, nicht gekürzt.
- **Regeln als Daten:** Persönliche Regeln wie „Anlass enthält <Ort> = Einsatz beim Stammkunden“ stehen in der lokalen Datei, nicht im Code. Jede Anwendung wird mit Regel und Sicherheitsstufe protokolliert.
- **Vorbelegung von Beginn und Ende** in der Rangfolge Zugzeiten, Flugzeiten, Hotel, erste und letzte Uber-/Bolt-Fahrt, Kalender, Zahlungsdaten. Jeder Wert trägt Quelle und Sicherheitsstufe. Ein Wert wird nur ersetzt, wenn die neue Quelle verlässlicher ist. Daten aus der Arbeitsmappe weichen nur Fahrplanzeiten, bestätigte Werte bleiben immer stehen.
- **Zuordnungsvorschläge** für noch nicht zugeordnete Zahlungen: zur Reise im Zeitraum, privat (Privatreise, Hotel am Wohnort, gelernte Regel), Tanken in die Sachkostenabrechnung, mögliche neue Reise, vorab bezahltes Ticket ohne Reise. Übernommen wird erst nach Bestätigung. Eine Privat-Entscheidung lässt sich als Regel merken.
- **Plausi-Prüfer:** leitet den Reisetyp ab und prüft gegen dessen Soll-Belege. Er findet fehlende Tickets, Hotels und Anreisen, Hotelnächte gegen die Reisedauer, Zahlungen außerhalb des Zeitraums, Hotels am Wohnort, unpassende Orte, fehlende Beträge und fehlende Euro-Beträge. Nachfragen kommen gesammelt je Reise als Auswahlfragen.
- **Belegbild-Ampel** je Reise: grün (alle Belege mit Bild), gelb (Beleg oder Zahlung bekannt, Bild fehlt), rot (Position ohne Beleg oder Soll-Beleg fehlt). Bevorstehende Reisen werden höchstens gelb.
- **Liste „Was ich noch besorgen muss“** mit Fundort je Eintrag.
- **Wiedervorlage:** Hinweis bei Reisen, die länger als die Frist beendet und nicht eingereicht sind.
- **Lesesicht und Bearbeitung** für die Oberfläche: Dashboard-Zeilen, Reisedetail, Position verschieben, Status setzen, offene Punkte erledigen. Jede Änderung wird protokolliert.
- **Kurzbericht** je Reise als Markdown mit Reisedaten, Positionen, Befunden, Besorgungsliste und offenen Punkten.
- **Concur:** Abgleich mit bestehenden Abrechnungen und verfügbaren Ausgaben, Plan als Vorschau, Freigabe, Ausführung über eine gekapselte Schnittstelle mit Protokoll.
- **Summen** je Reise im Aufbau der Arbeitsmappe (Fahrt, Unterkunft, Sonstiges). Privatreisen gehen in keine Summe ein.

Grundsatz: keine erfundenen Werte. Unlesbare Zeilen meldet der Import mit Zeilennummer, fehlende Beträge bleiben leer und zählen als offene Punkte.

## Noch nicht gegen echte Dateien geprüft

- PayPal-Export: Die Spaltennamen folgen dem deutschen Standardexport. Die Zuordnung der Euro-Beträge über die Zeilen „Währungsumrechnung“ ist nur mit erfundenen Daten getestet.
- Amex-Fremdwährung: gelesen wird das Muster „Foreign Spend Amount: … Commission Amount: …“ aus der Spalte „Weitere Details“.
- Die SwiftUI-App: nicht gebaut, nicht gestartet.
- Concur: kein Schritt lief gegen das echte Concur. Die Ausführung ist nur gegen einen nachgestellten Zugang getestet.
- Zuordnungsvorschläge gegen die echte Zahlungsdatenbank. Die Händlererkennung arbeitet mit einer Wortliste und wird an den echten Daten nachzuschärfen sein.
- Texterkennung der Belegbilder (Apple Vision) kommt mit der Oberfläche, weil sie nur auf dem Mac läuft.

## Aufbau

```
Sources/ReisemanagerKern/   Kern ohne Oberfläche
  Grundlagen/               Datum, Geld in Cent, CSV, SHA-256
  Modell/                   Datensätze und Aufzählungen
  Datenbank/                Schema und Migration
  Import/                   Importe und Paarung
  Regeln/                   Abrechnungstitel, Einstellungen, Händlerklassen, Regelanwendung
  Erkennung/                Vorbelegung, Zuordnungsvorschläge
  Pruefung/                 Plausi-Prüfer
  Ansicht/                  Lesesicht, Bearbeitung und Bericht für die Oberfläche
  Concur/                   Abgleich, Plan, Freigabe, Ausführung, Schnittstelle
  Auswertung/               Summen
Sources/reisemanager/       Kommandozeile
Sources/ReisemanagerApp/    SwiftUI-App (nur macOS)
Tests/                      Tests mit erfundenen Daten
concur/                     Browserzugang mit Playwright (nur macOS) und seine Tests
werkzeuge/                  Python-Hilfsskript, zusätzlich als .txt-Lesefassung
beispiel/                   Vorlagen für die lokalen Dateien
```
