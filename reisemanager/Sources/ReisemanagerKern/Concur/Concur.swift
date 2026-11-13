import Foundation
import GRDB

// MARK: - Bestand aus Concur (nur gelesen)

public struct ConcurAbrechnung: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "concurAbrechnung"
    public var nr: String
    public var titel: String
    public var status: String?
    public var betragCent: Int?
    public var gelesenAm: String?
}

/// Position in Concur. Ohne Abrechnungsnummer ist es eine „Verfügbare Ausgabe“ (ExpenseIt, E-Beleg).
public struct ConcurPosition: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "concurPosition"
    public var id: Int64?
    public var abrechnungNr: String?
    public var datum: Tag?
    public var ausgabentyp: String?
    public var lieferant: String?
    public var betragCent: Int?
    public var waehrung: String?
    public var hatBeleg: Bool
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Was der Zugang aus Concur liest: bestehende Abrechnungen und verfügbare Ausgaben.
public struct ConcurBestand: Codable, Sendable {
    public struct Position: Codable, Sendable {
        public var datum: Tag?
        public var ausgabentyp: String?
        public var lieferant: String?
        public var betragCent: Int?
        public var waehrung: String?
        public var hatBeleg: Bool?
        public init(datum: Tag?, ausgabentyp: String?, lieferant: String?, betragCent: Int?, waehrung: String? = "EUR", hatBeleg: Bool? = false) {
            self.datum = datum; self.ausgabentyp = ausgabentyp; self.lieferant = lieferant
            self.betragCent = betragCent; self.waehrung = waehrung; self.hatBeleg = hatBeleg
        }
    }
    public struct Abrechnung: Codable, Sendable {
        public var nr: String
        public var titel: String
        public var status: String?
        public var betragCent: Int?
        public var positionen: [Position]?
        public init(nr: String, titel: String, status: String?, betragCent: Int?, positionen: [Position]?) {
            self.nr = nr; self.titel = titel; self.status = status; self.betragCent = betragCent; self.positionen = positionen
        }
    }
    public var gelesenAm: String?
    public var abrechnungen: [Abrechnung]
    public var verfuegbareAusgaben: [Position]?
    public init(gelesenAm: String?, abrechnungen: [Abrechnung], verfuegbareAusgaben: [Position]?) {
        self.gelesenAm = gelesenAm; self.abrechnungen = abrechnungen; self.verfuegbareAusgaben = verfuegbareAusgaben
    }

