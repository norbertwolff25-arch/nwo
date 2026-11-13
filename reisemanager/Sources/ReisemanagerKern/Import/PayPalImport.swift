import Foundation
import GRDB

/// Liest den PayPal-Aktivitätenexport (Komma, Datum TT.MM.JJJJ, Abgang negativ).
public enum PayPalImport {
    static let noetig = ["Datum", "Name", "Währung", "Brutto", "Transaktionscode"]

    public static func importiere(datei pfad: String, in datenbank: Datenbank) throws -> Importergebnis {
        try importiere(text: Textnorm.dateiLesen(pfad), dateiname: URL(fileURLWithPath: pfad).lastPathComponent, in: datenbank)
    }

    public static func importiere(text: String, dateiname: String, in datenbank: Datenbank) throws -> Importergebnis {
        let (kopf, saetze) = CSV.datensaetze(text, trenner: ",")
        try Textnorm.pruefeSpalten(kopf, noetig: noetig, datei: dateiname)
        var ergebnis = Importergebnis()
        try datenbank.queue.write { db in
            // Euro-Gegenwerte aus den Zeilen „Währungsumrechnung“, je zugehörigem Transaktionscode.
            var euroGegenwert: [String: Int] = [:]
            for satz in saetze {
                let typ = (satz["Typ"] ?? satz["Beschreibung"] ?? "").lowercased()
                guard typ.contains("währungsumrechnung") || typ.contains("currency conversion"),
                      satz["Währung"] == "EUR", let bezug = Textnorm.leerAlsNil(satz["Zugehöriger Transaktionscode"]),
                      let cent = Geld.cent(aus: satz["Brutto"] ?? ""), cent < 0 else { continue }
                euroGegenwert[bezug] = cent
            }
            for (index, satz) in saetze.enumerated() {
                let zeile = index + 2
                guard let code = Textnorm.leerAlsNil(satz["Transaktionscode"]) else {
                    ergebnis.fehler.append("Zeile \(zeile): Transaktionscode fehlt"); continue
                }
                let id = "PP-" + code
                if try Zahlung.exists(db, key: id) { ergebnis.bekannt += 1; continue }
                if try Zahlung.filter(Column("externId") == id).fetchCount(db) > 0 { ergebnis.bekannt += 1; continue }
                guard let datum = Tag(tagMonatJahr: satz["Datum"] ?? "") else {
                    ergebnis.fehler.append("Zeile \(zeile) (\(code)): Datum unlesbar"); continue
                }
                guard let brutto = Geld.cent(aus: satz["Brutto"] ?? "") else {
                    ergebnis.fehler.append("Zeile \(zeile) (\(code)): Betrag unlesbar"); continue
                }
                let name = (satz["Name"] ?? "").trimmingCharacters(in: .whitespaces)
                let waehrung = (satz["Währung"] ?? "").trimmingCharacters(in: .whitespaces)
                let typ = Textnorm.leerAlsNil(satz["Typ"] ?? satz["Beschreibung"])
                let istEuro = waehrung == "EUR"
                let zahlung = Zahlung(
                    id: id, quelle: .paypal, konto: "PayPal", datum: datum,
                    betragCent: istEuro ? brutto : euroGegenwert[code],
                    haendler: name, zweck: typ,
                    fremdbetragCent: istEuro ? nil : brutto, fremdwaehrung: istEuro ? nil : waehrung,
                    karteLetzteVier: nil, externId: id, kategorie: nil,
                    // Umbuchungen und Umrechnungen ohne Händler sind Gegenbuchungen.
                    zaehlt: !name.isEmpty && brutto < 0,
                    gepaartMitId: nil, paarSicherheit: nil, herkunftsdatei: dateiname, herkunftsRef: "Tx \(code)")
                try zahlung.insert(db)
                var herkunft = ZahlungHerkunft(id: nil, zahlungId: id, quelle: .paypal, datei: dateiname, ref: code)
                try herkunft.insert(db)
                ergebnis.neu += 1
            }
        }
        return ergebnis
    }
}
