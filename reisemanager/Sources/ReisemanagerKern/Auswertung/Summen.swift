import Foundation
import GRDB

/// Summen je Reise im Aufbau der Arbeitsmappe: Fahrt, Unterkunft, Sonstiges.
public struct Reisesumme: Equatable, Sendable {
    public var fahrtCent = 0
    public var unterkunftCent = 0
    public var sonstigesCent = 0
    /// Positionen, deren Betrag noch fehlt. Sie zählen mit 0 und bleiben offene Punkte.
    public var ohneBetrag = 0
    public var summeCent: Int { fahrtCent + unterkunftCent + sonstigesCent }

    public init() {}

    mutating func addiere(_ position: Position) {
        guard let cent = position.betragCent else { ohneBetrag += 1; return }
        switch position.kostenart.summenspalte {
        case .fahrt: fahrtCent += cent
        case .unterkunft: unterkunftCent += cent
        case .sonstiges: sonstigesCent += cent
        }
    }

    mutating func addiere(_ andere: Reisesumme) {
        fahrtCent += andere.fahrtCent
        unterkunftCent += andere.unterkunftCent
        sonstigesCent += andere.sonstigesCent
        ohneBetrag += andere.ohneBetrag
    }
}

public enum Summen {
    public static func jeReise(in datenbank: Datenbank) throws -> [String: Reisesumme] {
        try datenbank.queue.read { db in
            var ergebnis: [String: Reisesumme] = [:]
            for position in try Position.filter(Column("reiseId") != nil).fetchAll(db) {
                ergebnis[position.reiseId!, default: Reisesumme()].addiere(position)
            }
            return ergebnis
        }
    }

    /// Gesamtsumme aller Dienstreisen. Privatreisen gehen nie ein.
    public static func dienstreisen(in datenbank: Datenbank) throws -> Reisesumme {
        let je = try jeReise(in: datenbank)
        let dienstlich = try datenbank.queue.read { db in
            try Reise.filter(Column("art") == Reiseart.dienstreise.rawValue).fetchAll(db).map(\.id)
        }
        var gesamt = Reisesumme()
        for id in dienstlich { gesamt.addiere(je[id] ?? Reisesumme()) }
        return gesamt
    }

    public static func jeSachkostenabrechnung(in datenbank: Datenbank) throws -> [String: Reisesumme] {
        try datenbank.queue.read { db in
            var ergebnis: [String: Reisesumme] = [:]
            for position in try Position.filter(Column("sachkostenId") != nil).fetchAll(db) {
                ergebnis[position.sachkostenId!, default: Reisesumme()].addiere(position)
            }
            return ergebnis
        }
    }
}