    /// Ersetzt den gespeicherten Stand: Concur ist die Quelle, der lokale Abzug nur ein Abbild.
    @discardableResult
    public func uebernehmen(in datenbank: Datenbank) throws -> Importergebnis {
        var ergebnis = Importergebnis()
        try datenbank.queue.write { db in
            try ConcurPosition.deleteAll(db)
            try ConcurAbrechnung.deleteAll(db)
            func speichern(_ p: Position, nr: String?) throws {
                var position = ConcurPosition(id: nil, abrechnungNr: nr, datum: p.datum, ausgabentyp: p.ausgabentyp, lieferant: p.lieferant,
                                              betragCent: p.betragCent, waehrung: p.waehrung, hatBeleg: p.hatBeleg ?? false)
                try position.insert(db)
                ergebnis.neu += 1
            }
            for a in abrechnungen {
                try ConcurAbrechnung(nr: a.nr, titel: a.titel, status: a.status, betragCent: a.betragCent, gelesenAm: gelesenAm).insert(db)
                ergebnis.neu += 1
                for p in a.positionen ?? [] { try speichern(p, nr: a.nr) }
            }
            for p in verfuegbareAusgaben ?? [] { try speichern(p, nr: nil) }

            // Fehlt einer eigenen Abrechnung die Concur-Nummer und gibt es in Concur genau einen Entwurf mit demselben Titel,
            // wird dessen Nummer übernommen. So entsteht kein zweiter Entwurf.
            func nummerZu(_ titel: String?) -> String? {
                guard let titel else { return nil }
                let gleiche = abrechnungen.filter { $0.titel == titel }
                return gleiche.count == 1 ? gleiche[0].nr : nil
            }
            for var reise in try Reise.filter(Column("concurNr") == nil && Column("concurTitel") != nil).fetchAll(db) {
                guard let nr = nummerZu(reise.concurTitel) else { continue }
                reise.concurNr = nr
                try reise.update(db)
                try uebernahmeProtokollieren(db, bezug: reise.id, nr: nr)
                ergebnis.zusammengefuehrt += 1
            }
            for var s in try Sachkostenabrechnung.filter(Column("concurNr") == nil && Column("concurTitel") != nil).fetchAll(db) {
                guard let nr = nummerZu(s.concurTitel) else { continue }
                s.concurNr = nr
                try s.update(db)
                try uebernahmeProtokollieren(db, bezug: s.id, nr: nr)
                ergebnis.zusammengefuehrt += 1
            }
            var lesung = ConcurProtokolleintrag(id: nil, bezug: "-", schritt: ConcurBestand.schrittLesen,
                                                beschreibung: "Concur-Stand gelesen: \(abrechnungen.count) Abrechnungen, \((verfuegbareAusgaben ?? []).count) verfügbare Ausgaben",
                                                ergebnis: "ok", zeit: gelesenAm ?? ISO8601DateFormatter().string(from: Date()))
            try lesung.insert(db)
        }
        return ergebnis
    }

    static let schrittLesen = "lesen"

    private func uebernahmeProtokollieren(_ db: Database, bezug: String, nr: String) throws {
        var eintrag = Entscheidung(id: nil, objektTyp: "abrechnung", objektId: bezug, feld: "concurNr", wert: nr,
                                   quelle: "Concur-Stand: Entwurf mit gleichem Titel", regelId: nil, sicherheit: .wahrscheinlich,
                                   zeit: ISO8601DateFormatter().string(from: Date()))
        try eintrag.insert(db)
        try OffenerPunkt.filter(Column("text") == "Concur-Nummer prüfen" && (Column("reiseId") == bezug || Column("sachkostenId") == bezug))
            .updateAll(db, Column("erledigt").set(to: true))
    }

    /// Wann der Concur-Stand zuletzt gelesen wurde. nil = noch nie.
    public static func zuletztGelesen(in datenbank: Datenbank) throws -> String? {
        try datenbank.queue.read { try zuletztGelesen($0) }
    }

    static func zuletztGelesen(_ db: Database) throws -> String? {
        try ConcurProtokolleintrag.filter(Column("schritt") == schrittLesen).order(Column("id").desc).fetchOne(db)?.zeit
    }

    public static func laden(datei pfad: String) throws -> ConcurBestand {
        try JSONDecoder().decode(ConcurBestand.self, from: Data(contentsOf: URL(fileURLWithPath: pfad)))
    }
}

// MARK: - Abgleich

public struct Abgleichseintrag: Equatable, Sendable {
    public enum Art: String, Sendable {
        /// Noch nicht in Concur: neu erfassen.
        case neu
        /// Steht schon in der eigenen Abrechnung.
        case schonErfasst
        /// Steht in einer anderen Abrechnung, z. B. einer Monatsabrechnung: nicht doppelt abrechnen.
        case inAndererAbrechnung
        /// Liegt als „Verfügbare Ausgabe“ vor: zuordnen statt neu erfassen.
        case verfuegbareAusgabe
        /// Ohne Betrag: kann nicht erfasst werden.
        case ohneBetrag
    }
    public var bezug: String
    public var positionId: Int64
    public var art: Art
    public var concurNr: String?
    public var hatBeleg: Bool
    public var text: String
}

