import Foundation

/// Ergebnis eines Vertragsimports vor dem Abgleich mit dem Bestand.
public struct VertragsImport: Sendable {
    public var vertraege: [VertragsDaten]
    /// Warnungen je Datenzeile (1-basiert, ohne Kopfzeile).
    public var warnungen: [(zeile: Int, text: String)]
    public var quelle: String

    public init(vertraege: [VertragsDaten], warnungen: [(zeile: Int, text: String)], quelle: String) {
        self.vertraege = vertraege
        self.warnungen = warnungen
        self.quelle = quelle
    }
}

// MARK: - 1. versicherungsbestand_*.csv

public enum BestandImport {
    /// Passt der Dateiname zum Muster `versicherungsbestand_*.csv`?
    public static func passt(dateiname: String) -> Bool {
        let n = dateiname.lowercased()
        return n.hasPrefix("versicherungsbestand_") && n.hasSuffix(".csv")
    }

    public static func lesen(_ daten: Data, dateiname: String = "versicherungsbestand.csv") throws -> VertragsImport {
        let tabelle = try CSV.tabelle(aus: daten)
        return lesen(tabelle, quelle: dateiname)
    }

    public static func lesen(_ tabelle: CSVTabelle, quelle: String, zuordnung: Feldzuordnung? = nil) -> VertragsImport {
        let zuordnung = zuordnung ?? (BeraterExport.istEigenerExport(kopf: tabelle.kopf)
            ? BeraterExport.csvZuordnung
            : Feldzuordnung.automatisch(fuer: tabelle.kopf))
        var vertraege: [VertragsDaten] = []
        var warnungen: [(Int, String)] = []
        for (i, zeile) in tabelle.zeilen.enumerated() {
            var paare: [(String, String)] = []
            for (j, name) in tabelle.kopf.enumerated() where !name.isEmpty {
                paare.append((name, j < zeile.count ? zeile[j] : ""))
            }
            // überzählige Zellen ohne Kopf nicht verlieren
            if zeile.count > tabelle.kopf.count {
                for j in tabelle.kopf.count..<zeile.count where !zeile[j].isEmpty {
                    paare.append(("Spalte \(j + 1)", zeile[j]))
                }
            }
            let (v, w) = zuordnung.vertrag(aus: paare, quelle: quelle, deutscheZahlen: true)
            vertraege.append(v)
            warnungen += w.map { (i + 1, $0) }
        }
        return VertragsImport(vertraege: vertraege, warnungen: warnungen, quelle: quelle)
    }
}

// MARK: - 2. DSGVO-Export von Clark (JSON oder CSV)

/// Rohdatensätze aus einem Fremdexport, bevor der Nutzer die Feldzuordnung bestätigt.
public struct Rohexport: Sendable, Equatable {
    /// Alle vorkommenden Feldnamen in stabiler Reihenfolge (verschachtelt als „a.b“).
    public var felder: [String]
    /// Datensätze als geordnete Paare (Feldname, Wert).
    public var datensaetze: [[Feldwert]]
    public var quelle: String
    /// JSON-Zahlen sind immer englisch notiert, CSV meist deutsch.
    public var deutscheZahlen: Bool

    public struct Feldwert: Sendable, Equatable {
        public var feld: String
        public var wert: String
    }

    /// Beispielwerte je Feld für den Zuordnungsdialog.
    public func beispiel(fuer feld: String) -> String {
        for d in datensaetze {
            if let w = d.first(where: { $0.feld == feld })?.wert, !w.isEmpty { return w }
        }
        return ""
    }

    public func importieren(mit zuordnung: Feldzuordnung) -> VertragsImport {
        var vertraege: [VertragsDaten] = []
        var warnungen: [(Int, String)] = []
        for (i, d) in datensaetze.enumerated() {
            var (v, w) = zuordnung.vertrag(aus: d.map { ($0.feld, $0.wert) }, quelle: quelle, deutscheZahlen: deutscheZahlen)
            if v.betreuer == nil { v.betreuer = .clark }
            vertraege.append(v)
            warnungen += w.map { (i + 1, $0) }
        }
        return VertragsImport(vertraege: vertraege, warnungen: warnungen, quelle: quelle)
    }
}

public enum ClarkImportFehler: Error, LocalizedError, Equatable {
    case keineVertraegeGefunden
    case ungueltigesFormat(String)

    public var errorDescription: String? {
        switch self {
        case .keineVertraegeGefunden: "Im Export wurde keine Liste von Verträgen gefunden."
        case .ungueltigesFormat(let s): "Das Exportformat ist nicht lesbar: \(s)"
        }
    }
}

