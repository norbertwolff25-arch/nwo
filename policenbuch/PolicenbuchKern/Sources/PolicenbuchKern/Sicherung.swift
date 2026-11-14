import Foundation

/// Vollständige Sicherung aller Daten als JSON-Datei (lokal, vom Nutzer gespeichert).
/// Die PDFs selbst gehören nicht dazu, nur ihre Pfade und der erkannte Text.
public struct Sicherung: Codable, Sendable, Equatable {
    public static let kennung = "Policenbuch-Sicherung"
    public static let aktuelleVersion = 1

    public var format: String
    public var version: Int
    public var erstellt: Date
    public var vertraege: [VertragsDaten]
    public var zahlungen: [ZahlungsDaten]
    public var dokumente: [Dokument]
    public var aufgaben: [AufgabeDaten]

    public struct Dokument: Codable, Sendable, Equatable {
        public var daten: DokumentDaten
        public var erkannterText: String
        public var kandidaten: String

        public init(daten: DokumentDaten, erkannterText: String, kandidaten: String) {
            self.daten = daten
            self.erkannterText = erkannterText
            self.kandidaten = kandidaten
        }
    }

    public init(erstellt: Date, vertraege: [VertragsDaten], zahlungen: [ZahlungsDaten],
                dokumente: [Dokument], aufgaben: [AufgabeDaten]) {
        format = Self.kennung
        version = Self.aktuelleVersion
        self.erstellt = erstellt
        self.vertraege = vertraege
        self.zahlungen = zahlungen
        self.dokumente = dokumente
        self.aufgaben = aufgaben
    }

    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    public enum Fehler: Error, LocalizedError, Equatable {
        case keineSicherung
        case neuereVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .keineSicherung: "Die Datei ist keine Policenbuch-Sicherung."
            case .neuereVersion(let v): "Die Sicherung stammt aus einer neueren Version (Format \(v)). Bitte die App aktualisieren."
            }
        }
    }

    public static func lesen(_ daten: Data) throws -> Sicherung {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let s = try? d.decode(Sicherung.self, from: daten), s.format == kennung else { throw Fehler.keineSicherung }
        guard s.version <= aktuelleVersion else { throw Fehler.neuereVersion(s.version) }
        return s.bereinigt()
    }

    /// Verweise auf nicht vorhandene Verträge werden gelöst statt die Sicherung abzulehnen.
    public func bereinigt() -> Sicherung {
        var s = self
        let ids = Set(vertraege.map(\.id))
        for i in s.zahlungen.indices where s.zahlungen[i].vertragID.map({ !ids.contains($0) }) ?? false {
            s.zahlungen[i].vertragID = nil
        }
        for i in s.dokumente.indices where s.dokumente[i].daten.vertragID.map({ !ids.contains($0) }) ?? false {
            s.dokumente[i].daten.vertragID = nil
        }
        for i in s.aufgaben.indices where s.aufgaben[i].vertragID.map({ !ids.contains($0) }) ?? false {
            s.aufgaben[i].vertragID = nil
        }
        return s
    }

    public var zusammenfassung: String {
        "\(vertraege.count) Verträge, \(zahlungen.count) Zahlungen, \(dokumente.count) Dokumente, \(aufgaben.count) Aufgaben"
    }
}

// MARK: - Rückimport des eigenen Berater-Exports

extension BeraterExport {
    /// Erkennt eine CSV-Kopfzeile aus `BeraterExport.csv`.
    public static func istEigenerExport(kopf: [String]) -> Bool {
        kopf.contains("Versicherungsscheinnummer") && kopf.contains("Anzahl_Dokumente")
    }

    /// Feste Zuordnung für den eigenen CSV-Export: abgeleitete Spalten werden nicht in Notizen kopiert.
    public static var csvZuordnung: Feldzuordnung {
        var z = Feldzuordnung.automatisch(fuer: spalten)
        z.zuordnung["Waehrung"] = .ignorieren
        z.zuordnung["Anzahl_Dokumente"] = .ignorieren
        z.zuordnung["Jahresbeitrag"] = .jahresbeitrag
        return z
    }

    /// Liest einen JSON-Export (`vertraege.json`) zurück. Verträge erhalten neue IDs und laufen danach
    /// durch den normalen Dublettenabgleich.
    public static func vertraege(ausJSON daten: Data, quelle: String) throws -> VertragsImport {
        let huelle: JSONHuelle
        do {
            huelle = try JSONDecoder().decode(JSONHuelle.self, from: daten)
        } catch {
            throw ClarkImportFehler.ungueltigesFormat("kein Policenbuch-Beraterexport")
        }
        var warnungen: [(zeile: Int, text: String)] = []
        let vertraege = huelle.Vertraege.enumerated().map { (i, j) -> VertragsDaten in
            var v = VertragsDaten(
                versicherer: j.Versicherer, sparte: j.Sparte, vertragsnummer: j.Versicherungsscheinnummer,
                tarif: j.Tarif ?? "", beginn: j.Vertragsbeginn.flatMap(Datum.lesen), ablauf: j.Vertragsablauf.flatMap(Datum.lesen),
                kuendigungsfrist: j.Kuendigungsfrist ?? "", beitrag: j.Beitrag, zahlweise: j.Zahlungsweise.flatMap(Zahlweise.erkennen),
                dynamikProzent: j.Dynamik_Prozent, status: VertragsStatus.erkennen(j.Vertragsstatus) ?? .pruefen,
                steuerlicheEinordnung: j.Steuerliche_Einordnung ?? "", betreuer: j.Betreuer.flatMap(Betreuer.erkennen),
                notizen: j.Bemerkungen ?? "")
            if j.Waehrung != "EUR" { v.notizAnhaengen("Waehrung: \(j.Waehrung)") }
            if !j.Dokumente.isEmpty {
                warnungen.append((i + 1, "\(j.Dokumente.count) Dokumente zu \(j.Versicherungsscheinnummer) bitte per PDF-Ordner einlesen"))
            }
            return v
        }
        return VertragsImport(vertraege: vertraege, warnungen: warnungen, quelle: quelle)
    }
}
