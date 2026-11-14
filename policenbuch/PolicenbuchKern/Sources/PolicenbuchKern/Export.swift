import Foundation

/// Export für den neuen Berater. Feldnamen angelehnt an GDV-Datensatz und BiPRO-Norm.
public enum BeraterExport {
    /// Spalten in fester Reihenfolge (CSV-Kopf = JSON-Schlüssel).
    public static let spalten = [
        "Versicherungsscheinnummer", "Versicherer", "Sparte", "Tarif",
        "Vertragsbeginn", "Vertragsablauf", "Kuendigungsfrist",
        "Beitrag", "Zahlungsweise", "Jahresbeitrag", "Waehrung", "Dynamik_Prozent",
        "Vertragsstatus", "Steuerliche_Einordnung", "Betreuer", "Anzahl_Dokumente", "Bemerkungen"
    ]

    public static func zeile(_ v: VertragsDaten, dokumente: Int) -> [String] {
        [
            v.vertragsnummer, v.versicherer, v.sparte, v.tarif,
            Datum.deutsch(v.beginn), Datum.deutsch(v.ablauf), v.kuendigungsfrist,
            v.beitrag.map { Zahl.deutsch($0) } ?? "", v.zahlweise?.anzeige ?? "",
            Zahl.deutsch(v.jahresbeitrag), "EUR", v.dynamikProzent.map { Zahl.deutsch($0) } ?? "",
            v.status.anzeige, v.steuerlicheEinordnung, v.betreuer?.anzeige ?? "", String(dokumente), v.notizen
        ]
    }

    /// CSV: UTF-8 mit BOM, Semikolon, Dezimalkomma, Datum TT.MM.JJJJ.
    public static func csv(_ vertraege: [VertragsDaten], dokumente: [DokumentDaten] = []) -> Data {
        let zeilen = sortiert(vertraege).map { v in zeile(v, dokumente: dokumente.filter { $0.vertragID == v.id }.count) }
        return CSV.schreiben(kopf: spalten, zeilen: zeilen)
    }

    public struct JSONVertrag: Codable, Equatable, Sendable {
        public var Versicherungsscheinnummer: String
        public var Versicherer: String
        public var Sparte: String
        public var Tarif: String?
        public var Vertragsbeginn: String?
        public var Vertragsablauf: String?
        public var Kuendigungsfrist: String?
        public var Beitrag: Decimal?
        public var Zahlungsweise: String?
        public var Jahresbeitrag: Decimal
        public var Waehrung: String
        public var Dynamik_Prozent: Decimal?
        public var Vertragsstatus: String
        public var Steuerliche_Einordnung: String?
        public var Betreuer: String?
        public var Bemerkungen: String?
        public var Dokumente: [JSONDokument]
    }

    public struct JSONDokument: Codable, Equatable, Sendable {
        public var Dokumentart: String
        public var Datum: String?
        /// Pfad innerhalb des ZIP-Archivs.
        public var Datei: String
    }

    public struct JSONHuelle: Codable, Equatable, Sendable {
        public var Format: String
        public var Erstellt: String
        public var Anzahl: Int
        public var Vertraege: [JSONVertrag]
    }

