import Foundation
import GRDB

/// Belegt Beginn und Ende jeder Dienstreise vor. Rangfolge der Quellen:
/// 1 Zugzeiten, 2 Flugzeiten, 3 Hotel-An- und Abreise, 4 erste und letzte Uber-/Bolt-Fahrt, 5 Kalender, 6 Zahlungsdaten.
public enum Vorbelegung {
    public struct Kandidat: Equatable, Sendable {
        public var rang: Int
        public var tag: Tag
        public var zeit: String?
        public var quelle: String
        public var sicherheit: Sicherheit
    }

    static func stufe(_ sicherheit: Sicherheit?) -> Int {
        switch sicherheit {
        case .sicher: return 3
        case .wahrscheinlich: return 2
        case .geschaetzt: return 1
        case nil: return 0
        }
    }

    static func istBahn(_ verkehrsmittel: String?) -> Bool {
        let v = (verkehrsmittel ?? "").lowercased()
        return ["bahn", "zug", "ice", "train", "eurostar", "thalys"].contains { v.contains($0) }
    }

    static func istFlug(_ verkehrsmittel: String?) -> Bool {
        let v = (verkehrsmittel ?? "").lowercased()
        return v.contains("flug") || v.contains("flight")
    }

    /// Alle Kandidaten für Beginn und Ende einer Reise, bester zuerst.
    static func kandidaten(_ db: Database, reise: Reise) throws -> (beginn: [Kandidat], ende: [Kandidat]) {
        var beginn: [Kandidat] = []
        var ende: [Kandidat] = []
        let abschnitte = try Reiseabschnitt.filter(Column("reiseId") == reise.id).fetchAll(db)

        // Rang 1 und 2: Fahrplanzeiten. Ein Vorlauf oder Nachlauf verschiebt Beginn und Ende bis zur Privatadresse.
        for (rang, passt, name) in [(1, istBahn, "Zugzeiten"), (2, istFlug, "Flugzeiten")] as [(Int, (String?) -> Bool, String)] {
            guard abschnitte.contains(where: { passt($0.verkehrsmittel) }) else { continue }
            let abfahrten = abschnitte.compactMap { a in a.abfahrt.flatMap(Zeitpunkt.init(text:)).map { ($0, a) } }
            let ankuenfte = abschnitte.compactMap { a in a.ankunft.flatMap(Zeitpunkt.init(text:)).map { ($0, a) } }
            if let (zeit, abschnitt) = abfahrten.min(by: { $0.0 < $1.0 }) {
                let zusatz = abschnitt.art == "vorlauf" ? " mit Vorlauf" : ""
                beginn.append(Kandidat(rang: rang, tag: zeit.tag, zeit: zeit.uhrzeit, quelle: "\(abschnitt.quelle ?? name)\(zusatz)", sicherheit: .sicher))
            }
            if let (zeit, abschnitt) = ankuenfte.max(by: { $0.0 < $1.0 }) {
                let zusatz = abschnitt.art == "nachlauf" ? " mit Nachlauf" : ""
                ende.append(Kandidat(rang: rang, tag: zeit.tag, zeit: zeit.uhrzeit, quelle: "\(abschnitt.quelle ?? name)\(zusatz)", sicherheit: .sicher))
            }
        }

        // Rang 3: Hotel.
        let aufenthalte = try Hotelaufenthalt.filter(Column("reiseId") == reise.id).fetchAll(db)
        if let erster = aufenthalte.min(by: { $0.anreise < $1.anreise }) {
            beginn.append(Kandidat(rang: 3, tag: erster.anreise, zeit: nil, quelle: "Hotel-Anreise \(erster.hotel)", sicherheit: .wahrscheinlich))
        }
        if let letzter = aufenthalte.max(by: { $0.abreise < $1.abreise }) {
            ende.append(Kandidat(rang: 3, tag: letzter.abreise, zeit: nil, quelle: "Hotel-Abreise \(letzter.hotel)", sicherheit: .wahrscheinlich))
        }

        // Rang 4: erste und letzte Uber- oder Bolt-Fahrt.
        let positionen = try Position.filter(Column("reiseId") == reise.id && Column("datum") != nil).fetchAll(db)
        let fahrten = positionen.filter { Haendlerklasse.bestimme($0.haendler) == .taxi }.compactMap(\.datum)
        if let erste = fahrten.min() {
            beginn.append(Kandidat(rang: 4, tag: erste, zeit: nil, quelle: "erste Uber-/Bolt-Fahrt", sicherheit: .wahrscheinlich))
        }
        if let letzte = fahrten.max() {
            ende.append(Kandidat(rang: 4, tag: letzte, zeit: nil, quelle: "letzte Uber-/Bolt-Fahrt", sicherheit: .wahrscheinlich))
        }

        // Rang 5: Kalender. Nur Termine, die den bisherigen Zeitraum berühren (±1 Tag).
        if let von = reise.beginn, let bis = reise.ende ?? reise.beginn {
            let termine = try Termin.fetchAll(db).filter {
                $0.ende.abstandInTagen(zu: von) <= 1 && bis.abstandInTagen(zu: $0.beginn) <= 1
            }
            if let erster = termine.min(by: { $0.beginn < $1.beginn }) {
                beginn.append(Kandidat(rang: 5, tag: erster.beginn, zeit: erster.beginnZeit, quelle: "Kalender: \(erster.titel)", sicherheit: .geschaetzt))
            }
            if let letzter = termine.max(by: { $0.ende < $1.ende }) {
                ende.append(Kandidat(rang: 5, tag: letzter.ende, zeit: letzter.endeZeit, quelle: "Kalender: \(letzter.titel)", sicherheit: .geschaetzt))
            }
        }

        // Rang 6: Zahlungsdaten. Vorab bezahlte Tickets zählen nicht, ihr Zahlungstag ist kein Reisetag.
        // Platzhalter ohne Betrag sind keine Zahlung.
        let vorOrt = positionen.filter { $0.betragCent != nil && !$0.vorauskauf && !Haendlerklasse.bestimme($0.haendler).vorauskaufUeblich && $0.kostenart != .paket }
            .compactMap(\.datum)
        if let erste = vorOrt.min() {
            beginn.append(Kandidat(rang: 6, tag: erste, zeit: nil, quelle: "erste Zahlung vor Ort", sicherheit: .geschaetzt))
        }
        if let letzte = vorOrt.max() {
            ende.append(Kandidat(rang: 6, tag: letzte, zeit: nil, quelle: "letzte Zahlung vor Ort", sicherheit: .geschaetzt))
        }
        return (beginn.sorted { $0.rang < $1.rang }, ende.sorted { $0.rang < $1.rang })
    }