public enum ClarkImport {
    public static func lesen(_ daten: Data, dateiname: String) throws -> Rohexport {
        let endung = (dateiname as NSString).pathExtension.lowercased()
        if endung == "json" || daten.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) }).map({ $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) == true {
            return try json(daten, quelle: dateiname)
        }
        let tabelle = try CSV.tabelle(aus: daten)
        let datensaetze = tabelle.zeilen.map { zeile in
            tabelle.kopf.enumerated().compactMap { (j, name) -> Rohexport.Feldwert? in
                name.isEmpty ? nil : Rohexport.Feldwert(feld: name, wert: j < zeile.count ? zeile[j] : "")
            }
        }
        return Rohexport(felder: tabelle.kopf.filter { !$0.isEmpty }, datensaetze: datensaetze,
                         quelle: dateiname, deutscheZahlen: true)
    }

    /// Sucht im JSON die größte Liste von Objekten (Verträge) und flacht verschachtelte Felder ab.
    public static func json(_ daten: Data, quelle: String) throws -> Rohexport {
        var d = daten
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        let wurzel: Any
        do {
            wurzel = try JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
        } catch {
            throw ClarkImportFehler.ungueltigesFormat(error.localizedDescription)
        }
        guard let liste = besteListe(in: wurzel, pfad: "") else { throw ClarkImportFehler.keineVertraegeGefunden }

        var felder: [String] = []
        var bekannt: Set<String> = []
        var datensaetze: [[Rohexport.Feldwert]] = []
        for objekt in liste.objekte {
            var paare: [Rohexport.Feldwert] = []
            abflachen(objekt, praefix: "", in: &paare)
            for p in paare where !bekannt.contains(p.feld) {
                bekannt.insert(p.feld)
                felder.append(p.feld)
            }
            datensaetze.append(paare)
        }
        return Rohexport(felder: felder, datensaetze: datensaetze, quelle: quelle, deutscheZahlen: false)
    }

    private struct Kandidat {
        var objekte: [[String: Any]]
        var punkte: Int
    }

    private static let vertragsWoerter = ["contract", "vertr", "polic", "insurance", "versicherung", "product"]

    private static func besteListe(in wert: Any, pfad: String) -> Kandidat? {
        var beste: Kandidat? = nil
        func pruefen(_ k: Kandidat?) {
            guard let k else { return }
            if beste == nil || k.punkte > beste!.punkte { beste = k }
        }
        if let array = wert as? [Any] {
            let objekte = array.compactMap { $0 as? [String: Any] }
            if !objekte.isEmpty && objekte.count == array.count {
                // Punkte: Anzahl Objekte, Bonus wenn Pfad nach Verträgen klingt oder Felder erkannt werden
                let p = pfad.lowercased()
                var punkte = objekte.count
                if vertragsWoerter.contains(where: { p.contains($0) }) { punkte += 1000 }
                let schluessel = objekte.first.map { Array($0.keys) } ?? []
                punkte += 10 * schluessel.filter { Zielfeld.vorschlag(fuer: $0) != nil }.count
                pruefen(Kandidat(objekte: objekte, punkte: punkte))
            }
            for (i, element) in array.enumerated() { pruefen(besteListe(in: element, pfad: pfad + "[\(i)]")) }
        } else if let objekt = wert as? [String: Any] {
            for (k, v) in objekt { pruefen(besteListe(in: v, pfad: pfad + "." + k)) }
        }
        // Einzelnes Vertragsobjekt auf oberster Ebene
        if beste == nil, pfad.isEmpty, let objekt = wert as? [String: Any] {
            return Kandidat(objekte: [objekt], punkte: 1)
        }
        return beste
    }

    private static func abflachen(_ wert: Any, praefix: String, in paare: inout [Rohexport.Feldwert]) {
        if let objekt = wert as? [String: Any] {
            for k in objekt.keys.sorted() {
                abflachen(objekt[k]!, praefix: praefix.isEmpty ? k : praefix + "." + k, in: &paare)
            }
        } else if let array = wert as? [Any] {
            if array.allSatisfy({ !($0 is [String: Any]) && !($0 is [Any]) }) {
                paare.append(.init(feld: praefix, wert: array.map(text).joined(separator: ", ")))
            } else {
                for (i, e) in array.enumerated() { abflachen(e, praefix: "\(praefix)[\(i)]", in: &paare) }
            }
        } else {
            paare.append(.init(feld: praefix, wert: text(wert)))
        }
    }

    private static func text(_ wert: Any) -> String {
        switch wert {
        case is NSNull: return ""
        case let s as String: return s
        case let n as NSNumber:
            #if canImport(Darwin)
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "ja" : "nein" }
            #endif
            return n.stringValue
        default: return "\(wert)"
        }
    }
}

// MARK: - 3. NWO-Pay-CSV

