import Foundation
import GRDB

/// Wendet gespeicherte Regeln an und protokolliert jede Änderung mit Regel und Sicherheitsstufe.
public enum Regelanwendung {
    public static let aktionStammeinsatz = "stammeinsatz"

    /// Regel „anlass enthält <Wort>“ → Reise ist Einsatz beim Stammkunden. Gesetzt wird nur, nie zurückgenommen:
    /// Ausnahmen markiert der Nutzer.
    @discardableResult
    static func stammeinsaetzeSetzen(_ db: Database) throws -> Int {
        let regeln = try Regel
            .filter(Column("aktiv") == true && Column("aktion") == aktionStammeinsatz && Column("feld") == "anlass")
            .order(Column("id")).fetchAll(db)
        guard !regeln.isEmpty else { return 0 }
        var gesetzt = 0
        let reisen = try Reise.filter(Column("art") == Reiseart.dienstreise.rawValue && Column("istStammeinsatz") == false).fetchAll(db)
        for var reise in reisen {
            guard let regel = regeln.first(where: { enthaeltWort(reise.anlass, $0.muster) }) else { continue }
            reise.istStammeinsatz = true
            try reise.update(db)
            var eintrag = Entscheidung(id: nil, objektTyp: "reise", objektId: reise.id, feld: "istStammeinsatz", wert: regel.wert,
                                       quelle: "Regel: Anlass enthält „\(regel.muster)“", regelId: regel.id, sicherheit: .wahrscheinlich,
                                       zeit: ISO8601DateFormatter().string(from: Date()))
            try eintrag.insert(db)
            gesetzt += 1
        }
        return gesetzt
    }

    /// Ganzes Wort, ohne Groß- und Kleinschreibung: „Berlin“ trifft „OID+Kunde Berlin“, „AB“ trifft nicht „Abo“.
    static func enthaeltWort(_ text: String, _ wort: String) -> Bool {
        let ziel = wort.lowercased()
        return text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).contains { $0 == ziel }
    }
}
