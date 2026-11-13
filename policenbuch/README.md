# Policenbuch

Native macOS-App (SwiftUI, SwiftData, macOS 15+) für die private Versicherungsverwaltung.
Alles bleibt lokal: kein Cloud-Sync, kein Server, keine Telemetrie, keine Fremdpakete.
Daten: `~/Library/Application Support/Policenbuch/Policenbuch.store`.

## Einrichten auf dem Mac

```sh
git clone policenbuch.bundle ~/Projekte/policenbuch   # aus dem Git-Bundle
cd ~/Projekte/policenbuch
open Policenbuch.xcodeproj                             # Xcode 16 oder neuer
```

Bauen und testen im Terminal:

```sh
cd PolicenbuchKern && swift test && cd ..
xcodebuild -project Policenbuch.xcodeproj -scheme Policenbuch -destination 'platform=macOS' test
```

Die App ist ad hoc signiert („Sign to Run Locally“), ohne Sandbox. Nur so kann sie beliebige PDF-Ordner lesen
und unter `Application Support/Policenbuch` speichern.

## Aufbau

| Teil | Inhalt |
|---|---|
| `PolicenbuchKern/` | Swift-Paket ohne UI: Datenmodell als Werttypen, CSV-Leser, Importe, Feldzuordnung, Dubletten, Prüfliste, Fristen, Dokumenterkennung, Export, ZIP. Läuft auch unter Linux. |
| `Policenbuch/Daten` | SwiftData-Modelle `Vertrag`, `Dokument`, `Zahlung`, `Aufgabe`, Speicherort, Importdienst |
| `Policenbuch/Dienste` | Texterkennung (PDFKit + Vision-OCR), Erinnerungen (UserNotifications) |
| `Policenbuch/Ansichten` | SwiftUI-Oberfläche |
| `PolicenbuchTests/` | App-Tests (Swift Testing, SwiftData im Speicher) |

## Importe

1. **Versicherungsbestand** `versicherungsbestand_*.csv`: Semikolon, UTF-8 mit BOM (Windows-1252 geht auch), Dezimalkomma.
   Spalten werden über Synonyme erkannt (z. B. „Gesellschaft“ → Versicherer, „VSNR“ → Vertragsnummer).
   Unbekannte Spalten landen als `Spalte: Wert` in den Notizen.
2. **Clark-DSGVO-Export** (JSON oder CSV): Die App sucht die Vertragsliste im JSON, flacht verschachtelte Felder ab
   (`insurer.name`) und schlägt eine Zuordnung vor. Im Mapping-Dialog lässt sich jedes Feld umstellen.
   Nicht zugeordnete Felder kommen in die Notizen. Felder wie `password`, `pin` oder `token` werden nie übernommen.
3. **NWO-Pay** (`pay_id;konto;art;datum;richtung;betrag;gegenpartei;zweck;…`): Ausgänge werden negativ gespeichert.
   Die Zuordnung läuft über die Vertragsnummer in Gegenpartei und Zweck, Leer- und Trennzeichen zählen nicht
   (`LV 123 456 78` = `LV-123.456.78`). Die Nummer braucht mindestens 5 Zeichen und muss als Ganzes vorkommen.
   Eine schon vorhandene `pay_id` wird übersprungen.
4. **PDF-Ordner**: rekursiv. Zuerst wird die Textebene gelesen (PDFKit), bei Scans der ersten 4 Seiten Vision-OCR (de-DE).
   Danach Vertragsnummer, Dokumenttyp und Datum erkennen. Gespeichert wird nur der Pfad, die Datei bleibt an ihrem Ort.
5. **Dubletten**: gleiche normalisierte Vertragsnummer und gleicher Versicherer (Rechtsform egal, erstes Wort reicht).
   Bei Unterschieden stehen Bestand und Import nebeneinander. Lösung je Vertrag: *Bestand behalten*,
   *Import übernehmen* oder *Zusammenführen* (Vorgabe). Beim Zusammenführen werden leere Felder gefüllt
   und abweichende Werte als Notiz festgehalten.

Nach jedem Vertragsimport werden offene Zahlungen und Dokumente neu zugeordnet.

## Ansichten

- **Übersicht**: Jahresbeitrag gesamt und je Monat, Balkendiagramm und Tabelle nach Sparte.
- **Verträge**: Tabelle mit Suche und Statusfilter. Das Vertragsdetail zeigt Dokumente, Zahlungshistorie,
  Beitragsverlauf (Swift Charts, je Jahr und je Zahlung), Fristen, Aufgaben und Notizen.
- **Prüfliste**: Verträge mit Status „prüfen“, Zahlungen ohne Vertrag (dort direkt zuordnen), aktive Verträge ohne Zahlung
  im laufenden Jahr (jährliche Zahler erst nach ihrer Fälligkeit) und Dokumente ohne Vertrag.
- **Fristen & Aufgaben**: Kündigungstermin = Ablauf (bzw. nächste Hauptfälligkeit) minus Kündigungsfrist.
  Ablauftermine wie die Kapitalauszahlung 06/2028 melden sich mindestens 90 Tage vorher.
  Die Erinnerungen sind lokale Mitteilungen um 9 Uhr.
- **Export für Berater**: CSV (Excel), JSON und ZIP mit CSV, JSON und allen Dokumenten unter
  `Dokumente/<Versicherer>_<Nummer>/<Datum>_<Typ>_<Datei>.pdf`.
  Feldnamen: Versicherungsscheinnummer, Versicherer, Sparte, Tarif, Vertragsbeginn, Vertragsablauf, Kuendigungsfrist,
  Beitrag, Zahlungsweise, Jahresbeitrag, Waehrung, Dynamik_Prozent, Vertragsstatus, Steuerliche_Einordnung, Betreuer,
  Anzahl_Dokumente, Bemerkungen.

## Datenschutz

Passwörter und Portalzugänge werden nicht gespeichert. Die Testdaten in `PolicenbuchKern/Tests/…/Testdaten` sind erfunden.
Echte Exporte, Kontoauszüge und Policen gehören nicht ins Repository (`.gitignore` schließt Stores und `Export/` aus).