public enum PayImport {
    /// Liest NWO-Pay (`pay_id;konto;art;datum;richtung;betrag;gegenpartei;zweck;…`).
    public static func lesen(_ daten: Data, dateiname: String = "nwo-pay.csv") throws -> (zahlungen: [ZahlungsDaten], warnungen: [(zeile: Int, text: String)]) {
        let tabelle = try CSV.tabelle(aus: daten)
        let index = Dictionary(tabelle.kopf.enumerated().map { (Textnorm.schluessel($1), $0) }, uniquingKeysWith: { a, _ in a })
        func wert(_ zeile: [String], _ namen: String...) -> String {
            for n in namen { if let i = index[n], i < zeile.count { return zeile[i].trimmingCharacters(in: .whitespaces) } }
            return ""
        }
        var zahlungen: [ZahlungsDaten] = []
        var warnungen: [(Int, String)] = []
        for (i, zeile) in tabelle.zeilen.enumerated() {
            let nr = i + 1
            guard let datum = Datum.lesen(wert(zeile, "datum", "buchungstag", "valuta")) else {
                warnungen.append((nr, "Datum fehlt oder ist unlesbar")); continue
            }
            guard var betrag = Zahl.lesen(wert(zeile, "betrag", "amount")) else {
                warnungen.append((nr, "Betrag fehlt oder ist unlesbar")); continue
            }
            let richtung = Textnorm.schluessel(wert(zeile, "richtung", "direction"))
            let ausgang = ["aus", "ausgang", "ausgabe", "soll", "out", "debit", "lastschrift", "s"].contains(richtung)
            let eingang = ["ein", "eingang", "einnahme", "haben", "in", "credit", "gutschrift", "h"].contains(richtung)
            if ausgang { betrag = -abs(betrag) } else if eingang { betrag = abs(betrag) }

            let gegenpartei = wert(zeile, "gegenpartei", "empfaenger", "auftraggeber")
            let zweck = wert(zeile, "zweck", "verwendungszweck", "buchungstext")
            let art = wert(zeile, "art")
            let konto = wert(zeile, "konto")
            let id = wert(zeile, "payid", "id")
            let text = [gegenpartei, zweck].filter { !$0.isEmpty }.joined(separator: " – ")
            var quelle = "NWO-Pay"
            if !konto.isEmpty { quelle += " (\(konto)\(art.isEmpty ? "" : ", \(art)"))" }
            zahlungen.append(ZahlungsDaten(externeID: id.isEmpty ? nil : "nwo-pay:\(id)", datum: datum, betrag: betrag,
                                           buchungstext: text, quelle: quelle))
        }
        return (zahlungen, warnungen)
    }
}

// MARK: - Zuordnung Zahlung → Vertrag

public enum ZahlungsZuordnung {
    public static let mindestlaenge = 5

    /// Sucht die Vertragsnummer im Buchungstext. Trennzeichen und Leerzeichen werden ignoriert.
    /// Bei mehreren Treffern gewinnt die längste Nummer; gleich lange Treffer gelten als mehrdeutig (nil).
    public static func vertrag(fuer buchungstext: String, in vertraege: [VertragsDaten]) -> UUID? {
        let text = Textnorm.vertragsnummer(buchungstext)
        guard !text.isEmpty else { return nil }
        var treffer: [(UUID, Int)] = []
        for v in vertraege {
            let nr = Textnorm.vertragsnummer(v.vertragsnummer)
            guard nr.count >= mindestlaenge else { continue }
            if enthaeltAlsGanzes(text: text, nummer: nr, roh: buchungstext) { treffer.append((v.id, nr.count)) }
        }
        guard let laengste = treffer.map(\.1).max() else { return nil }
        let beste = treffer.filter { $0.1 == laengste }
        let ids = Set(beste.map(\.0))
        return ids.count == 1 ? ids.first : nil
    }

    /// Verhindert, dass „12345“ in „9123456“ erkannt wird: Im Rohtext darf direkt davor/danach keine Ziffer stehen.
    static func enthaeltAlsGanzes(text: String, nummer: String, roh: String) -> Bool {
        guard text.contains(nummer) else { return false }
        // Rohtext auf Ziffern/Buchstaben plus Grenzen prüfen
        let zeichen = Array(roh.uppercased())
        let ziel = Array(nummer)
        var i = 0
        while i < zeichen.count {
            // Startposition muss Ziffer/Buchstabe sein und am Wortanfang bzgl. Alnum-Sequenz
            if zeichen[i] == ziel[0] {
                var j = i, k = 0
                while j < zeichen.count, k < ziel.count {
                    let c = zeichen[j]
                    if c.isLetter || c.isNumber {
                        if c != ziel[k] { break }
                        k += 1
                    } else if !" -./_".contains(c) {
                        break
                    }
                    j += 1
                }
                if k == ziel.count {
                    let davor = i > 0 ? zeichen[i - 1] : " "
                    let danach = j < zeichen.count ? zeichen[j] : " "
                    let grenzeVorne = !(davor.isNumber || davor.isLetter && ziel[0].isLetter)
                    let grenzeHinten = !(danach.isNumber || danach.isLetter && ziel[ziel.count - 1].isLetter)
                    if grenzeVorne && grenzeHinten { return true }
                }
            }
            i += 1
        }
        return false
    }

    /// Ordnet alle noch nicht zugeordneten Zahlungen zu. Gibt die Anzahl neuer Zuordnungen zurück.
    @discardableResult
    public static func zuordnen(_ zahlungen: inout [ZahlungsDaten], vertraege: [VertragsDaten]) -> Int {
        var anzahl = 0
        for i in zahlungen.indices where zahlungen[i].vertragID == nil {
            if let id = vertrag(fuer: zahlungen[i].buchungstext, in: vertraege) {
                zahlungen[i].vertragID = id
                anzahl += 1
            }
        }
        return anzahl
    }
}
