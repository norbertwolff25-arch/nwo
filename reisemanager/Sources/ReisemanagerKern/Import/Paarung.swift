import Foundation
import GRDB

/// Paart PayPal-Zahlungen mit ihrer Amex-Finanzierung: gleicher Betrag, Datum ±3 Tage, Händler.
/// Zählen danach beide Seiten, führt die PayPal-Seite und die Amex-Seite zählt nicht mehr.
public enum Paarung {
    public static let tageFenster = 3

    @discardableResult
    public static func paareBilden(in datenbank: Datenbank) throws -> Int {
        try datenbank.queue.write { db in
            var gepaart = 0
            let amexSeiten = try Zahlung
                .filter(Column("konto") == "Amex" && Column("gepaartMitId") == nil && Column("betragCent") != nil)
                .filter(Column("haendler").like("PAYPAL%"))
                .order(Column("datum"), Column("id"))
                .fetchAll(db)
            for var amex in amexSeiten {
                guard let betrag = amex.betragCent else { continue }
                let kandidaten = try Zahlung
                    .filter(Column("konto") == "PayPal" && Column("gepaartMitId") == nil && Column("betragCent") == betrag)
                    .order(Column("datum"), Column("id"))
                    .fetchAll(db)
                    .filter { abs(amex.datum.abstandInTagen(zu: $0.datum)) <= tageFenster }
                guard !kandidaten.isEmpty else { continue }
                let marke = haendlermarke(amex.haendler)
                let mitNamen = kandidaten.filter { passt(marke: marke, name: $0.haendler) }

                let wahl: Zahlung
                let sicherheit: Sicherheit
                if mitNamen.count == 1 {
                    wahl = mitNamen[0]; sicherheit = .sicher
                } else if mitNamen.count > 1 {
                    wahl = naechste(mitNamen, zu: amex.datum); sicherheit = .wahrscheinlich
                } else if kandidaten.count == 1 {
                    wahl = kandidaten[0]; sicherheit = .wahrscheinlich
                } else {
                    continue // mehrere Kandidaten ohne Händlertreffer: nicht raten
                }
                var paypal = wahl
                paypal.gepaartMitId = amex.id
                paypal.paarSicherheit = sicherheit
                paypal.karteLetzteVier = paypal.karteLetzteVier ?? amex.karteLetzteVier
                try paypal.update(db)
                amex.gepaartMitId = paypal.id
                amex.paarSicherheit = sicherheit
                // Nur wenn beide Seiten zählen, droht Doppelzählung. NWO-Pay hat das oft schon entschieden.
                if amex.zaehlt && paypal.zaehlt { amex.zaehlt = false }
                try amex.update(db)
                gepaart += 1
            }
            return gepaart
        }
    }

    /// „PAYPAL *TESTFLUGRE 4029357733“ → „TESTFLUGRE“.
    static func haendlermarke(_ amexText: String) -> String {
        var rest = amexText
        if let stern = rest.firstIndex(of: "*") { rest = String(rest[rest.index(after: stern)...]) }
        let worte = rest.split(separator: " ").filter { !$0.allSatisfy(\.isNumber) }
        return Textnorm.kern(worte.joined())
    }

    static func passt(marke: String, name: String) -> Bool {
        let kern = Textnorm.kern(name)
        guard marke.count >= 3, kern.count >= 3 else { return false }
        if kern.hasPrefix(marke) || marke.hasPrefix(kern) { return true }
        return zip(marke, kern).prefix(while: { $0 == $1 }).count >= 5
    }

    static func naechste(_ kandidaten: [Zahlung], zu datum: Tag) -> Zahlung {
        kandidaten.min { abs(datum.abstandInTagen(zu: $0.datum)) < abs(datum.abstandInTagen(zu: $1.datum)) }!
    }
}