    public static func json(_ vertraege: [VertragsDaten], dokumente: [DokumentDaten] = [], erstellt: Date) throws -> Data {
        let namen = zipNamen(vertraege: vertraege, dokumente: dokumente)
        let liste = sortiert(vertraege).map { v -> JSONVertrag in
            func leer(_ s: String) -> String? { s.isEmpty ? nil : s }
            let docs = dokumente.filter { $0.vertragID == v.id }.map {
                JSONDokument(Dokumentart: $0.typ.rawValue, Datum: $0.datum.map { Datum.iso($0) }, Datei: namen[$0.id] ?? $0.dateiname)
            }
            return JSONVertrag(
                Versicherungsscheinnummer: v.vertragsnummer, Versicherer: v.versicherer, Sparte: v.sparte,
                Tarif: leer(v.tarif), Vertragsbeginn: v.beginn.map { Datum.iso($0) }, Vertragsablauf: v.ablauf.map { Datum.iso($0) },
                Kuendigungsfrist: leer(v.kuendigungsfrist), Beitrag: v.beitrag.map { Zahl.runden($0) },
                Zahlungsweise: v.zahlweise?.anzeige, Jahresbeitrag: Zahl.runden(v.jahresbeitrag), Waehrung: "EUR",
                Dynamik_Prozent: v.dynamikProzent, Vertragsstatus: v.status.anzeige,
                Steuerliche_Einordnung: leer(v.steuerlicheEinordnung), Betreuer: v.betreuer?.anzeige,
                Bemerkungen: leer(v.notizen), Dokumente: docs)
        }
        let huelle = JSONHuelle(Format: "Policenbuch-Beraterexport 1.0 (Feldnamen angelehnt an GDV/BiPRO)",
                                Erstellt: Datum.iso(erstellt), Anzahl: liste.count, Vertraege: liste)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(huelle)
    }

    static func sortiert(_ v: [VertragsDaten]) -> [VertragsDaten] {
        v.sorted { ($0.sparte, $0.versicherer, $0.vertragsnummer) < ($1.sparte, $1.versicherer, $1.vertragsnummer) }
    }

    /// Dateinamen im ZIP: `Dokumente/<Versicherer>_<Nummer>/<JJJJ-MM-TT>_<Typ>_<Original>.pdf`, eindeutig.
    public static func zipNamen(vertraege: [VertragsDaten], dokumente: [DokumentDaten]) -> [UUID: String] {
        var ergebnis: [UUID: String] = [:]
        var vergeben: Set<String> = []
        let nachID = Dictionary(vertraege.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for d in dokumente.sorted(by: { ($0.datum ?? .distantPast, $0.pfad) < ($1.datum ?? .distantPast, $1.pfad) }) {
            let ordner: String
            if let id = d.vertragID, let v = nachID[id] {
                ordner = dateiname(v.versicherer) + "_" + dateiname(v.vertragsnummer)
            } else {
                ordner = "ohne_Vertrag"
            }
            let datum = d.datum.map { Datum.iso($0) } ?? "ohne-Datum"
            let original = (d.dateiname as NSString).deletingPathExtension
            let endung = (d.dateiname as NSString).pathExtension.isEmpty ? "pdf" : (d.dateiname as NSString).pathExtension
            var name = "Dokumente/\(ordner)/\(datum)_\(d.typ.rawValue)_\(dateiname(original)).\(endung)"
            var n = 2
            while vergeben.contains(name) {
                name = "Dokumente/\(ordner)/\(datum)_\(d.typ.rawValue)_\(dateiname(original))_\(n).\(endung)"
                n += 1
            }
            vergeben.insert(name)
            ergebnis[d.id] = name
        }
        return ergebnis
    }

    /// Dateinamensicher, Umlaute bleiben erhalten.
    static func dateiname(_ s: String) -> String {
        let erlaubt = s.map { c -> Character in
            (c.isLetter || c.isNumber || c == "-" || c == "_") ? c : "_"
        }
        var t = String(erlaubt)
        while t.contains("__") { t = t.replacingOccurrences(of: "__", with: "_") }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return t.isEmpty ? "unbenannt" : String(t.prefix(60))
    }

    /// ZIP mit CSV, JSON und allen lesbaren Dokumenten. Fehlende Dateien werden im Ergebnis gemeldet.
    public static func zip(vertraege: [VertragsDaten], dokumente: [DokumentDaten], erstellt: Date,
                           lesen: (String) -> Data?) throws -> (daten: Data, fehlend: [String]) {
        var zip = ZipSchreiber()
        zip.hinzufuegen(name: "vertraege.csv", daten: csv(vertraege, dokumente: dokumente), datum: erstellt)
        zip.hinzufuegen(name: "vertraege.json", daten: try json(vertraege, dokumente: dokumente, erstellt: erstellt), datum: erstellt)
        var fehlend: [String] = []
        let namen = zipNamen(vertraege: vertraege, dokumente: dokumente)
        for d in dokumente {
            guard let name = namen[d.id] else { continue }
            if let daten = lesen(d.pfad) {
                zip.hinzufuegen(name: name, daten: daten, datum: d.datum ?? erstellt)
            } else {
                fehlend.append(d.pfad)
            }
        }
        return (zip.fertig(), fehlend)
    }
}

// MARK: - ZIP (ohne Kompression, plattformunabhängig)

public struct ZipSchreiber: Sendable {
    private var daten = Data()
    private var verzeichnis = Data()
    private var anzahl: UInt16 = 0

