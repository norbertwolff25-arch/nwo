# Reisemanager

Lokale macOS-App für Dienstreisen und Sachkosten: Zahlungen und Belege einsammeln, Reisen erkennen, Belege zuordnen, Lücken finden und Abrechnungen in SAP Concur als Entwurf vorbereiten. Eingereicht wird nie von der App.

**Stand: Etappe 2 von 5 – Datenmodell und Import.** Es gibt den Kern als Swift-Paket und eine Kommandozeile. Plausi-Prüfer, SwiftUI-Oberfläche und Concur-Anbindung folgen.

## Persönliche Daten

Dieses Repository enthält nur Code und erfundene Testdaten. Privatadresse, Concur-Kopfdaten, Zahlungen, Belege und der Startbestand liegen ausschließlich lokal:

| Datei | Inhalt | Vorlage |
|---|---|---|
| `einstellungen.json` | Privatadresse, Concur-Kopfdaten, Belegordner | `beispiel/einstellungen.beispiel.json` |
| `startbestand.json` | Reisen, Positionen, Sachkosten, Belegverzeichnis aus der Arbeitsmappe | entsteht mit `werkzeuge/mappe_zu_startbestand.py` |
| `startbestand-zusatz.json` | Concur-Entwürfe, offene Punkte, persönliche Regeln | `beispiel/startbestand-zusatz.beispiel.json` |

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

Die Datenbank liegt unter `~/Library/Application Support/Reisemanager/reisemanager.sqlite`. Ein anderer Ort geht über `--db <Pfad>` oder `REISEMANAGER_DB`. Jeder Import darf wiederholt werden, bekannte Einträge entstehen nicht doppelt.

## Was der Kern kann

- **Datenmodell** (SQLite über GRDB): Zahlung mit allen Fundstellen, Reise, Reiseabschnitt, Position, Sachkostenabrechnung, Beleg, Belegbild, Regel, Entscheidung, offener Punkt.
- **Importe:** NWO-Pay-CSV, Amex `activity.csv`, PayPal-Export, Startbestand, Belegordner.
- **Dubletten:** Ein Amex-Umsatz, der schon aus NWO-Pay bekannt ist, ergänzt nur Kartendaten. Eine PayPal-Zahlung, die NWO-Pay schon kennt, wird nicht neu angelegt. Belegbilder mit gleichem Inhalt gelten als Dublette.
- **Paarung PayPal ↔ Amex:** gleicher Betrag, Datum ±3 Tage, Händler. Jedes Paar trägt die Stufe „sicher“ oder „wahrscheinlich“. Bei mehreren Kandidaten ohne Händlertreffer wird nicht gepaart.
- **Fremdwährung:** Fremdbetrag und Euro-Betrag stehen getrennt. Fehlt der Euro-Betrag, bleibt das Feld leer.
- **Abrechnungstitel:** Muster `<Anlass> <Ort> TT.-TT.MM.JJ`, höchstens 32 Zeichen. Zu lange Titel werden gemeldet, nicht gekürzt.
- **Regeln als Daten:** Persönliche Regeln wie „Anlass enthält <Ort> = Einsatz beim Stammkunden“ stehen in der lokalen Datei, nicht im Code. Jede Anwendung wird mit Regel und Sicherheitsstufe protokolliert.
- **Summen** je Reise im Aufbau der Arbeitsmappe (Fahrt, Unterkunft, Sonstiges). Privatreisen gehen in keine Summe ein.

Grundsatz: keine erfundenen Werte. Unlesbare Zeilen meldet der Import mit Zeilennummer, fehlende Beträge bleiben leer und zählen als offene Punkte.

## Noch nicht gegen echte Dateien geprüft

- PayPal-Export: Die Spaltennamen folgen dem deutschen Standardexport. Die Zuordnung der Euro-Beträge über die Zeilen „Währungsumrechnung“ ist nur mit erfundenen Daten getestet.
- Amex-Fremdwährung: gelesen wird das Muster „Foreign Spend Amount: … Commission Amount: …“ aus der Spalte „Weitere Details“.
- Texterkennung der Belegbilder (Apple Vision) kommt mit der Oberfläche, weil sie nur auf dem Mac läuft.

## Aufbau

```
Sources/ReisemanagerKern/   Kern ohne Oberfläche
  Grundlagen/               Datum, Geld in Cent, CSV, SHA-256
  Modell/                   Datensätze und Aufzählungen
  Datenbank/                Schema und Migration
  Import/                   Importe und Paarung
  Regeln/                   Abrechnungstitel, Einstellungen
  Auswertung/               Summen
Sources/reisemanager/       Kommandozeile
Tests/                      Tests mit erfundenen Daten
werkzeuge/                  Python-Hilfsskript, zusätzlich als .txt-Lesefassung
beispiel/                   Vorlagen für die lokalen Dateien
```
