import Foundation
import GRDB

/// Schlägt für jede noch nicht zugeordnete Zahlung vor, wohin sie gehört, mit Begründung und Sicherheitsstufe.
/// Nichts wird ohne Bestätigung übernommen.
public enum Zuordnung {
    public enum Fehler: Error, CustomStringConvertible {
        case unbekannt(Int64)
        case zielFehlt(Int64)
        case schonEntschieden(Int64)
        public var description: String {
            switch self {
            case .unbekannt(let id): return "Vorschlag \(id) gibt es nicht"
            case .zielFehlt(let id): return "Vorschlag \(id) braucht ein Ziel (Reise oder Sachkostenabrechnung)"
            case .schonEntschieden(let id): return "Vorschlag \(id) ist schon entschieden"
            }
        }
    }

    public static let regelPrivat = "privat"
    public static let regelIgnorieren = "ignorieren"

    /// Händlername ohne den Vorsatz „PAYPAL *“ der Amex-Abrechnung.
    static func haendlername(_ text: String) -> String {
        guard text.uppercased().hasPrefix("PAYPAL"), let stern = text.firstIndex(of: "*") else { return text }
        return String(text[text.index(after: stern)...]).trimmingCharacters(in: .whitespaces)
    }

    static func ortsvarianten(_ ort: String?) -> [String] {
        guard let ort, !ort.isEmpty else { return [] }
        let umschrift = ort.replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        return Array(Set([Textnorm.kern(ort), Textnorm.kern(umschrift)])).filter { $0.count >= 3 }
    }

    @discardableResult
    public static func vorschlaegeBilden(in datenbank: Datenbank, wohnort: String? = nil) throws -> Int {
        try datenbank.queue.write { db in
            let vergeben = Set(try String.fetchAll(db, sql: "SELECT zahlungId FROM position WHERE zahlungId IS NOT NULL"))
            let vorgeschlagen = Set(try String.fetchAll(db, sql: "SELECT zahlungId FROM vorschlag"))
            let regeln = try Regel.filter(Column("aktiv") == true && Column("feld") == "haendler").fetchAll(db)
            let reisen = try Reise.filter(Column("beginn") != nil).fetchAll(db)
            let tanken = try Sachkostenabrechnung.fetchAll(db).first { $0.titel.localizedCaseInsensitiveContains("Tanken") }
            let wohnorte = ortsvarianten(wohnort)

            var neu = 0
            var lose: [(Zahlung, Haendlerklasse)] = []
            func anlegen(_ z: Zahlung, _ art: Vorschlagsart, ziel: String?, kostenart: Kostenart, _ grund: String, _ sicherheit: Sicherheit,
                         gruppe: String? = nil, regel: Int64? = nil) throws {
                var vorschlag = Vorschlag(id: nil, zahlungId: z.id, art: art, zielId: ziel, kostenart: kostenart, begruendung: grund,
                                          sicherheit: sicherheit, status: .offen, gruppe: gruppe, regelId: regel)
                try vorschlag.insert(db)
                neu += 1
            }

            let zahlungen = try Zahlung.filter(Column("zaehlt") == true).order(Column("datum"), Column("id")).fetchAll(db)
            for z in zahlungen {
                if let betrag = z.betragCent, betrag >= 0 { continue } // Eingänge sind keine Ausgaben
                if vergeben.contains(z.id) || vorgeschlagen.contains(z.id) { continue }
                if let partner = z.gepaartMitId, vergeben.contains(partner) || vorgeschlagen.contains(partner) { continue }
                let name = haendlername(z.haendler)
                let kern = Textnorm.kern(name)
                let klasse = Haendlerklasse.bestimme(name)

                if let regel = regeln.first(where: { !$0.muster.isEmpty && kern.contains($0.muster) }) {
                    if regel.aktion == regelIgnorieren { continue }
                    if regel.aktion == regelPrivat {
                        try anlegen(z, .privat, ziel: nil, kostenart: klasse.kostenart, "Regel: „\(regel.wert)“", .sicher, regel: regel.id)
                        continue
                    }
                }
                if klasse == .tanken {
                    try anlegen(z, .zuSachkosten, ziel: tanken?.id, kostenart: .sonstiges,
                                "Tankbeleg: Alle Tankbelege gehen in die Sachkostenabrechnung Tanken", .wahrscheinlich)
                    continue
                }
                let reisekategorie = (z.kategorie ?? "").uppercased().hasPrefix("RK")
                guard klasse.istReisebezogen || (klasse == .sonstige && reisekategorie) else { continue }

                let treffer = reisen.filter { $0.beginn! <= z.datum && z.datum <= ($0.ende ?? $0.beginn!) }
                if let privat = treffer.first(where: { $0.art == .privat }) {
                    try anlegen(z, .privat, ziel: privat.id, kostenart: klasse.kostenart,
                                "Liegt im Zeitraum der Privatreise \(privat.id) „\(privat.anlass)“", .wahrscheinlich)
                    continue
                }
                if klasse == .hotel, wohnorte.contains(where: { kern.contains($0) }) {
                    try anlegen(z, .privat, ziel: nil, kostenart: .unterkunft, "Hotel am Wohnort", .wahrscheinlich)
                    continue
                }
                if let dienstlich = treffer.first(where: { $0.art == .dienstreise }) {
                    try anlegen(z, .zuReise, ziel: dienstlich.id, kostenart: klasse.kostenart,
                                "Liegt im Zeitraum der Reise \(dienstlich.id) „\(dienstlich.anlass)“",
                                klasse.vorauskaufUeblich ? .geschaetzt : .wahrscheinlich)
                    continue
                }
                if klasse.vorauskaufUeblich {
                    try anlegen(z, .vorauskaufOffen, ziel: nil, kostenart: klasse.kostenart,
                                "Vorab bezahltes Ticket: Die Reise ergibt sich aus dem Reisedatum, nicht aus dem Zahlungstag", .geschaetzt)
                    continue
                }
                lose.append((z, klasse))
            }

            // Übrige Zahlungen vor Ort: Liegen sie höchstens einen Tag auseinander, bilden sie eine mögliche neue Reise.
            var gruppe: [(Zahlung, Haendlerklasse)] = []
            func gruppeAbschliessen() throws {
                guard let erste = gruppe.first?.0, let letzte = gruppe.last?.0 else { return }
                let zeitraum = erste.datum == letzte.datum ? "am \(erste.datum)" : "vom \(erste.datum) bis \(letzte.datum)"
                let grund = "\(gruppe.count) \(gruppe.count == 1 ? "Zahlung" : "Zahlungen") \(zeitraum) außerhalb bekannter Reisen"
                for (z, klasse) in gruppe {
                    try anlegen(z, .neueReise, ziel: nil, kostenart: klasse.kostenart, grund, .geschaetzt, gruppe: "G\(erste.datum)")
                }
                gruppe = []
            }
            for eintrag in lose {
                if let letzte = gruppe.last?.0, letzte.datum.abstandInTagen(zu: eintrag.0.datum) > 1 { try gruppeAbschliessen() }
                gruppe.append(eintrag)
            }
            try gruppeAbschliessen()
            return neu
        }
    }

