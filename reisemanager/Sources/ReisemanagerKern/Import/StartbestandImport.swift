import Foundation
import GRDB

/// Startbestand als JSON. Entsteht aus der Arbeitsmappe über `werkzeuge/mappe_zu_startbestand.py`
/// und bleibt lokal: Die Datei enthält persönliche Daten und gehört nicht ins Repository.
public struct Startbestand: Codable, Sendable {
    public struct ReiseEintrag: Codable, Sendable {
        public var nr: String
        public var anlass: String
        public var beginn: Tag?
        public var ende: Tag?
        public var verkehrsmittel: String?
        public var unterkunft: String?
        public var offen: String?
    }
    public struct PositionEintrag: Codable, Sendable {
        public var reise: String?
        public var datum: Tag?
        public var quelle: String?
        public var kostenart: Kostenart
        public var kostenartText: String?
        public var haendler: String
        public var ort: String?
        public var betragCent: Int?
        public var zahlungId: String?
        public var belege: [String]?
        public var belegHinweis: String?
        public var vorschlag: String?
    }
    public struct PrivatEintrag: Codable, Sendable {
        public var nr: String
        public var reise: String
        public var beginn: Tag?
        public var ende: Tag?
        public var hinweis: String?
    }
    public struct SachkostenEintrag: Codable, Sendable {
        public var nr: String
        public var titel: String
        public var hinweis: String?
        public var positionen: [PositionEintrag]
    }
    public struct BelegEintrag: Codable, Sendable {
        public var nr: String
        public var dokument: String
        public var art: String?
        public var fundort: String?
        public var belegt: String?
        public var status: String?
    }
    public struct ConcurEintrag: Codable, Sendable {
        public var nr: String
        public var titel: String
        public var concurNr: String?
        public var hinweis: String?
    }
    /// Persönliche Regel, z. B. feld „anlass“, muster „<Ort>“, aktion „stammeinsatz“, wert „<Kunde>“.
    public struct RegelEintrag: Codable, Sendable {
        public var feld: String
        public var muster: String
        public var aktion: String
        public var wert: String
    }
    public struct OffenerPunktEintrag: Codable, Sendable {
        public var bezug: String?
        public var text: String
        public var fundort: String?
    }

    public var jahr: Int
    public var quelle: String?
    public var reisen: [ReiseEintrag]?
    public var positionen: [PositionEintrag]?
    public var privat: [PrivatEintrag]?
    public var offenePosten: [PositionEintrag]?
    public var sachkosten: [SachkostenEintrag]?
    public var belege: [BelegEintrag]?
    public var concur: [ConcurEintrag]?
    public var offenePunkte: [OffenerPunktEintrag]?
    public var regeln: [RegelEintrag]?
}

public enum StartbestandImport {
    public static func importiere(datei pfad: String, in datenbank: Datenbank) throws -> Importergebnis {
        let daten = try Data(contentsOf: URL(fileURLWithPath: pfad))
        let bestand = try JSONDecoder().decode(Startbestand.self, from: daten)
        return try importiere(bestand, in: datenbank)
    }

