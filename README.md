# Wallet-Werkbank

KI-Werkbank für Apple-Wallet-Karten als **eine einzige HTML-Datei**: [`wallet-werkbank.html`](wallet-werkbank.html).

Termine, Mails, Mitgliedsdaten, Fotos von Karten und Notizen sammeln. Claude erkennt, was zusammengehört (Reisekette, gleicher Anlass, Mitgliedschaft plus Termin, Fristen), und schlägt passende Wallet-Karten vor. Aus deinen Entscheidungen lernt die Werkbank, welche Karten dir wichtig sind.

## Starten

- Datei im Browser öffnen (Safari auf dem iPhone, Mac, PC). Kein Server und keine Installation nötig.
- Für die KI: unter **Einstellungen** einen Anthropic-API-Schlüssel eintragen. Ohne Schlüssel arbeitet die Werkbank mit lokalen Regeln.
- Daten bleiben im Browser (`localStorage`). Der API-Schlüssel geht nur an `api.anthropic.com`.

## Direkt zur Karte

Oben im Eingang: Mail, Kalendertermin oder Screenshot hinein, fertige Karte heraus, ohne Umweg über Analyse und Übernehmen.

- **Mail**: Text, HTML oder kompletten Quelltext einfügen oder eine `.eml`-Datei wählen. Gelesen werden Betreff, Absender, Text, Anhänge (Bilder, PDFs, Kalendereinladungen, `.pkpass`) und die strukturierten Buchungsdaten (schema.org: Zug, Bus, Flug, Veranstaltung, Hotel, Restaurant, Mietwagen). Buchungsdaten werden ohne KI exakt übernommen, inklusive Ticket-Code.
- **Kalendertermin**: Formular für einen Termin oder `.ics`-Datei, dann je Termin eine Karte. Bei Google/Outlook (Reiter Schnittstellen) gibt es den Haken „direkt als Karten erzeugen“.
- **Screenshot / Foto / PDF**: auswählen, hineinziehen, einfügen (⌘V / Strg+V) oder „Bild aus Zwischenablage einsetzen“. Die Karte entsteht sofort. QR-Codes werden lokal gelesen (jsQR, bei Chrome zusätzlich BarcodeDetector für Strichcodes, PDF417, Aztec) und exakt in die Karte übernommen.
- **Kurzbefehl/Link**: `#add=<Text>&direct=1`, `#mail=<Mailtext>`, `#shot`.

Ohne API-Schlüssel greifen Buchungsdaten, Codes und lokale Regeln; Texte aus Bildern liest nur Claude.

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

## Mac-App (DMG)

Der Ordner [`mac/`](mac/) macht aus der Werkbank eine eigenständige Mac-App (Electron). Die Bibliotheken sind eingebaut, die App startet also auch offline. `.eml`, `.ics` und `.pkpass` lassen sich per „Öffnen mit“, aufs Dock-Symbol ziehen oder mit ⌘O übergeben; Mails, Termine und Bilder werden dabei direkt zu Karten. Exportierte Karten zeigt die App im Finder, von dort per AirDrop ans iPhone.

- **DMG herunterladen:** GitHub → Actions → „Mac-App (DMG)“ → letzter Lauf → Artefakt `Wallet-Werkbank-DMG`. Darin je ein DMG für Apple Silicon (`arm64`) und Intel (`x64`).
- **Erster Start:** Die App ist nur ad-hoc signiert (kein Apple-Entwicklerzertifikat). macOS meldet deshalb, dass der Entwickler nicht überprüft werden kann. Einmal öffnen versuchen, dann Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“. Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/Wallet-Werkbank.app`.
- **Selbst bauen (auf einem Mac):** `cd mac && npm ci && npm run dist` → `mac/dist/*.dmg`. Zum Ausprobieren ohne DMG: `npm start`.
- Der Workflow [`.github/workflows/mac-app.yml`](.github/workflows/mac-app.yml) baut bei jeder Änderung an Werkbank oder App auf einem macOS-Runner, prüft Signatur und DMG und startet die App einmal zur Probe.

## Technik

- Claude Messages API direkt aus dem Browser (`anthropic-dangerous-direct-browser-access`), Standardmodell `claude-opus-5-5`, strukturierte Ausgabe per JSON-Schema, Websuche als Server-Tool, optionale Ausweichmodelle bei Ablehnung.
- Bibliotheken von cdnjs/jsDelivr: JSZip (Paket), node-forge (PKCS#7-Signatur), qrcode-generator (QR-Code), jsQR (QR-Codes in Bildern lesen).

---

# Reisemanager

Im Ordner [`reisemanager/`](reisemanager/) entsteht eine lokale macOS-App für Dienstreisen und Sachkosten. Stand und Bedienung stehen in der [README dort](reisemanager/README.md).
