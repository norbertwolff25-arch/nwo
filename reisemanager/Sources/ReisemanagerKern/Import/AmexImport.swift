import Foundation
import GRDB

/// Liest den Amex-Export `activity.csv` (Komma, Datum TT/MM/JJJJ, Belastung positiv).
public enum AmexImport {
    static let noetig = ["Datum", "Beschreibung", "Betrag"]

    public static func importiere(datei pfad: String, in datenbank: Datenbank) throws -> Importergebnis {
        try importiere(text: Textnorm.dateiLesen(pfad), dateiname: URL(fileURLWithPath: pfad).lastPathComponent, in: datenbank)
    }

    public static func importiere(text: String, dateiname: String, in datenbank: Datenbank) throws -> Importergebnis {
        let (kopf, saetze) = CSV.datensaetze(text, trenner: ",")
        try Textnorm.pruefeSpalten(kopf, noetig: noetig, datei: dateiname)
        var ergebnis = Importergebnis()
        try datenbank.queue.write { db in
            for (index, satz) in saetze.enumerated() {
                let zeile = index + 2
                guard let datum = Tag(tagMonatJahr: satz["Datum"] ?? "") else {
                    ergebnis.fehler.append("Zeile \(zeile): Datum unlesbar"); continue
                }
                guard let belastung = Geld.cent(aus: satz["Betrag"] ?? "") else {
                    ergebnis.fehler.append("Zeile \(zeile): Betrag unlesbar"); continue
                }
                let haendler = (satz["Beschreibung"] ?? "").trimmingCharacters(in: .whitespaces)
                let betrag = -belastung
                let referenz = Textnorm.leerAlsNil(satz["Betreff"]?.trimmingCharacters(in: CharacterSet(charactersIn: "' ")))
                let id = "AMEX-" + (referenz ?? String(SHA256.hex(Data("\(datum)|\(betrag)|\(haendler)|\(zeile)".utf8)).prefix(16)))
                if try Zahlung.exists(db, key: id) { ergebnis.bekannt += 1; continue }
                if try ZahlungHerkunft.filter(Column("quelle") == Zahlungsquelle.amex.rawValue && Column("ref") == id).fetchCount(db) > 0 {
                    ergebnis.bekannt += 1; continue
                }
                let karte = letzteVier(satz["Konto #"])
                let fremd = fremdbetrag(aus: satz["Weitere Details"])

                // Derselbe Umsatz steht schon aus NWO-Pay in der Datenbank: Kartendaten ergänzen, nicht doppelt anlegen.
                if var vorhandene = try gleicherUmsatz(db, datum: datum, betrag: betrag, haendler: haendler) {
                    vorhandene.karteLetzteVier = vorhandene.karteLetzteVier ?? karte
                    if vorhandene.fremdbetragCent == nil, let fremd {
                        vorhandene.fremdbetragCent = fremd.cent
                        vorhandene.fremdwaehrung = fremd.waehrung
                    }
                    try vorhandene.update(db)
                    var herkunft = ZahlungHerkunft(id: nil, zahlungId: vorhandene.id, quelle: .amex, datei: dateiname, ref: id)
                    try herkunft.insert(db)
                    ergebnis.zusammengefuehrt += 1
                    continue
                }
                let zahlung = Zahlung(
                    id: id, quelle: .amex, konto: "Amex", datum: datum, betragCent: betrag, haendler: haendler,
                    zweck: nil, fremdbetragCent: fremd?.cent, fremdwaehrung: fremd?.waehrung, karteLetzteVier: karte,
                    externId: nil, kategorie: Textnorm.leerAlsNil(satz["Kategorie"]), zaehlt: true,
                    gepaartMitId: nil, paarSicherheit: nil, herkunftsdatei: dateiname, herkunftsRef: "Zeile \(zeile)")
                try zahlung.insert(db)
                var herkunft = ZahlungHerkunft(id: nil, zahlungId: id, quelle: .amex, datei: dateiname, ref: id)
                try herkunft.insert(db)
                ergebnis.neu += 1
            }
        }
        return ergebnis
    }

    /// Amex-Umsatz aus anderer Quelle mit gleichem Tag, Betrag und Händler, der noch keine Amex-Fundstelle hat.
    static func gleicherUmsatz(_ db: Database, datum: Tag, betrag: Int, haendler: String) throws -> Zahlung? {
        let kandidaten = try Zahlung
            .filter(Column("konto") == "Amex" && Column("quelle") != Zahlungsquelle.amex.rawValue)
            .filter(Column("datum") == datum && Column("betragCent") == betrag)
            .order(Column("id"))
            .fetchAll(db)
        let kern = Textnorm.kern(haendler)
        for kandidat in kandidaten {
            let anderer = Textnorm.kern(kandidat.haendler)
            guard !kern.isEmpty, !anderer.isEmpty, kern.hasPrefix(anderer) || anderer.hasPrefix(kern) else { continue }
            let schonVerbunden = try ZahlungHerkunft
                .filter(Column("zahlungId") == kandidat.id && Column("quelle") == Zahlungsquelle.amex.rawValue)
                .fetchCount(db) > 0
            if !schonVerbunden { return kandidat }
        }
        return nil
    }

    static func letzteVier(_ konto: String?) -> String? {
        let ziffern = (konto ?? "").filter(\.isNumber)
        return ziffern.count >= 4 ? String(ziffern.suffix(4)) : nil
    }

    static let waehrungen = [
        "pound sterling": "GBP", "us dollar": "USD", "u.s. dollar": "USD", "swiss franc": "CHF",
        "danish krone": "DKK", "swedish krona": "SEK", "norwegian krone": "NOK", "polish zloty": "PLN",
    ]

    /// Liest „Foreign Spend Amount: 16.20 Pound Sterling Commission Amount: …“ aus „Weitere Details“.
    static func fremdbetrag(aus details: String?) -> (cent: Int, waehrung: String)? {
        guard let details, let start = details.range(of: "Foreign Spend Amount:", options: .caseInsensitive) else { return nil }
        var rest = details[start.upperBound...].trimmingCharacters(in: .whitespaces)
        if let ende = rest.range(of: "Commission", options: .caseInsensitive) {
            rest = String(rest[..<ende.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        let teile = rest.split(separator: " ", maxSplits: 1).map(String.init)
        guard teile.count == 2, let cent = Geld.cent(aus: teile[0]) else { return nil }
        let name = teile[1].trimmingCharacters(in: .whitespaces)
        return (cent, waehrungen[name.lowercased()] ?? name)
    }
}