/// Gleicht die eigenen Positionen gegen den Concur-Bestand ab: gleicher Betrag, Datum höchstens einen Tag auseinander.
public enum ConcurAbgleich {
    public static func abgleichen(in datenbank: Datenbank) throws -> [Abgleichseintrag] {
        try datenbank.queue.read { try abgleichen($0) }
    }

    static func abgleichen(_ db: Database) throws -> [Abgleichseintrag] {
        var frei = try ConcurPosition.order(Column("id")).fetchAll(db)
        let titel = try ConcurAbrechnung.fetchAll(db).reduce(into: [String: String]()) { $0[$1.nr] = $1.titel }
        var nummern: [String: String] = [:]
        for reise in try Reise.filter(Column("concurNr") != nil).fetchAll(db) { nummern[reise.id] = reise.concurNr }
        for s in try Sachkostenabrechnung.filter(Column("concurNr") != nil).fetchAll(db) { nummern[s.id] = s.concurNr }
        let privat = Set(try Reise.filter(Column("art") == Reiseart.privat.rawValue).fetchAll(db).map(\.id))

        var ergebnis: [Abgleichseintrag] = []
        for p in try Position.order(Column("id")).fetchAll(db) {
            guard let bezug = p.reiseId ?? p.sachkostenId, !privat.contains(bezug), let pid = p.id else { continue }
            let name = "\(p.haendler)\(p.datum.map { " (\($0))" } ?? "")"
            guard let betrag = p.betragCent else {
                ergebnis.append(Abgleichseintrag(bezug: bezug, positionId: pid, art: .ohneBetrag, concurNr: nil, hatBeleg: false,
                                                 text: "\(name): ohne Betrag, wird nicht erfasst"))
                continue
            }
            let eigene = nummern[bezug]
            let treffer = frei.enumerated().filter { _, c in
                guard c.betragCent == betrag, let d1 = p.datum, let d2 = c.datum else { return false }
                return abs(d1.abstandInTagen(zu: d2)) <= 1
            }
            // Von der App schon erfasst: Das gilt auch, wenn der gelesene Concur-Stand älter ist und die Ausgabe
            // dort noch als verfügbar steht. Der passende Eintrag wird verbraucht, damit ihn keine andere Position bekommt.
            if let nr = p.concurErfasstIn {
                if let (index, _) = treffer.first(where: { $0.element.abrechnungNr == nr }) ?? treffer.first(where: { $0.element.abrechnungNr == nil }) {
                    frei.remove(at: index)
                }
                ergebnis.append(Abgleichseintrag(bezug: bezug, positionId: pid, art: .schonErfasst, concurNr: nr, hatBeleg: false,
                                                 text: "\(name): von der App in \(nr) erfasst"))
                continue
            }
            // Vorrang: eigene Abrechnung, dann andere Abrechnung, dann verfügbare Ausgabe.
            let wahl = treffer.first { $0.element.abrechnungNr != nil && $0.element.abrechnungNr == eigene }
                ?? treffer.first { $0.element.abrechnungNr != nil }
                ?? treffer.first
            if let (index, c) = wahl {
                frei.remove(at: index)
                if let nr = c.abrechnungNr, nr == eigene {
                    ergebnis.append(Abgleichseintrag(bezug: bezug, positionId: pid, art: .schonErfasst, concurNr: nr, hatBeleg: c.hatBeleg,
                                                     text: "\(name): schon in \(nr) erfasst"))
                } else if let nr = c.abrechnungNr {
                    let wo = titel[nr].map { "„\($0)“ (\(nr))" } ?? nr
                    ergebnis.append(Abgleichseintrag(bezug: bezug, positionId: pid, art: .inAndererAbrechnung, concurNr: nr, hatBeleg: c.hatBeleg,
                                                     text: "\(name): steht schon in der Abrechnung \(wo) – nicht doppelt abrechnen"))
                } else {
                    ergebnis.append(Abgleichseintrag(bezug: bezug, positionId: pid, art: .verfuegbareAusgabe, concurNr: nil, hatBeleg: c.hatBeleg,
                                                     text: "\(name): liegt als verfügbare Ausgabe vor – zuordnen statt neu erfassen"))
                }
            } else {
                ergebnis.append(Abgleichseintrag(bezug: bezug, positionId: pid, art: .neu, concurNr: nil, hatBeleg: false, text: "\(name): neu erfassen"))
            }
        }
        return ergebnis
    }
}

