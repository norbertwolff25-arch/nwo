import Foundation
import ReisemanagerKern
import SwiftUI

enum Bereich: Hashable {
    case dashboard
    case abrechnung(String)
    case vorschlaege
    case besorgen
    case einlesen
}

enum Importart: String, CaseIterable, Identifiable {
    case nwopay = "NWO-Pay (CSV)"
    case amex = "Amex activity.csv"
    case paypal = "PayPal-Export (CSV)"
    case startbestand = "Startbestand (JSON)"
    case ereignisse = "Reiseverläufe, Hotels, Termine (JSON)"
    case belege = "Belegordner"
    var id: String { rawValue }
}

struct Besorgungsgruppe: Identifiable {
    var fundort: String
    var eintraege: [Besorgung]
    var id: String { fundort }
}

/// Zustand der Oberfläche. Alle Fachlogik liegt im Kern; hier wird nur geladen und weitergereicht.
@MainActor
final class AppModell: ObservableObject {
    @Published var uebersicht: Uebersicht?
    @Published var detail: Abrechnungsdetail?
    @Published var vorschlaege: [Vorschlagszeile] = []
    @Published var besorgen: [Besorgungsgruppe] = []
    @Published var auswahl: Bereich? = .dashboard
    @Published var meldung: String?
    @Published var protokoll: [String] = []

    let ordner: URL
    private(set) var datenbank: Datenbank?
    private(set) var einstellungen: Einstellungen?

    var heute: Tag {
        let teile = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return Tag(jahr: teile.year ?? 2026, monat: teile.month ?? 1, tag: teile.day ?? 1)!
    }

    init() {
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        ordner = basis.appendingPathComponent("Reisemanager", isDirectory: true)
        do {
            let umgebung = ProcessInfo.processInfo.environment
            datenbank = try Datenbank(pfad: umgebung["REISEMANAGER_DB"] ?? ordner.appendingPathComponent("reisemanager.sqlite").path)
            let pfad = umgebung["REISEMANAGER_EINSTELLUNGEN"] ?? ordner.appendingPathComponent("einstellungen.json").path
            if FileManager.default.fileExists(atPath: pfad) {
                einstellungen = try Einstellungen.laden(pfad: pfad)
            } else {
                protokoll.append("Keine Einstellungen gefunden (\(pfad)). „Hotel am Wohnort“ wird nicht erkannt.")
            }
        } catch {
            meldung = "Start fehlgeschlagen: \(error)"
        }
        laden()
    }

    /// Lädt alles neu. Die Datenmenge einer Person ist klein, daher ohne Teilaktualisierung.
    func laden() {
        guard let datenbank else { return }
        do {
            uebersicht = try Ansicht.uebersicht(in: datenbank, einstellungen: einstellungen, heute: heute)
            vorschlaege = try Ansicht.vorschlaege(in: datenbank)
            besorgen = try Ansicht.besorgungsliste(in: datenbank, einstellungen: einstellungen, heute: heute)
                .map { Besorgungsgruppe(fundort: $0.fundort, eintraege: $0.eintraege) }
            if case .abrechnung(let bezug) = auswahl {
                detail = try Ansicht.detail(in: datenbank, bezug: bezug, einstellungen: einstellungen, heute: heute)
            } else {
                detail = nil
            }
        } catch {
            meldung = "\(error)"
        }
    }

    /// Führt eine Änderung aus, meldet Fehler und lädt neu.
    func ausfuehren(_ aktion: (Datenbank) throws -> Void) {
        guard let datenbank else { return }
        do { try aktion(datenbank) } catch { meldung = "\(error)" }
        laden()
    }

    func antworte(_ schluessel: String, nummer: Int) {
        ausfuehren { try Plausi.beantworte(in: $0, schluessel: schluessel, nummer: nummer, einstellungen: einstellungen) }
    }

    func verschiebe(position: Int64, nach bezug: String) {
        ausfuehren { try Bearbeitung.verschiebe(in: $0, position: position, nach: bezug) }
    }

    func setzeStatus(_ bezug: String, _ status: Reisestatus) {
        ausfuehren { try Bearbeitung.setzeStatus(in: $0, bezug: bezug, status: status) }
    }

    func erledige(punkt: Int64) {
        ausfuehren { try Bearbeitung.erledige(in: $0, offenerPunkt: punkt) }
    }

    func annehmen(_ vorschlag: Int64, ziel: String? = nil, alsRegel: Bool = false) {
        ausfuehren { try Zuordnung.annehmen(in: $0, vorschlag: vorschlag, ziel: ziel, alsRegel: alsRegel) }
    }

    func ablehnen(_ vorschlag: Int64) {
        ausfuehren { try Zuordnung.ablehnen(in: $0, vorschlag: vorschlag) }
    }

    func erkennen() {
        ausfuehren { datenbank in
            let reisen = try Vorbelegung.anwenden(in: datenbank)
            let neue = try Zuordnung.vorschlaegeBilden(in: datenbank, wohnort: einstellungen?.privatadresse.ort)
            protokoll.append("Erkennung: \(reisen) Reisen neu vorbelegt, \(neue) neue Vorschläge")
        }
    }

    func importiere(_ art: Importart, urls: [URL]) {
        ausfuehren { datenbank in
            for url in urls {
                // Dateien aus dem Auswahldialog brauchen in einer Sandbox ausdrücklich Zugriff.
                let zugriff = url.startAccessingSecurityScopedResource()
                defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
                let ergebnis: Importergebnis
                switch art {
                case .nwopay: ergebnis = try NWOPayImport.importiere(datei: url.path, in: datenbank)
                case .amex: ergebnis = try AmexImport.importiere(datei: url.path, in: datenbank)
                case .paypal: ergebnis = try PayPalImport.importiere(datei: url.path, in: datenbank)
                case .startbestand: ergebnis = try StartbestandImport.importiere(datei: url.path, in: datenbank)
                case .ereignisse: ergebnis = try EreignisImport.importiere(datei: url.path, in: datenbank)
                case .belege: ergebnis = try BelegordnerImport.importiere(ordner: url.path, in: datenbank)
                }
                protokoll.append("\(url.lastPathComponent): \(ergebnis.zusammenfassung)")
                protokoll.append(contentsOf: ergebnis.fehler.map { "  ! \($0)" })
            }
            if [.nwopay, .amex, .paypal].contains(art) {
                let paare = try Paarung.paareBilden(in: datenbank)
                if paare > 0 { protokoll.append("\(paare) PayPal-Zahlungen mit Amex gepaart") }
            }
        }
    }

    func berichtSpeichern(_ bezug: String, nach url: URL) {
        ausfuehren { datenbank in
            guard let text = try Bericht.markdown(in: datenbank, bezug: bezug, einstellungen: einstellungen, heute: heute) else { return }
            try text.write(to: url, atomically: true, encoding: .utf8)
            protokoll.append("Bericht gespeichert: \(url.lastPathComponent)")
        }
    }
}