    /// Übernimmt einen Vorschlag. `ziel` überschreibt das vorgeschlagene Ziel. Bei einer neuen Reise gilt die ganze Gruppe.
    /// `alsRegel` merkt sich eine Privat-Entscheidung für künftige Zahlungen desselben Händlers.
    @discardableResult
    public static func annehmen(in datenbank: Datenbank, vorschlag id: Int64, ziel: String? = nil, alsRegel: Bool = false) throws -> String? {
        try datenbank.queue.write { db in
            guard var vorschlag = try Vorschlag.fetchOne(db, key: id) else { throw Fehler.unbekannt(id) }
            guard vorschlag.status == .offen else { throw Fehler.schonEntschieden(id) }
            guard let zahlung = try Zahlung.fetchOne(db, key: vorschlag.zahlungId) else { throw Fehler.unbekannt(id) }
            let zielId = ziel ?? vorschlag.zielId

            switch vorschlag.art {
            case .privat where ziel == nil:
                if alsRegel {
                    let name = haendlername(zahlung.haendler)
                    var regel = Regel(id: nil, feld: "haendler", muster: Textnorm.kern(name), aktion: regelPrivat,
                                      wert: "\(name) = privat", herkunft: "Entscheidung zu \(zahlung.id)", aktiv: true)
                    try regel.insert(db)
                    vorschlag.regelId = regel.id
                }
                try entscheiden(db, &vorschlag, .angenommen, wert: "privat")
                return nil
            case .neueReise where ziel == nil:
                let mitglieder = try Vorschlag
                    .filter(Column("gruppe") == vorschlag.gruppe && Column("status") == Vorschlagsstatus.offen.rawValue && Column("art") == Vorschlagsart.neueReise.rawValue)
                    .fetchAll(db)
                let zahlungen = try mitglieder.compactMap { try Zahlung.fetchOne(db, key: $0.zahlungId) }
                let tage = zahlungen.map(\.datum)
                let nummern = try String.fetchAll(db, sql: "SELECT id FROM reise WHERE id LIKE 'D%'").compactMap { Int($0.dropFirst()) }
                let reiseId = String(format: "D%02d", (nummern.max() ?? 0) + 1)
                try Reise(id: reiseId, art: .dienstreise, typ: nil, anlass: "Erkannte Reise", ort: nil, istStammeinsatz: false,
                          beginn: tage.min(), beginnZeit: nil, beginnQuelle: "erste Zahlung vor Ort", beginnSicherheit: .geschaetzt,
                          ende: tage.max(), endeZeit: nil, endeQuelle: "letzte Zahlung vor Ort", endeSicherheit: .geschaetzt,
                          verkehrsmittel: nil, unterkunft: nil, hinweis: nil, status: .erkannt, concurNr: nil, concurTitel: nil).insert(db)
                var punkt = OffenerPunkt(id: nil, reiseId: reiseId, sachkostenId: nil, text: "Anlass und Ort der erkannten Reise nachtragen",
                                         fundort: "Kalender", erledigt: false, herkunft: "Reiseerkennung")
                try punkt.insert(db)
                for var mitglied in mitglieder {
                    guard let z = zahlungen.first(where: { $0.id == mitglied.zahlungId }) else { continue }
                    try positionAnlegen(db, z, kostenart: mitglied.kostenart, reise: reiseId, sachkosten: nil)
                    mitglied.zielId = reiseId
                    try entscheiden(db, &mitglied, .angenommen, wert: reiseId)
                }
                return reiseId
            default:
                guard let zielId else { throw Fehler.zielFehlt(id) }
                if try Reise.exists(db, key: zielId) {
                    try positionAnlegen(db, zahlung, kostenart: vorschlag.kostenart, reise: zielId, sachkosten: nil)
                } else if try Sachkostenabrechnung.exists(db, key: zielId) {
                    try positionAnlegen(db, zahlung, kostenart: .sonstiges, reise: nil, sachkosten: zielId)
                } else {
                    throw Fehler.zielFehlt(id)
                }
                vorschlag.zielId = zielId
                try entscheiden(db, &vorschlag, .angenommen, wert: zielId)
                return zielId
            }
        }
    }

