import Foundation
import UserNotifications
import PolicenbuchKern

/// Lokale Mitteilungen für Kündigungsfristen, Abläufe und Aufgaben. Es wird nichts versendet.
@MainActor
enum Erinnerungen {
    static let praefix = "policenbuch.frist."
    /// macOS begrenzt die Zahl geplanter Mitteilungen; die nächsten Termine haben Vorrang.
    static let hoechstzahl = 60
    static let uhrzeit = 9

    /// Fragt beim ersten Mal nach; danach liefert das System nur den aktuellen Stand.
    static func erlaubnisAnfragen() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Ersetzt alle geplanten Erinnerungen des Policenbuchs. Gibt die Zahl geplanter Mitteilungen zurück.
    @discardableResult
    static func planen(_ fristen: [Frist], vertragsnamen: [UUID: String]) async -> Int {
        guard await erlaubnisAnfragen() else { return 0 }
        let zentrale = UNUserNotificationCenter.current()
        // Die App plant nur eigene Mitteilungen; alles neu aufsetzen.
        zentrale.removeAllPendingNotificationRequests()

        let jetzt = Date.now
        var anzahl = 0
        for frist in fristen where frist.datum > jetzt {
            guard anzahl < hoechstzahl else { break }
            var zeitpunkt = Datum.kalender.dateComponents([.year, .month, .day], from: max(frist.erinnerung, jetzt))
            zeitpunkt.hour = uhrzeit
            if let d = Datum.kalender.date(from: zeitpunkt), d <= jetzt {
                // heute schon nach 9 Uhr: morgen erinnern
                zeitpunkt = Datum.kalender.dateComponents([.year, .month, .day], from: Datum.plus(tage: 1, zu: d))
                zeitpunkt.hour = uhrzeit
            }
            let inhalt = UNMutableNotificationContent()
            inhalt.title = titel(frist)
            let name = frist.vertragID.flatMap { vertragsnamen[$0] } ?? ""
            inhalt.body = [name, "Termin: \(Datum.deutsch(frist.datum))"].filter { !$0.isEmpty }.joined(separator: "\n")
            inhalt.sound = .default
            if let id = frist.vertragID { inhalt.userInfo = ["vertrag": id.uuidString] }
            let ausloeser = UNCalendarNotificationTrigger(dateMatching: zeitpunkt, repeats: false)
            let anfrage = UNNotificationRequest(identifier: praefix + frist.id, content: inhalt, trigger: ausloeser)
            do {
                try await zentrale.add(anfrage)
                anzahl += 1
            } catch {
                continue
            }
        }
        return anzahl
    }

    static func titel(_ frist: Frist) -> String {
        switch frist.art {
        case .kuendigung: "Kündigungsfrist läuft ab"
        case .ablauf: "Vertragsablauf naht"
        case .aufgabe: "Aufgabe fällig: \(frist.titel)"
        }
    }
}