    /// Mehrere Dateien dürfen nacheinander eingelesen werden (Mappe, dann Concur-Entwürfe und offene Punkte).
    /// Reisen, Sachkosten und Belege werden über ihre Nummer wiedererkannt; Positionen kommen nur beim ersten Anlegen dazu.
    public static func importiere(_ bestand: Startbestand, in datenbank: Datenbank) throws -> Importergebnis {
        var ergebnis = Importergebnis()
        let herkunft = bestand.quelle ?? "Startbestand \(bestand.jahr)"
        try datenbank.queue.write { db in
            for eintrag in bestand.belege ?? [] {
                if try Beleg.exists(db, key: eintrag.nr) { ergebnis.bekannt += 1; continue }
                try Beleg(id: eintrag.nr, dokument: eintrag.dokument, art: eintrag.art, fundort: eintrag.fundort,
                          belegt: eintrag.belegt, status: eintrag.status).insert(db)
                ergebnis.neu += 1
            }
            var neueReisen: Set<String> = []
            for eintrag in bestand.reisen ?? [] {
                if try Reise.exists(db, key: eintrag.nr) { ergebnis.bekannt += 1; continue }
                try Reise(
                    id: eintrag.nr, art: .dienstreise, typ: nil, anlass: eintrag.anlass, ort: nil, istStammeinsatz: false,
                    beginn: eintrag.beginn, beginnZeit: nil, beginnQuelle: eintrag.beginn == nil ? nil : herkunft,
                    beginnSicherheit: eintrag.beginn == nil ? nil : .geschaetzt,
                    ende: eintrag.ende, endeZeit: nil, endeQuelle: eintrag.ende == nil ? nil : herkunft,
                    endeSicherheit: eintrag.ende == nil ? nil : .geschaetzt,
                    verkehrsmittel: Textnorm.leerAlsNil(eintrag.verkehrsmittel), unterkunft: Textnorm.leerAlsNil(eintrag.unterkunft),
                    hinweis: nil, status: .erkannt, concurNr: nil, concurTitel: nil).insert(db)
                neueReisen.insert(eintrag.nr)
                ergebnis.neu += 1
                if let offen = Textnorm.leerAlsNil(eintrag.offen) {
                    var punkt = OffenerPunkt(id: nil, reiseId: eintrag.nr, sachkostenId: nil, text: offen, fundort: nil, erledigt: false, herkunft: herkunft)
                    try punkt.insert(db)
                }
            }
            for eintrag in bestand.privat ?? [] {
                if try Reise.exists(db, key: eintrag.nr) { ergebnis.bekannt += 1; continue }
                try Reise(
                    id: eintrag.nr, art: .privat, typ: nil, anlass: eintrag.reise, ort: nil, istStammeinsatz: false,
                    beginn: eintrag.beginn, beginnZeit: nil, beginnQuelle: herkunft, beginnSicherheit: nil,
                    ende: eintrag.ende, endeZeit: nil, endeQuelle: herkunft, endeSicherheit: nil,
                    verkehrsmittel: nil, unterkunft: nil, hinweis: eintrag.hinweis, status: .bestaetigt,
                    concurNr: nil, concurTitel: nil).insert(db)
                ergebnis.neu += 1
            }
            for eintrag in bestand.positionen ?? [] {
                guard let reise = eintrag.reise else {
                    ergebnis.fehler.append("Position ohne Reise: \(eintrag.haendler)"); continue
                }
                guard neueReisen.contains(reise) else {
                    if try Reise.exists(db, key: reise) { ergebnis.bekannt += 1 }
                    else { ergebnis.fehler.append("Position verweist auf unbekannte Reise \(reise): \(eintrag.haendler)") }
                    continue
                }
                try positionAnlegen(db, eintrag, reiseId: reise, sachkostenId: nil, ergebnis: &ergebnis)
            }
            if try Position.filter(Column("vorschlag") != nil).fetchCount(db) == 0 {
                for eintrag in bestand.offenePosten ?? [] {
                    try positionAnlegen(db, eintrag, reiseId: nil, sachkostenId: nil, ergebnis: &ergebnis)
                }
            }
            for eintrag in bestand.sachkosten ?? [] {
                if try Sachkostenabrechnung.exists(db, key: eintrag.nr) { ergebnis.bekannt += 1; continue }
                try Sachkostenabrechnung(id: eintrag.nr, titel: eintrag.titel, hinweis: Textnorm.leerAlsNil(eintrag.hinweis),
                                         status: .erkannt, concurNr: nil, concurTitel: nil).insert(db)
                ergebnis.neu += 1
                for position in eintrag.positionen {
                    try positionAnlegen(db, position, reiseId: nil, sachkostenId: eintrag.nr, ergebnis: &ergebnis)
                }
            }
            for eintrag in bestand.concur ?? [] {
                if var reise = try Reise.fetchOne(db, key: eintrag.nr) {
                    reise.concurNr = eintrag.concurNr
                    reise.concurTitel = eintrag.titel
                    if Reisestatus.allCases.firstIndex(of: reise.status)! < Reisestatus.allCases.firstIndex(of: .concurEntwurf)! {
                        reise.status = .concurEntwurf
                    }
                    try reise.update(db)
                } else if var sachkosten = try Sachkostenabrechnung.fetchOne(db, key: eintrag.nr) {
                    sachkosten.concurNr = eintrag.concurNr
                    sachkosten.concurTitel = eintrag.titel
                    sachkosten.status = .concurEntwurf
                    try sachkosten.update(db)
                } else if eintrag.nr.hasPrefix("S") {
                    try Sachkostenabrechnung(id: eintrag.nr, titel: eintrag.titel, hinweis: nil, status: .concurEntwurf,
                                             concurNr: eintrag.concurNr, concurTitel: eintrag.titel).insert(db)
                    ergebnis.neu += 1
                } else {
                    ergebnis.fehler.append("Concur-Entwurf \(eintrag.nr) passt zu keiner Reise"); continue
                }
                if !Abrechnungstitel.istGueltig(eintrag.titel) {
                    try punktAnlegen(db, bezug: eintrag.nr, text: "Concur-Titel hat \(eintrag.titel.count) Zeichen, erlaubt sind \(Abrechnungstitel.maxLaenge): „\(eintrag.titel)“", fundort: "Concur", herkunft: herkunft)
                }
                if eintrag.concurNr == nil {
                    try punktAnlegen(db, bezug: eintrag.nr, text: "Concur-Nummer prüfen", fundort: "Concur", herkunft: herkunft)
                }
                if let hinweis = Textnorm.leerAlsNil(eintrag.hinweis) {
                    try punktAnlegen(db, bezug: eintrag.nr, text: hinweis, fundort: "Concur", herkunft: herkunft)
                }
            }
            for eintrag in bestand.offenePunkte ?? [] {
                try punktAnlegen(db, bezug: eintrag.bezug, text: eintrag.text, fundort: eintrag.fundort, herkunft: herkunft)
            }
            for eintrag in bestand.regeln ?? [] {
                let schonDa = try Regel
                    .filter(Column("feld") == eintrag.feld && Column("muster") == eintrag.muster)
                    .filter(Column("aktion") == eintrag.aktion && Column("wert") == eintrag.wert)
                    .fetchCount(db) > 0
                if schonDa { ergebnis.bekannt += 1; continue }
                var regel = Regel(id: nil, feld: eintrag.feld, muster: eintrag.muster, aktion: eintrag.aktion, wert: eintrag.wert,
                                  herkunft: herkunft, aktiv: true)
                try regel.insert(db)
                ergebnis.neu += 1
            }
            try Regelanwendung.stammeinsaetzeSetzen(db)
        }
        return ergebnis
    }

