# Reisemanager

Lokale macOS-App für Dienstreisen und Sachkosten: Zahlungen und Belege einsammeln, Reisen erkennen, Belege zuordnen, Lücken finden und Abrechnungen in SAP Concur als Entwurf vorbereiten. Eingereicht wird nie von der App.

**Stand: Etappe 3 von 5 – Reiseerkennung und Plausi-Prüfer.** Es gibt den Kern als Swift-Paket und eine Kommandozeile. SwiftUI-Oberfläche und Concur-Anbindung folgen.

## Persönliche Daten

Dieses Repository enthält nur Code und erfundene Testdaten. Privatadresse, Concur-Kopfdaten, Zahlungen, Belege und der Startbestand liegen ausschließlich lokal:

| Datei | Inhalt | Vorlage |
|---|---|---|
| `einstellungen.json` | Privatadresse, Concur-Kopfdaten, Belegordner | `beispiel/einstellungen.beispiel.json` |
| `startbestand.json` | Reisen, Positionen, Sachkosten, Belegverzeichnis aus der Arbeitsmappe | entsteht mit `werkzeuge/mappe_zu_startbestand.py` |
| `startbestand-zusatz.json` | Concur-Entwürfe, offene Punkte, persönliche Regeln | `beispiel/startbestand-zusatz.beispiel.json` |
| `ereignisse.json` | Reiseverläufe mit Uhrzeiten, Hotelaufenthalte, Termine | `beispiel/ereignisse.beispiel.json` |

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
```

Die Datenbank liegt unter `~/Library/Application Support/Reisemanager/reisemanager.sqlite`. Ein anderer Ort geht über `--db <Pfad>` oder `REISEMANAGER_DB`. Jeder Import darf wiederholt werden, bekannte Einträge entstehen nicht doppelt.

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
- **Summen** je Reise im Aufbau der Arbeitsmappe (Fahrt, Unterkunft, Sonstiges). Privatreisen gehen in keine Summe ein.

Grundsatz: keine erfundenen Werte. Unlesbare Zeilen meldet der Import mit Zeilennummer, fehlende Beträge bleiben leer und zählen als offene Punkte.

## Noch nicht gegen echte Dateien geprüft

- PayPal-Export: Die Spaltennamen folgen dem deutschen Standardexport. Die Zuordnung der Euro-Beträge über die Zeilen „Währungsumrechnung“ ist nur mit erfundenen Daten getestet.
- Amex-Fremdwährung: gelesen wird das Muster „Foreign Spend Amount: … Commission Amount: …“ aus der Spalte „Weitere Details“.
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
  Auswertung/               Summen
Sources/reisemanager/       Kommandozeile
Tests/                      Tests mit erfundenen Daten
werkzeuge/                  Python-Hilfsskript, zusätzlich als .txt-Lesefassung
beispiel/                   Vorlagen für die lokalen Dateien
```