// MARK: - Plan (Vorschau)

/// Ein Schreibvorgang in Concur. Einen Schritt „senden“ gibt es nicht: Eingereicht wird nie von der App.
public struct ConcurSchritt: Codable, Equatable, Sendable {
    public enum Art: String, Codable, Sendable {
        case kopfAnlegen, reiseverlaufSetzen, positionErfassen, verfuegbareAusgabeZuordnen, belegHochladen, loeschen
    }
    public struct Feld: Codable, Equatable, Sendable {
        public var name: String
        public var wert: String
    }
    public var art: Art
    public var bezug: String
    public var positionId: Int64?
    public var felder: [Feld]
    public var beschreibung: String

    public func wert(_ name: String) -> String? { felder.first { $0.name == name }?.wert }
}

public struct ConcurPlan: Equatable, Sendable {
    public var bezug: String
    public var concurNr: String?
    public var titel: String
    public var schritte: [ConcurSchritt]
    /// Was bewusst nicht geschrieben wird, und warum.
    public var hinweise: [String]
    /// Was vor dem Schreiben geklärt sein muss.
    public var blocker: [String]
    /// Prüfsumme der Schritte. Eine Freigabe gilt nur für genau diesen Plan.
    public var hash: String
    public var istAusfuehrbar: Bool { blocker.isEmpty && !schritte.isEmpty }
}

public enum ConcurRegeln {
    /// Schaltflächen, die die Automatisierung nie betätigt, in keiner Sprache der Oberfläche.
    public static let verboteneBeschriftungen = [
        "Abrechnung senden", "Abrechnung einreichen", "Senden", "Einreichen", "Submit Report", "Submit", "Akzeptieren und senden", "Accept & Submit",
    ]
}

public enum ConcurPlanung {
    public enum Fehler: Error, CustomStringConvertible {
        case unbekannt(String)
        public var description: String {
            if case .unbekannt(let bezug) = self { return "\(bezug) gibt es nicht" }
            return ""
        }
    }

    public static func plan(in datenbank: Datenbank, bezug: String, einstellungen: Einstellungen?) throws -> ConcurPlan {
        try datenbank.queue.read { try plan($0, bezug: bezug, einstellungen: einstellungen) }
    }