    public init() {}

    public mutating func hinzufuegen(name: String, daten inhalt: Data, datum: Date) {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.pruefsumme(inhalt)
        let (zeit, tag) = Self.dosZeit(datum)
        let offset = UInt32(daten.count)
        let groesse = UInt32(inhalt.count)

        var kopf = Data()
        kopf.le32(0x04034b50)
        kopf.le16(20)          // benötigte Version
        kopf.le16(0x0800)      // Bit 11: Dateiname UTF-8
        kopf.le16(0)           // Methode: gespeichert
        kopf.le16(zeit); kopf.le16(tag)
        kopf.le32(crc); kopf.le32(groesse); kopf.le32(groesse)
        kopf.le16(UInt16(nameBytes.count)); kopf.le16(0)
        daten.append(kopf); daten.append(nameBytes); daten.append(inhalt)

        var eintrag = Data()
        eintrag.le32(0x02014b50)
        eintrag.le16(0x0314)   // erstellt unter Unix, Version 20
        eintrag.le16(20); eintrag.le16(0x0800); eintrag.le16(0)
        eintrag.le16(zeit); eintrag.le16(tag)
        eintrag.le32(crc); eintrag.le32(groesse); eintrag.le32(groesse)
        eintrag.le16(UInt16(nameBytes.count)); eintrag.le16(0); eintrag.le16(0)
        eintrag.le16(0); eintrag.le16(0)
        eintrag.le32(0o100644 << 16) // Dateirechte rw-r--r--
        eintrag.le32(offset)
        verzeichnis.append(eintrag); verzeichnis.append(nameBytes)
        anzahl += 1
    }

    public func fertig() -> Data {
        var ergebnis = daten
        let start = UInt32(ergebnis.count)
        ergebnis.append(verzeichnis)
        var ende = Data()
        ende.le32(0x06054b50)
        ende.le16(0); ende.le16(0)
        ende.le16(anzahl); ende.le16(anzahl)
        ende.le32(UInt32(verzeichnis.count)); ende.le32(start)
        ende.le16(0)
        ergebnis.append(ende)
        return ergebnis
    }

    static func dosZeit(_ d: Date) -> (UInt16, UInt16) {
        let k = Datum.kalender.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let stunde: Int = k.hour ?? 0, minute: Int = k.minute ?? 0, sekunde: Int = k.second ?? 0
        let jahr: Int = max(0, (k.year ?? 1980) - 1980), monat: Int = k.month ?? 1, tagImMonat: Int = k.day ?? 1
        let zeitWert: Int = (stunde << 11) | (minute << 5) | (sekunde / 2)
        let tagWert: Int = (jahr << 9) | (monat << 5) | tagImMonat
        let zeit = UInt16(truncatingIfNeeded: zeitWert)
        let tag = UInt16(truncatingIfNeeded: tagWert)
        return (zeit, tag)
    }
}

public enum CRC32 {
    static let tabelle: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func pruefsumme(_ daten: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in daten { crc = tabelle[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func le16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