    public static func ablehnen(in datenbank: Datenbank, vorschlag id: Int64) throws {
        try datenbank.queue.write { db in
            guard var vorschlag = try Vorschlag.fetchOne(db, key: id) else { throw Fehler.unbekannt(id) }
            guard vorschlag.status == .offen else { throw Fehler.schonEntschieden(id) }
            try entscheiden(db, &vorschlag, .abgelehnt, wert: "abgelehnt")
        }
    }

    static func entscheiden(_ db: Database, _ vorschlag: inout Vorschlag, _ status: Vorschlagsstatus, wert: String) throws {
        vorschlag.status = status
        try vorschlag.update(db)
        var eintrag = Entscheidung(id: nil, objektTyp: "zahlung", objektId: vorschlag.zahlungId, feld: "zuordnung", wert: wert, quelle: "Nutzer",
                                   regelId: vorschlag.regelId, sicherheit: .sicher, zeit: ISO8601DateFormatter().string(from: Date()))
        try eintrag.insert(db)
    }

    static func positionAnlegen(_ db: Database, _ z: Zahlung, kostenart: Kostenart, reise: String?, sachkosten: String?) throws {
        var vorauskauf = false
        if let reise, let beginn = try Reise.fetchOne(db, key: reise)?.beginn { vorauskauf = z.datum < beginn }
        var position = Position(
            id: nil, reiseId: reise, sachkostenId: sachkosten, datum: z.datum, quelle: z.gepaartMitId == nil ? z.konto : "Amex+PayPal",
            kostenart: kostenart, kostenartText: nil, haendler: z.haendler, ort: nil, betragCent: z.betragCent.map { -$0 },
            fremdbetragCent: z.fremdbetragCent.map { abs($0) }, fremdwaehrung: z.fremdwaehrung, zahlungId: z.id, privatVorgestreckt: true,
            erstattung: .offen, vorauskauf: vorauskauf, belegHinweis: nil, vorschlag: nil)
        try position.insert(db)
    }
}
