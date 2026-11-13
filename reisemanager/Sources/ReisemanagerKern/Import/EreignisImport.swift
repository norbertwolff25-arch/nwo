import Foundation
import GRDB

/// Reiseverläufe, Hotelaufenthalte und Termine als JSON. Die Datei entsteht auf dem Mac aus bahn.de,
/// dem Hotelportal und dem Kalender und bleibt lokal.
public struct Ereignisse: Codable, Sendable {
    public struct AbschnittEintrag: Codable, Sendable {
        public var reise: String
        /// „vorlauf“, „hauptlauf“ oder „nachlauf“.
        public var art: String?
        public var von: String?
        public var nach: String?
        /// „JJJJ-MM-TT HH:MM“
        public var abfahrt: String?
        public var ankunft: String?
        public var verkehrsmittel: String?
        public var quelle: String?
    }
    public struct AufenthaltEintrag: Codable, Sendable {
        public var reise: String?
        public var hotel: String
        public var ort: String?
        public var anreise: Tag
        public var abreise: Tag
        public var quelle: String?
    }
    public struct TerminEintrag: Codable, Sendable {
        public var titel: String
        public var ort: String?
        public var beginn: Tag
        public var beginnZeit: String?
        public var ende: Tag?
        public var endeZeit: String?
        public var quelle: String?
    }
    public var abschnitte: [AbschnittEintrag]?
    public var aufenthalte: [AufenthaltEintrag]?
    public var termine: [TerminEintrag]?
}

public enum EreignisImport {
    public static func importiere(datei pfad: String, in datenbank: Datenbank) throws -> Importergebnis {
        let daten = try Data(contentsOf: URL(fileURLWithPath: pfad))
        return try importiere(JSONDecoder().decode(Ereignisse.self, from: daten), in: datenbank)
    }

    public static func importiere(_ ereignisse: Ereignisse, in datenbank: Datenbank) throws -> Importergebnis {
        var ergebnis = Importergebnis()
        try datenbank.queue.write { db in
            for eintrag in ereignisse.abschnitte ?? [] {
                guard try Reise.exists(db, key: eintrag.reise) else {
                    ergebnis.fehler.append("Abschnitt verweist auf unbekannte Reise \(eintrag.reise)"); continue
                }
                for zeit in [eintrag.abfahrt, eintrag.ankunft] {
                    if let zeit, Zeitpunkt(text: zeit) == nil {
                        ergebnis.fehler.append("Abschnitt \(eintrag.reise): Zeit unlesbar „\(zeit)“")
                    }
                }
                let schonDa = try Reiseabschnitt
                    .filter(Column("reiseId") == eintrag.reise && Column("abfahrt") == eintrag.abfahrt)
                    .filter(Column("von") == eintrag.von && Column("nach") == eintrag.nach)
                    .fetchCount(db) > 0
                if schonDa { ergebnis.bekannt += 1; continue }
                let nummer = try Reiseabschnitt.filter(Column("reiseId") == eintrag.reise).fetchCount(db) + 1
                var abschnitt = Reiseabschnitt(
                    id: nil, reiseId: eintrag.reise, reihenfolge: nummer, art: eintrag.art ?? "hauptlauf", von: eintrag.von,
                    nach: eintrag.nach, abfahrt: eintrag.abfahrt, ankunft: eintrag.ankunft, verkehrsmittel: eintrag.verkehrsmittel,
                    quelle: eintrag.quelle, sicherheit: .sicher)
                try abschnitt.insert(db)
                ergebnis.neu += 1
            }
            for eintrag in ereignisse.aufenthalte ?? [] {
                guard eintrag.anreise <= eintrag.abreise else {
                    ergebnis.fehler.append("Aufenthalt \(eintrag.hotel): Abreise liegt vor der Anreise"); continue
                }
                if let reise = eintrag.reise, try !Reise.exists(db, key: reise) {
                    ergebnis.fehler.append("Aufenthalt \(eintrag.hotel) verweist auf unbekannte Reise \(reise)"); continue
                }
                if try Hotelaufenthalt.filter(Column("hotel") == eintrag.hotel && Column("anreise") == eintrag.anreise).fetchCount(db) > 0 {
                    ergebnis.bekannt += 1; continue
                }
                var aufenthalt = Hotelaufenthalt(id: nil, reiseId: eintrag.reise, hotel: eintrag.hotel, ort: eintrag.ort,
                                                 anreise: eintrag.anreise, abreise: eintrag.abreise, quelle: eintrag.quelle)
                try aufenthalt.insert(db)
                ergebnis.neu += 1
            }
            for eintrag in ereignisse.termine ?? [] {
                if try Termin.filter(Column("titel") == eintrag.titel && Column("beginn") == eintrag.beginn).fetchCount(db) > 0 {
                    ergebnis.bekannt += 1; continue
                }
                var termin = Termin(id: nil, titel: eintrag.titel, ort: eintrag.ort, beginn: eintrag.beginn, beginnZeit: eintrag.beginnZeit,
                                    ende: eintrag.ende ?? eintrag.beginn, endeZeit: eintrag.endeZeit, quelle: eintrag.quelle)
                try termin.insert(db)
                ergebnis.neu += 1
            }
        }
        return ergebnis
    }
}

/// „JJJJ-MM-TT HH:MM“ (auch mit „T“). Ohne Zeitzone: Es gilt die Ortszeit des Fahrplans.
public struct Zeitpunkt: Comparable, Equatable, Sendable {
    public let tag: Tag
    public let stunde: Int
    public let minute: Int

    public init?(text: String) {
        let teile = text.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "T" })
        guard teile.count == 2, let tag = Tag(iso: String(teile[0])) else { return nil }
        let zeit = teile[1].split(separator: ":")
        guard zeit.count >= 2, let h = Int(zeit[0]), let m = Int(zeit[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.tag = tag
        self.stunde = h
        self.minute = m
    }

    public var uhrzeit: String { String(format: "%02d:%02d", stunde, minute) }

    public static func < (l: Zeitpunkt, r: Zeitpunkt) -> Bool {
        (l.tag, l.stunde, l.minute) < (r.tag, r.stunde, r.minute)
    }
}