    static func plan(_ db: Database, bezug: String, einstellungen: Einstellungen?) throws -> ConcurPlan {
        let reise = try Reise.fetchOne(db, key: bezug)
        let sachkosten = try Sachkostenabrechnung.fetchOne(db, key: bezug)
        guard reise != nil || sachkosten != nil else { throw Fehler.unbekannt(bezug) }
        var schritte: [ConcurSchritt] = []
        var hinweise: [String] = []
        var blocker: [String] = []
        func feld(_ name: String, _ wert: String) -> ConcurSchritt.Feld { .init(name: name, wert: wert) }

        if reise?.art == .privat { blocker.append("Privatreise: wird nicht abgerechnet") }
        // Ohne gelesenen Concur-Stand ist unbekannt, was dort schon steht. Dann wird nichts geschrieben.
        if try ConcurBestand.zuletztGelesen(db) == nil {
            blocker.append("Concur-Stand noch nicht gelesen: erst mit bestehenden Abrechnungen und verfügbaren Ausgaben abgleichen")
        }
        let nummer = reise?.concurNr ?? sachkosten?.concurNr

        // Titel: vorhandener Concur-Titel, sonst nach dem Muster gebildet. Zu lange Titel werden nicht gekürzt.
        var titel = reise?.concurTitel ?? sachkosten?.concurTitel ?? sachkosten?.titel ?? ""
        if titel.isEmpty, let reise, let beginn = reise.beginn, let ende = reise.ende {
            switch Abrechnungstitel.bilden(anlass: reise.anlass, ort: reise.ort, beginn: beginn, ende: ende) {
            case .success(let gebildet): titel = gebildet
            case .failure(let zuLang):
                titel = zuLang.titel
                blocker.append("Titel hat \(zuLang.laenge) Zeichen, erlaubt sind \(Abrechnungstitel.maxLaenge): kürzeren Anlass wählen")
            }
        }

        if nummer == nil, let vorhanden = try ConcurAbrechnung.filter(Column("titel") == titel).fetchAll(db).first, !titel.isEmpty {
            blocker.append("In Concur gibt es schon „\(titel)“ (\(vorhanden.nr)): Nummer zuordnen statt neu anlegen")
        }
        if nummer == nil {
            if titel.isEmpty { blocker.append("Titel fehlt: Beginn und Ende der Reise nachtragen") }
            else if !Abrechnungstitel.istGueltig(titel), !blocker.contains(where: { $0.hasPrefix("Titel hat") }) {
                blocker.append("Titel hat \(titel.count) Zeichen, erlaubt sind \(Abrechnungstitel.maxLaenge)")
            }
            if let c = einstellungen?.concur {
                schritte.append(ConcurSchritt(art: .kopfAnlegen, bezug: bezug, positionId: nil, felder: [
                    feld("Titel", titel), feld("Logical System", c.logicalSystem), feld("Company Code", c.companyCode),
                    feld("Business Area", c.businessArea), feld("Cost Object Type", c.costObjectType), feld("Cost Object ID", c.costObjectId),
                    feld("Tagespauschalen", reise == nil ? "nein" : "ja"),
                ], beschreibung: "Abrechnung „\(titel)“ als Entwurf anlegen"))
            } else {
                blocker.append("Einstellungen fehlen: Concur-Kopfdaten")
            }
        }

        // Reiseverlauf: Abreise und Ankunft an der Privatadresse, mit Vor- und Nachlauf.
        if let reise, reise.art == .dienstreise {
            let schonGesetzt = try ConcurProtokolleintrag
                .filter(Column("bezug") == bezug && Column("schritt") == ConcurSchritt.Art.reiseverlaufSetzen.rawValue && Column("ergebnis") == "ok")
                .fetchCount(db) > 0
            if !schonGesetzt {
                if let beginn = reise.beginn, let ende = reise.ende, let von = reise.beginnZeit, let bis = reise.endeZeit {
                    if let adresse = einstellungen?.privatadresse {
                        var felder = [
                            feld("Abreise", "\(adresse.strasse), \(adresse.plz) \(adresse.ort)"), feld("Beginn", "\(beginn.iso) \(von)"),
                            feld("Ankunft", "\(adresse.strasse), \(adresse.plz) \(adresse.ort)"), feld("Ende", "\(ende.iso) \(bis)"),
                            feld("Tätigkeitsstätte", reise.ort ?? reise.anlass),
                        ]
                        let abschnitte = try Reiseabschnitt.filter(Column("reiseId") == bezug).order(Column("abfahrt"), Column("reihenfolge")).fetchAll(db)
                        for (index, a) in abschnitte.enumerated() {
                            felder.append(feld("Abschnitt \(index + 1)", "\(a.art): \(a.von ?? "?") \(a.abfahrt ?? "?") → \(a.nach ?? "?") \(a.ankunft ?? "?")\(a.verkehrsmittel.map { ", \($0)" } ?? "")"))
                        }
                        schritte.append(ConcurSchritt(art: .reiseverlaufSetzen, bezug: bezug, positionId: nil, felder: felder,
                                                      beschreibung: "Reiseverlauf \(beginn.iso) \(von) bis \(ende.iso) \(bis) ab und bis Privatadresse"))
                    } else {
                        blocker.append("Einstellungen fehlen: Privatadresse für den Reiseverlauf")
                    }
                } else {
                    hinweise.append("Reiseverlauf wird noch nicht gesetzt: Uhrzeiten für Beginn und Ende fehlen")
                }
            }
        }

        // Positionen nach dem Abgleich.
        let typen = einstellungen?.ausgabentypen ?? [:]
        var fehlendeTypen: Set<String> = []
        for eintrag in try ConcurAbgleich.abgleichen(db).filter({ $0.bezug == bezug }) {
            guard let p = try Position.fetchOne(db, key: eintrag.positionId) else { continue }
            var schreibt = false
            switch eintrag.art {
            case .ohneBetrag, .inAndererAbrechnung:
                hinweise.append(eintrag.text)
            case .schonErfasst:
                break
            case .verfuegbareAusgabe:
                schritte.append(ConcurSchritt(art: .verfuegbareAusgabeZuordnen, bezug: bezug, positionId: p.id, felder: [
                    feld("Datum", p.datum?.iso ?? ""), feld("Betrag", Geld.text(cent: p.betragCent ?? 0)), feld("Lieferant", p.haendler),
                ], beschreibung: "Verfügbare Ausgabe zuordnen: \(p.haendler), \(Geld.text(cent: p.betragCent ?? 0)) €"))
                schreibt = true
            case .neu:
                let klasse = Haendlerklasse.bestimme(Zuordnung.haendlername(p.haendler)).rawValue
                let typ = typen[klasse] ?? typen[p.kostenart.rawValue]
                if typ == nil { fehlendeTypen.insert(typen[klasse] == nil && Haendlerklasse(rawValue: klasse) != .sonstige ? klasse : p.kostenart.rawValue) }
                var felder = [
                    feld("Ausgabentyp", typ ?? ""), feld("Datum", p.datum?.iso ?? ""), feld("Betrag", Geld.text(cent: p.betragCent ?? 0)),
                    feld("Währung", "EUR"), feld("Lieferant", p.haendler), feld("Zahlungsart", "privat vorgestreckt"),
                ]
                if let fremd = p.fremdbetragCent { felder.append(feld("Fremdbetrag", "\(Geld.text(cent: fremd)) \(p.fremdwaehrung ?? "")")) }
                schritte.append(ConcurSchritt(art: .positionErfassen, bezug: bezug, positionId: p.id, felder: felder,
                                              beschreibung: "Position erfassen: \(p.haendler), \(p.datum?.iso ?? "ohne Datum"), \(Geld.text(cent: p.betragCent ?? 0)) €"))
                schreibt = true
            }
            // Belegbild hochladen, wenn eines da ist und Concur noch keines hat.
            if schreibt || (eintrag.art == .schonErfasst && !eintrag.hatBeleg && p.concurErfasstIn == nil) {
                let bild = try String.fetchOne(db, sql: """
                    SELECT b.pfad FROM belegbild b JOIN belegbildBeleg bb ON bb.belegbildId = b.id
                    JOIN positionBeleg pb ON pb.belegId = bb.belegId
                    WHERE pb.positionId = ? AND b.dubletteVonId IS NULL ORDER BY b.id LIMIT 1
                    """, arguments: [p.id])
                if let bild {
                    schritte.append(ConcurSchritt(art: .belegHochladen, bezug: bezug, positionId: p.id, felder: [feld("Datei", bild)],
                                                  beschreibung: "Belegbild hochladen: \(bild)"))
                } else if schreibt {
                    hinweise.append("\(p.haendler)\(p.datum.map { " (\($0))" } ?? ""): ohne Belegbild")
                }
            }
        }
        for typ in fehlendeTypen.sorted() {
            blocker.append("Ausgabentyp für „\(typ)“ fehlt in den Einstellungen (ausgabentypen)")
        }

        let kodierer = JSONEncoder()
        kodierer.outputFormatting = [.sortedKeys]
        let hash = SHA256.hex(try kodierer.encode(schritte))
        return ConcurPlan(bezug: bezug, concurNr: nummer, titel: titel, schritte: schritte, hinweise: hinweise, blocker: blocker, hash: hash)
    }
}

