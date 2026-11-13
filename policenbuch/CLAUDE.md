# Policenbuch – Regeln für Claude

Native macOS-App für Norberts **private** Versicherungsverwaltung.

## Technik

- Swift 6 (Strict Concurrency), SwiftUI, SwiftData, Swift Charts, Vision, PDFKit, UserNotifications.
- Mindestversion macOS 15. Xcode-Projekt `Policenbuch.xcodeproj` (Xcode 16, synchronisierte Ordner).
- Zielordner auf dem Mac: `~/Projekte/policenbuch`.
- Fachlogik ohne Apple-UI-Abhängigkeit im lokalen Paket `PolicenbuchKern`
  (Parser, Importe, Zuordnung, Dubletten, Fristen, Export, ZIP). Läuft auch unter Linux (`swift test`).
- App-Schicht `Policenbuch/` (SwiftData-Modelle, Ansichten, OCR, Mitteilungen) nur macOS.
- Tests mit **Swift Testing** (`import Testing`, `@Test`, `#expect`), kein XCTest.

## Datenschutz (nicht verhandelbar)

- **Nur lokal**: kein Cloud-Sync (kein CloudKit, kein iCloud-Container), kein Server, keine Telemetrie,
  keine Analyse-SDKs, keine Netzwerkzugriffe. Keine Abhängigkeiten von Drittanbieter-Paketen.
- Daten ausschließlich unter `~/Library/Application Support/Policenbuch` (SwiftData-Store).
  Dokumente bleiben, wo sie liegen; gespeichert wird nur der PDF-Pfad.
- **Keine Passwörter, PINs oder Portalzugänge speichern** – auch nicht in `notizen`.
  Der Import entfernt Felder, deren Name nach Zugangsdaten aussieht (`password`, `passwort`, `pin`, `token`, …).
- Keine echten Vertragsdaten, Kontoauszüge oder Policen ins Repository. Testdaten sind erfunden.

## Git

- Git lokal. **Kein Push auf das x1F-GitLab** (privates Projekt, nie mit x1F vermischen).

## Vorgehen

1. Datenmodell und CSV-Import mit Tests, 2. UI, 3. OCR.
2. Nach jedem Schritt bauen und testen:
   - `cd PolicenbuchKern && swift test`
   - `xcodebuild -project Policenbuch.xcodeproj -scheme Policenbuch -destination 'platform=macOS' test`
3. Deutsche Oberfläche mit korrekten Umlauten (ä, ö, ü, ß) – keine Ersatzschreibungen wie „ae“ in sichtbaren Texten.
   Bezeichner im Code dürfen ASCII sein (`kuendigungsfrist`), Rohwerte von Enums tragen Umlaute (`"prüfen"`).

## Fachliche Regeln

- Nichts manuell neu erfassen: Import ist Kernfunktion.
- Unbekannte Importfelder landen in `notizen` (`Feldname: Wert`), nie verwerfen.
- Dubletten = gleiche normalisierte `vertragsnummer` + gleicher Versicherer; Konflikte nebeneinander zeigen.
- Zahlungen werden über die Vertragsnummer im Verwendungszweck zugeordnet (Trennzeichen egal, mind. 5 Zeichen).
- Exportfelder an GDV-/BiPRO-Begriffe angelehnt (Versicherungsscheinnummer, Sparte, Beitrag, Zahlungsweise).

## Stand (13.11.2026)

- Fachkern `PolicenbuchKern`: 47 Tests grün (Swift 6.2, Linux).
- App-Schicht (SwiftUI/SwiftData/Vision) wurde in der Cloud-Sitzung ohne Xcode geschrieben und ist **noch nicht kompiliert**.
  Erster Schritt auf dem Mac: `xcodebuild … test` ausführen und Compilerfehler beheben, danach die App mit erfundenen Daten
  aus `PolicenbuchKern/Tests/PolicenbuchKernTests/Testdaten` durchklicken.