    /// Setzt Beginn und Ende, wenn die beste Quelle verlässlicher ist als der bisherige Wert.
    /// Vom Nutzer bestätigte Werte bleiben unangetastet. Jede Änderung wird protokolliert.
    @discardableResult
    public static func anwenden(in datenbank: Datenbank) throws -> Int {
        try datenbank.queue.write { db in
            var geaendert = 0
            for var reise in try Reise.filter(Column("art") == Reiseart.dienstreise.rawValue).fetchAll(db) {
                let (beginn, ende) = try kandidaten(db, reise: reise)
                var neu = false
                if let bester = beginn.first, try darfSetzen(db, reise: reise.id, feld: "beginn", bisher: reise.beginnSicherheit, hatWert: reise.beginn != nil, kandidat: bester) {
                    reise.beginn = bester.tag; reise.beginnZeit = bester.zeit; reise.beginnQuelle = bester.quelle; reise.beginnSicherheit = bester.sicherheit
                    try protokolliere(db, reise: reise.id, feld: "beginn", kandidat: bester)
                    neu = true
                }
                if let bester = ende.first, try darfSetzen(db, reise: reise.id, feld: "ende", bisher: reise.endeSicherheit, hatWert: reise.ende != nil, kandidat: bester) {
                    reise.ende = bester.tag; reise.endeZeit = bester.zeit; reise.endeQuelle = bester.quelle; reise.endeSicherheit = bester.sicherheit
                    try protokolliere(db, reise: reise.id, feld: "ende", kandidat: bester)
                    neu = true
                }
                if neu {
                    try reise.update(db)
                    geaendert += 1
                    // Mit neuem Beginn steht fest, was Vorauskauf war.
                    if let start = reise.beginn {
                        for var position in try Position.filter(Column("reiseId") == reise.id && Column("datum") != nil).fetchAll(db) {
                            let vorher = position.datum! < start
                            if position.vorauskauf != vorher { position.vorauskauf = vorher; try position.update(db) }
                        }
                    }
                }
            }
            return geaendert
        }
    }

    static func darfSetzen(_ db: Database, reise: String, feld: String, bisher: Sicherheit?, hatWert: Bool, kandidat: Kandidat) throws -> Bool {
        let vomNutzer = try Entscheidung
            .filter(Column("objektTyp") == "reise" && Column("objektId") == reise && Column("feld") == feld && Column("quelle") == "Nutzer")
            .fetchCount(db) > 0
        if vomNutzer { return false }
        if !hatWert { return true }
        return stufe(kandidat.sicherheit) > stufe(bisher)
    }

    static func protokolliere(_ db: Database, reise: String, feld: String, kandidat: Kandidat) throws {
        let wert = kandidat.tag.iso + (kandidat.zeit.map { " " + $0 } ?? "")
        var eintrag = Entscheidung(id: nil, objektTyp: "reise", objektId: reise, feld: feld, wert: wert, quelle: kandidat.quelle,
                                   regelId: nil, sicherheit: kandidat.sicherheit, zeit: ISO8601DateFormatter().string(from: Date()))
        try eintrag.insert(db)
    }

    /// Der Nutzer legt Beginn oder Ende fest. Danach überschreibt keine Vorbelegung den Wert.
    public static func bestaetige(in datenbank: Datenbank, reise id: String, beginn: Zeitpunkt?, ende: Zeitpunkt?) throws {
        try datenbank.queue.write { db in
            guard var reise = try Reise.fetchOne(db, key: id) else { return }
            if let beginn {
                reise.beginn = beginn.tag; reise.beginnZeit = beginn.uhrzeit; reise.beginnQuelle = "Nutzer"; reise.beginnSicherheit = .sicher
                try protokolliere(db, reise: id, feld: "beginn", kandidat: Kandidat(rang: 0, tag: beginn.tag, zeit: beginn.uhrzeit, quelle: "Nutzer", sicherheit: .sicher))
            }
            if let ende {
                reise.ende = ende.tag; reise.endeZeit = ende.uhrzeit; reise.endeQuelle = "Nutzer"; reise.endeSicherheit = .sicher
                try protokolliere(db, reise: id, feld: "ende", kandidat: Kandidat(rang: 0, tag: ende.tag, zeit: ende.uhrzeit, quelle: "Nutzer", sicherheit: .sicher))
            }
            try reise.update(db)
        }
    }
}