// MARK: - Zugang und Ausführung

/// Gekapselter Zugang zu Concur. Variante A ist die Browserautomatisierung, Variante B später die API.
/// Die Schnittstelle kennt bewusst kein Senden.
public protocol ConcurZugang {
    /// Bestehende Abrechnungen und verfügbare Ausgaben lesen.
    func lesen() throws -> ConcurBestand
    /// Einen Schritt ausführen. `kopfAnlegen` liefert die Nummer der neuen Abrechnung.
    func ausfuehren(_ schritt: ConcurSchritt, concurNr: String?) throws -> String?
}

public struct ConcurFreigabe: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "concurFreigabe"
    public var bezug: String
    public var planHash: String
    /// Modus „Stapel“: Nach der ersten Vorschau laufen weitere Schreibvorgänge in diese Abrechnung ohne Rückfrage.
    public var stapel: Bool
    public var zeit: String
}

public struct ConcurProtokolleintrag: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "concurProtokoll"
    public var id: Int64?
    public var bezug: String
    public var schritt: String
    public var beschreibung: String
    public var ergebnis: String
    public var zeit: String
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum ConcurLauf {
    public enum Fehler: Error, Equatable, CustomStringConvertible {
        case blockiert([String])
        case vorschauFehlt(String)
        case planVeraltet(String)
        case loeschenNichtBestaetigt
        case loeschenImPlan
        public var description: String {
            switch self {
            case .blockiert(let gruende): return "Plan ist blockiert: \(gruende.joined(separator: "; "))"
            case .vorschauFehlt(let bezug): return "\(bezug): Vor dem Schreiben muss die Vorschau bestätigt sein"
            case .planVeraltet(let bezug): return "\(bezug): Der Plan hat sich geändert, Vorschau erneut zeigen"
            case .loeschenNichtBestaetigt: return "Löschen in Concur nur mit ausdrücklicher Bestätigung"
            case .loeschenImPlan: return "Ein Plan enthält nie einen Löschschritt"
            }
        }
    }

    static func jetzt() -> String { ISO8601DateFormatter().string(from: Date()) }

    /// Der Nutzer hat die Vorschau dieses Plans gesehen und bestätigt.
    public static func freigeben(in datenbank: Datenbank, plan: ConcurPlan, stapel: Bool) throws {
        guard plan.blocker.isEmpty else { throw Fehler.blockiert(plan.blocker) }
        try datenbank.queue.write { db in
            try ConcurFreigabe(bezug: plan.bezug, planHash: plan.hash, stapel: stapel, zeit: jetzt()).save(db)
        }
    }

    public static func darfSchreiben(in datenbank: Datenbank, plan: ConcurPlan) throws -> Bool {
        try datenbank.queue.read { db in
            guard let freigabe = try ConcurFreigabe.fetchOne(db, key: plan.bezug) else { return false }
            return freigabe.planHash == plan.hash || freigabe.stapel
        }
    }

    /// Führt den freigegebenen Plan aus. Legt nur Entwürfe an und bricht beim ersten Fehler ab.
    @discardableResult
    public static func ausfuehren(in datenbank: Datenbank, plan: ConcurPlan, zugang: ConcurZugang, einstellungen: Einstellungen?) throws -> Int {
        guard plan.blocker.isEmpty else { throw Fehler.blockiert(plan.blocker) }
        guard !plan.schritte.contains(where: { $0.art == .loeschen }) else { throw Fehler.loeschenImPlan }
        let aktuell = try ConcurPlanung.plan(in: datenbank, bezug: plan.bezug, einstellungen: einstellungen)
        guard aktuell.hash == plan.hash else { throw Fehler.planVeraltet(plan.bezug) }
        guard try darfSchreiben(in: datenbank, plan: plan) else { throw Fehler.vorschauFehlt(plan.bezug) }

        var nummer = plan.concurNr
        var erledigt = 0
        for schritt in plan.schritte {
            do {
                let antwort = try zugang.ausfuehren(schritt, concurNr: nummer)
                try datenbank.queue.write { db in
                    if schritt.art == .kopfAnlegen, let neu = antwort {
                        nummer = neu
                        if var reise = try Reise.fetchOne(db, key: plan.bezug) {
                            reise.concurNr = neu; reise.concurTitel = plan.titel
                            if rang(reise.status) < rang(.concurEntwurf) { reise.status = .concurEntwurf }
                            try reise.update(db)
                        } else if var s = try Sachkostenabrechnung.fetchOne(db, key: plan.bezug) {
                            s.concurNr = neu; s.concurTitel = plan.titel
                            if rang(s.status) < rang(.concurEntwurf) { s.status = .concurEntwurf }
                            try s.update(db)
                        }
                    }
                    if schritt.art == .positionErfassen || schritt.art == .verfuegbareAusgabeZuordnen,
                       let pid = schritt.positionId, var position = try Position.fetchOne(db, key: pid) {
                        position.concurErfasstIn = nummer ?? "?"
                        try position.update(db)
                    }
                    try protokolliere(db, schritt, "ok")
                }
                erledigt += 1
            } catch {
                try datenbank.queue.write { try protokolliere($0, schritt, "Fehler: \(error)") }
                throw error
            }
        }
        // Sind alle Positionen mit Betrag erfasst, rückt der Status vor.
        try datenbank.queue.write { db in
            let offen = try ConcurAbgleich.abgleichen(db).filter { $0.bezug == plan.bezug && ($0.art == .neu || $0.art == .verfuegbareAusgabe) }
            guard offen.isEmpty else { return }
            if var reise = try Reise.fetchOne(db, key: plan.bezug), rang(reise.status) < rang(.concurPositionen) {
                reise.status = .concurPositionen; try reise.update(db)
            } else if var s = try Sachkostenabrechnung.fetchOne(db, key: plan.bezug), rang(s.status) < rang(.concurPositionen) {
                s.status = .concurPositionen; try s.update(db)
            }
        }
        return erledigt
    }

    /// Löschen läuft nie über einen Plan, sondern nur einzeln und mit ausdrücklicher Bestätigung.
    public static func loeschen(in datenbank: Datenbank, zugang: ConcurZugang, bezug: String, concurNr: String, beschreibung: String,
                                felder: [ConcurSchritt.Feld], ausdruecklichBestaetigt: Bool) throws {
        guard ausdruecklichBestaetigt else { throw Fehler.loeschenNichtBestaetigt }
        let schritt = ConcurSchritt(art: .loeschen, bezug: bezug, positionId: nil, felder: felder, beschreibung: beschreibung)
        _ = try zugang.ausfuehren(schritt, concurNr: concurNr)
        try datenbank.queue.write { try protokolliere($0, schritt, "ok") }
    }

    static func rang(_ status: Reisestatus) -> Int { Reisestatus.allCases.firstIndex(of: status)! }

    static func protokolliere(_ db: Database, _ schritt: ConcurSchritt, _ ergebnis: String) throws {
        var eintrag = ConcurProtokolleintrag(id: nil, bezug: schritt.bezug, schritt: schritt.art.rawValue, beschreibung: schritt.beschreibung,
                                             ergebnis: ergebnis, zeit: jetzt())
        try eintrag.insert(db)
    }
}