    static func positionAnlegen(_ db: Database, _ eintrag: Startbestand.PositionEintrag, reiseId: String?, sachkostenId: String?,
                                ergebnis: inout Importergebnis) throws {
        var vorauskauf = false
        if let reiseId, let datum = eintrag.datum, let reise = try Reise.fetchOne(db, key: reiseId), let beginn = reise.beginn {
            vorauskauf = datum < beginn
        }
        var position = Position(
            id: nil, reiseId: reiseId, sachkostenId: sachkostenId, datum: eintrag.datum, quelle: Textnorm.leerAlsNil(eintrag.quelle),
            kostenart: eintrag.kostenart, kostenartText: Textnorm.leerAlsNil(eintrag.kostenartText), haendler: eintrag.haendler,
            ort: Textnorm.leerAlsNil(eintrag.ort), betragCent: eintrag.betragCent, fremdbetragCent: nil, fremdwaehrung: nil,
            zahlungId: Textnorm.leerAlsNil(eintrag.zahlungId), privatVorgestreckt: true, erstattung: .offen, vorauskauf: vorauskauf,
            belegHinweis: Textnorm.leerAlsNil(eintrag.belegHinweis), vorschlag: Textnorm.leerAlsNil(eintrag.vorschlag))
        try position.insert(db)
        ergebnis.neu += 1
        for nummer in eintrag.belege ?? [] {
            if try Beleg.exists(db, key: nummer) {
                try PositionBeleg(positionId: position.id!, belegId: nummer).insert(db)
            } else {
                ergebnis.fehler.append("Position „\(eintrag.haendler)“ nennt unbekannten Beleg \(nummer)")
            }
        }
    }

    static func punktAnlegen(_ db: Database, bezug: String?, text: String, fundort: String?, herkunft: String) throws {
        var reiseId: String?
        var sachkostenId: String?
        if let bezug {
            if try Reise.exists(db, key: bezug) { reiseId = bezug }
            else if try Sachkostenabrechnung.exists(db, key: bezug) { sachkostenId = bezug }
        }
        let schonDa = try OffenerPunkt
            .filter(Column("text") == text && Column("reiseId") == reiseId && Column("sachkostenId") == sachkostenId)
            .fetchCount(db) > 0
        guard !schonDa else { return }
        var punkt = OffenerPunkt(id: nil, reiseId: reiseId, sachkostenId: sachkostenId, text: text, fundort: fundort, erledigt: false, herkunft: herkunft)
        try punkt.insert(db)
    }
}
