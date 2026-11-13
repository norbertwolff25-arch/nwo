import Foundation
import GRDB

/// Liest `NWO_Pay_<Jahr>_Zahlungen.csv` (Semikolon, Dezimalkomma, Datum JJJJ-MM-TT).
public enum NWOPayImport {
    static let noetig = ["pay_id", "konto", "datum", "betrag", "gegenpartei", "zaehlt"]

    public static func importiere(datei pfad: String, in datenbank: Datenbank) throws -> Importergebnis {
        try importiere(text: Textnorm.dateiLesen(pfad), dateiname: URL(fileURLWithPath: pfad).lastPathComponent, in: datenbank)
    }

    public static func importiere(text: String, dateiname: String, in datenbank: Datenbank) throws -> Importergebnis {
        let (kopf, saetze) = CSV.datensaetze(text, trenner: ";")
        try Textnorm.pruefeSpalten(kopf, noetig: noetig, datei: dateiname)
        var ergebnis = Importergebnis()
        try datenbank.queue.write { db in
            for (index, satz) in saetze.enumerated() {
                let zeile = index + 2
                guard let id = Textnorm.leerAlsNil(satz["pay_id"]) else {
                    ergebnis.fehler.append("Zeile \(zeile): pay_id fehlt"); continue
                }
                if try Zahlung.exists(db, key: id) { ergebnis.bekannt += 1; continue }
                guard let datum = Tag(iso: satz["datum"] ?? "") else {
                    ergebnis.fehler.append("Zeile \(zeile) (\(id)): Datum unlesbar"); continue
                }
                guard let betrag = Geld.cent(aus: satz["betrag"] ?? "") else {
                    ergebnis.fehler.append("Zeile \(zeile) (\(id)): Betrag unlesbar"); continue
                }
                let externId = Textnorm.leerAlsNil(satz["gesamt_id"])
                let herkunftsdatei = Textnorm.leerAlsNil(satz["quelle_datei"]) ?? dateiname

                // Dieselbe Zahlung liegt schon aus einem Direktimport vor (z. B. PayPal-Export): nur die Fundstelle ergänzen.
                if let externId, let vorhandene = try Zahlung.filter(Column("externId") == externId).fetchOne(db) {
                    var herkunft = ZahlungHerkunft(id: nil, zahlungId: vorhandene.id, quelle: .nwoPay, datei: dateiname, ref: id)
                    try herkunft.insert(db)
                    ergebnis.zusammengefuehrt += 1
                    continue
                }
                let zahlung = Zahlung(
                    id: id, quelle: .nwoPay, konto: satz["konto"] ?? "", datum: datum, betragCent: betrag,
                    haendler: satz["gegenpartei"] ?? "", zweck: Textnorm.leerAlsNil(satz["zweck"]),
                    fremdbetragCent: nil, fremdwaehrung: nil, karteLetzteVier: nil, externId: externId,
                    kategorie: Textnorm.leerAlsNil(satz["kategorie"]), zaehlt: satz["zaehlt"]?.trimmingCharacters(in: .whitespaces) == "1",
                    gepaartMitId: nil, paarSicherheit: nil, herkunftsdatei: herkunftsdatei,
                    herkunftsRef: Textnorm.leerAlsNil(satz["quelle_ref"]))
                try zahlung.insert(db)
                var herkunft = ZahlungHerkunft(id: nil, zahlungId: id, quelle: .nwoPay, datei: dateiname, ref: id)
                try herkunft.insert(db)
                ergebnis.neu += 1
            }
        }
        return ergebnis
    }
}
