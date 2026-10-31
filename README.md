# Wallet-Werkbank

KI-Werkbank für Apple-Wallet-Karten als **eine einzige HTML-Datei**: [`wallet-werkbank.html`](wallet-werkbank.html).

Termine, Mails, Mitgliedsdaten, Fotos von Karten und Notizen sammeln. Claude erkennt, was zusammengehört (Reisekette, gleicher Anlass, Mitgliedschaft plus Termin, Fristen), und schlägt passende Wallet-Karten vor. Aus deinen Entscheidungen lernt die Werkbank, welche Karten dir wichtig sind.

## Starten

- Datei im Browser öffnen (Safari auf dem iPhone, Mac, PC). Kein Server und keine Installation nötig.
- Für die KI: unter **Einstellungen** einen Anthropic-API-Schlüssel eintragen. Ohne Schlüssel arbeitet die Werkbank mit lokalen Regeln.
- Daten bleiben im Browser (`localStorage`). Der API-Schlüssel geht nur an `api.anthropic.com`.

## Ablauf

1. **Eingang**: Text einfügen, Dateien ablegen (`.ics`, `.vcf`, `.pkpass`, Fotos, PDF, `.txt/.eml`), ICS-Abo laden, Google-/Outlook-Kalender per Token holen oder per iPhone-Kurzbefehl übergeben (`…/wallet-werkbank.html#add=<Text>`).
2. **Verbindungen & Vorschläge**: Claude (strukturierte Ausgabe) liefert Verbindungen als Netz, Kartenvorschläge mit Relevanz, Hinweise auf Schnittstellen, Rückfragen und Regelvorschläge.
3. **Karten**: Editor mit Wallet-Vorschau (Event-Ticket, Mitgliedskarte, Bordkarte, Gutschein, Allgemein), Felder, Farben, Code, Datum, Ort. „Mit Claude verfeinern“ ändert die Karte per Anweisung.
4. **Export**:
   - **.pkpass** direkt fürs Wallet, lokal im Browser signiert (Pass-Type-ID-Zertifikat `.p12` + Apple WWDR-Zertifikat aus dem Apple Developer Program).
   - Ohne Zertifikat: Code als Bild und Feldtexte kopieren, dann im Wallet „+“ → „Pass erstellen“; oder unsigniertes Paket (`.zip`) für einen Signierdienst.
   - Zusätzlich `.ics`-Kalendereintrag und `pass.json`.

## Lernen

Übernehmen, Verwerfen, Bearbeiten und Exportieren verändern das Lernprofil: Quote je Kategorie, gewichtete Begriffe, bevorzugte Farben und Feldbezeichnungen. Dazu kommen eigene Regeln in Klartext. Das Profil geht bei jeder Analyse an Claude und bestimmt die Sortierung der Vorschläge.

## Schnittstellen

Der Reiter **Schnittstellen** enthält einen Katalog (Kalender, Mail, Tickets, Reisen, Mitgliedschaften, Wallet-Erzeugung, Automatisierung) mit Zugangsart und Browser-Tauglichkeit. „Recherchieren“ lässt Claude mit Websuche aktuelle APIs, Feeds und Wallet-Angebote eines Anbieters finden.

## Technik

- Claude Messages API direkt aus dem Browser (`anthropic-dangerous-direct-browser-access`), Standardmodell `claude-opus-5-5`, strukturierte Ausgabe per JSON-Schema, Websuche als Server-Tool, optionale Ausweichmodelle bei Ablehnung.
- Bibliotheken von cdnjs: JSZip (Paket), node-forge (PKCS#7-Signatur), qrcode-generator (QR-Code).
