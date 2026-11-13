import Foundation
import GRDB

public enum Ampel: Int, Comparable, Sendable {
    case gruen, gelb, rot
    public static func < (l: Ampel, r: Ampel) -> Bool { l.rawValue < r.rawValue }
    public var text: String { ["grün", "gelb", "rot"][rawValue] }
}

public enum Reisetyp: String, Sendable {
    case kongress, bahn, pkw, flug, tagesreise
    public var text: String {
        switch self {
        case .kongress: return "Kongress/Konferenz"
        case .bahn: return "Kundentermin/Einsatz mit Bahn"
        case .pkw: return "Pkw-/Dienstwagenfahrt"
        case .flug: return "Flugreise/Pauschalreise"
        case .tagesreise: return "Tagesreise"
        }
    }
}

public struct Antwortoption: Equatable, Sendable {
    public var text: String
    /// true: Mit dieser Antwort ist der Befund erledigt. false: Der Beleg ist noch zu besorgen.
    public var erledigt: Bool
}

public struct Frage: Equatable, Sendable {
    public var text: String
    public var optionen: [Antwortoption]
}

public struct Befund: Equatable, Sendable {
    public enum Art: String, Sendable { case sollBeleg, luecke, widerspruch, betragFehlt, euroFehlt, belegbild, zeitraum, wiedervorlage }
    /// Stabiler Schlüssel, unter dem die Antwort gespeichert wird, z. B. „D10:hotel“.
    public var schluessel: String
    public var art: Art
    public var ampel: Ampel
    public var text: String
    public var fundort: String?
    public var frage: Frage?
    public var antwort: String?
}

public struct Besorgung: Equatable, Sendable {
    public var bezug: String
    public var text: String
    public var fundort: String
}

public struct Pruefbericht: Sendable {
    public var bezug: String
    public var titel: String
    public var typ: Reisetyp?
    public var typGrund: String?
    public var ampel: Ampel
    public var befunde: [Befund]
    public var besorgen: [Besorgung]
    public var fragen: [(schluessel: String, frage: Frage)] { befunde.compactMap { b in b.frage.map { (b.schluessel, $0) } } }
}

/// Prüft jede Reise und jede Sachkostenabrechnung gegen ihre Soll-Checkliste, findet Lücken und Widersprüche
/// und stellt die Nachfragen gesammelt je Reise.
public enum Plausi {
    static let kongressworte = ["kongress", "konferenz", "messe", "tagung", "summit", "forum", "dialog", "con"]

    /// Reisetyp: gesetzt vom Nutzer oder abgeleitet aus Verkehrsmittel, Positionen und Anlass.
    static func typ(_ reise: Reise, _ positionen: [Position], _ abschnitte: [Reiseabschnitt]) -> (Reisetyp, String) {
        if let gesetzt = reise.typ.flatMap(Reisetyp.init(rawValue:)) { return (gesetzt, "festgelegt") }
        let mittel = (reise.verkehrsmittel ?? "").lowercased()
        let klassen = positionen.map { Haendlerklasse.bestimme(Zuordnung.haendlername($0.haendler)) }
        let worte = reise.anlass.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        if worte.contains(where: { w in kongressworte.contains { w == $0 || (w.count > 4 && (w.hasSuffix($0) || w.hasPrefix($0))) } }) {
            return (.kongress, "Anlass nennt eine Veranstaltung")
        }
        if positionen.contains(where: { $0.kostenart == .paket }) || klassen.contains(.flug) || mittel.hasPrefix("flug")
            || abschnitte.contains(where: { Vorbelegung.istFlug($0.verkehrsmittel) }) {
            return (.flug, "Flug oder Pauschalreise in den Positionen")
        }
        if mittel.contains("dienstwagen") || mittel.contains("pkw") || mittel.contains("auto") {
            return (.pkw, "Verkehrsmittel „\(reise.verkehrsmittel ?? "")“")
        }
        if let beginn = reise.beginn, let ende = reise.ende, beginn == ende { return (.tagesreise, "Beginn und Ende am selben Tag") }
        return (.bahn, "kein anderer Typ erkennbar")
    }

    static let folgt = "Beleg folgt"

    public static func pruefe(in datenbank: Datenbank, einstellungen: Einstellungen? = nil, heute: Tag? = nil) throws -> [Pruefbericht] {
        try datenbank.queue.read { db in
            var berichte: [Pruefbericht] = []
            let belege = try Beleg.fetchAll(db)
            let mitBild = Set(try String.fetchAll(db, sql: "SELECT DISTINCT belegId FROM belegbildBeleg"))
            let antworten = try Entscheidung.filter(Column("objektTyp") == "befund").order(Column("id")).fetchAll(db)
                .reduce(into: [String: String]()) { $0[$1.objektId] = $1.wert }
            let wohnorte = Zuordnung.ortsvarianten(einstellungen?.privatadresse.ort)
            let frist = einstellungen?.wiedervorlageTage ?? 30

            func abschluss(_ bezug: String, _ titel: String, _ typ: (Reisetyp, String)?, _ roh: [Befund], _ besorgen: [Besorgung], laeuftNoch: Bool = false) {
                var befunde: [Befund] = []
                var liste = besorgen
                for var befund in roh {
                    // Bevorstehende oder laufende Reise: Fehlende Belege sind noch kein Mangel.
                    if laeuftNoch, befund.ampel == .rot, befund.art == .sollBeleg || befund.art == .luecke { befund.ampel = .gelb }
                    if let antwort = antworten[befund.schluessel] {
                        // Erledigende Antwort: Befund entfällt. Sonst bleibt er ohne erneute Frage stehen.
                        if befund.frage?.optionen.first(where: { $0.text == antwort })?.erledigt == true { continue }
                        befund.antwort = antwort
                        befund.frage = nil
                    }
                    befunde.append(befund)
                    if befund.art == .sollBeleg || befund.art == .luecke, befund.ampel == .rot || befund.antwort != nil, let fundort = befund.fundort {
                        liste.append(Besorgung(bezug: bezug, text: befund.text, fundort: fundort))
                    }
                }
                let ampel = befunde.map(\.ampel).max() ?? .gruen
                berichte.append(Pruefbericht(bezug: bezug, titel: titel, typ: typ?.0, typGrund: typ?.1, ampel: ampel, befunde: befunde, besorgen: liste))
            }

            /// Belegbild-Ampel je Position: grün mit Bild, gelb bei bekanntem Beleg oder bekannter Zahlung ohne Bild, rot ohne beides.
            func positionspruefung(_ p: Position, bezug: String, befunde: inout [Befund], besorgen: inout [Besorgung]) throws {
                let platzhalter = ["betrag fehlt", "offen"].contains(p.haendler.lowercased())
                let name = "\(platzhalter ? (p.kostenartText ?? p.haendler) : p.haendler)\(p.datum.map { " (\($0))" } ?? "")"
                let pid = p.id ?? 0
                if p.betragCent == nil {
                    if p.fremdbetragCent != nil {
                        befunde.append(Befund(schluessel: "\(bezug):euro:\(pid)", art: .euroFehlt, ampel: .rot,
                                              text: "Euro-Betrag fehlt: \(name), \(Geld.text(cent: p.fremdbetragCent!)) \(p.fremdwaehrung ?? "")",
                                              fundort: "Kartenabrechnung", frage: nil, antwort: nil))
                    } else {
                        befunde.append(Befund(schluessel: "\(bezug):betrag:\(pid)", art: .betragFehlt, ampel: .rot, text: "Betrag fehlt: \(name)",
                                              fundort: Haendlerklasse.fundort(haendler: p.haendler, quelle: p.quelle, datum: p.datum), frage: nil, antwort: nil))
                    }
                }
                let eigene = try String.fetchAll(db, sql: "SELECT belegId FROM positionBeleg WHERE positionId = ?", arguments: [pid])
                if eigene.contains(where: mitBild.contains) { return }
                // Ein Hinweis wie „Rechnung 4711“ oder eine genannte Zahlungsquelle heißt: Der Beleg ist bekannt, nur das Bild fehlt.
                let hinweis = p.belegHinweis.flatMap { ["nachtragen", "nachreichen", "offen"].contains($0.lowercased()) ? nil : $0 }
                let quelleBekannt = !(p.quelle ?? "").isEmpty && p.quelle?.lowercased() != "offen" && p.betragCent != nil
                let fundort = eigene.compactMap { nr in belege.first { $0.id == nr }?.fundort }.first ?? hinweis
                    ?? Haendlerklasse.fundort(haendler: Zuordnung.haendlername(p.haendler), quelle: p.quelle, datum: p.datum)
                let bekannt = !eigene.isEmpty || p.zahlungId != nil || hinweis != nil || quelleBekannt
                befunde.append(Befund(schluessel: "\(bezug):bild:\(pid)", art: .belegbild, ampel: bekannt ? .gelb : .rot,
                                      text: bekannt ? "Belegbild fehlt: \(name)" : "Position ohne Beleg: \(name)", fundort: fundort, frage: nil, antwort: nil))
                besorgen.append(Besorgung(bezug: bezug, text: "\(bekannt ? "Belegbild" : "Beleg") für \(name)", fundort: fundort))
            }

            for reise in try Reise.filter(Column("art") == Reiseart.dienstreise.rawValue).order(Column("id")).fetchAll(db) {
                let id = reise.id
                let positionen = try Position.filter(Column("reiseId") == id).order(Column("datum"), Column("id")).fetchAll(db)
                let abschnitte = try Reiseabschnitt.filter(Column("reiseId") == id).fetchAll(db)
                let aufenthalte = try Hotelaufenthalt.filter(Column("reiseId") == id).fetchAll(db)
                let klassen = positionen.map { Haendlerklasse.bestimme(Zuordnung.haendlername($0.haendler)) }
                let typ = typ(reise, positionen, abschnitte)
                var befunde: [Befund] = []
                var besorgen: [Besorgung] = []

                guard let beginn = reise.beginn, let ende = reise.ende else {
                    befunde.append(Befund(schluessel: "\(id):zeitraum", art: .zeitraum, ampel: positionen.isEmpty ? .gelb : .rot,
                                          text: "Beginn und Ende der Reise fehlen", fundort: "Kalender, bahn.de", frage: nil, antwort: nil))
                    for p in positionen { try positionspruefung(p, bezug: id, befunde: &befunde, besorgen: &besorgen) }
                    abschluss(id, reise.concurTitel ?? reise.anlass, nil, befunde, besorgen)
                    continue
                }
                let naechte = beginn.abstandInTagen(zu: ende)

                // Soll-Checkliste je Reisetyp.
                if typ.0 == .kongress, !positionen.contains(where: { $0.kostenart == .sonstiges && $0.betragCent != nil && Haendlerklasse.bestimme($0.haendler) != .parken }) {
                    befunde.append(Befund(schluessel: "\(id):ticket", art: .sollBeleg, ampel: .rot, text: "Ticket oder Teilnahmegebühr fehlt",
                                          fundort: "Veranstalter oder dienstliches Postfach",
                                          frage: Frage(text: "Ticket oder Teilnahmegebühr?", optionen: [
                                            Antwortoption(text: folgt, erledigt: false),
                                            Antwortoption(text: "Kostenlos oder eingeladen", erledigt: true),
                                            Antwortoption(text: "Vom Arbeitgeber direkt bezahlt", erledigt: true)]), antwort: nil))
                }
                let hatAnreise = typ.0 == .pkw || !abschnitte.isEmpty || klassen.contains(.bahn) || klassen.contains(.flug)
                    || positionen.contains { $0.kostenart == .paket }
                if !hatAnreise {
                    befunde.append(Befund(schluessel: "\(id):anreise", art: .luecke, ampel: .gelb, text: "Anreise und Rückreise fehlen",
                                          fundort: "bahn.de → Meine Reisen",
                                          frage: Frage(text: "Wie bist du angereist?", optionen: [
                                            Antwortoption(text: "Bahn, \(folgt)", erledigt: false),
                                            Antwortoption(text: "Flug, \(folgt)", erledigt: false),
                                            Antwortoption(text: "Dienstwagen oder Pkw", erledigt: true),
                                            Antwortoption(text: "Mitfahrt, keine Kosten", erledigt: true)]), antwort: nil))
                }
                if naechte > 0 {
                    let hatHotel = positionen.contains { ($0.kostenart == .unterkunft || $0.kostenart == .paket) && $0.betragCent != nil }
                    let hotelnaechte = aufenthalte.map(\.naechte).reduce(0, +)
                    if !hatHotel && aufenthalte.isEmpty {
                        befunde.append(Befund(schluessel: "\(id):hotel", art: .sollBeleg, ampel: .rot,
                                              text: "Hotel fehlt für \(naechte) \(naechte == 1 ? "Nacht" : "Nächte")", fundort: "Hotelportal → Rechnung",
                                              frage: Frage(text: "Übernachtung?", optionen: [
                                                Antwortoption(text: "Hotel, \(folgt)", erledigt: false),
                                                Antwortoption(text: "Privat übernachtet, keine Kosten", erledigt: true),
                                                Antwortoption(text: "Vom Veranstalter oder Kunden bezahlt", erledigt: true)]), antwort: nil))
                    } else if !aufenthalte.isEmpty, hotelnaechte != naechte {
                        befunde.append(Befund(schluessel: "\(id):naechte", art: .luecke, ampel: .gelb,
                                              text: "\(hotelnaechte) Hotelnächte bei \(naechte) Nächten Reisedauer", fundort: "Hotelportal",
                                              frage: Frage(text: "Stimmt die Zahl der Hotelnächte?", optionen: [
                                                Antwortoption(text: "Ja, die übrigen Nächte ohne Hotel", erledigt: true),
                                                Antwortoption(text: "Nein, Aufenthalt fehlt", erledigt: false)]), antwort: nil))
                    } else if !hatHotel {
                        befunde.append(Befund(schluessel: "\(id):hotelrechnung", art: .sollBeleg, ampel: .rot, text: "Hotelrechnung fehlt",
                                              fundort: "Hotelportal → Rechnung", frage: nil, antwort: nil))
                    }
                }
                if typ.0 == .pkw, !klassen.contains(.parken) {
                    befunde.append(Befund(schluessel: "\(id):parken", art: .sollBeleg, ampel: .gelb, text: "Kein Parkbeleg", fundort: "Parkschein scannen",
                                          frage: Frage(text: "Parkgebühren?", optionen: [
                                            Antwortoption(text: folgt, erledigt: false),
                                            Antwortoption(text: "Kein Parken angefallen", erledigt: true)]), antwort: nil))
                }
                if typ.0 != .pkw, !klassen.contains(.taxi), !klassen.contains(.oepnv) {
                    befunde.append(Befund(schluessel: "\(id):vorort", art: .sollBeleg, ampel: .gelb, text: "Keine Belege für ÖPNV oder Taxi vor Ort",
                                          fundort: "Uber-/Bolt-App, Verkehrsbetrieb",
                                          frage: Frage(text: "ÖPNV oder Taxi vor Ort?", optionen: [
                                            Antwortoption(text: folgt, erledigt: false),
                                            Antwortoption(text: "Keine Kosten vor Ort", erledigt: true)]), antwort: nil))
                }

                // Lücken: Tage mitten in der Reise ohne jeden Beleg, wenn auch kein Hotel den Zeitraum deckt.
                if naechte >= 2, !positionen.contains(where: { $0.kostenart == .unterkunft || $0.kostenart == .paket }), aufenthalte.isEmpty {
                    let belegt = Set(positionen.compactMap(\.datum))
                    let leer = positionen.isEmpty ? [] : belegt.isEmpty ? [] : (1..<naechte).filter { versatz in
                        !belegt.contains { beginn.abstandInTagen(zu: $0) == versatz }
                    }
                    if !leer.isEmpty {
                        befunde.append(Befund(schluessel: "\(id):leertage", art: .luecke, ampel: .gelb,
                                              text: "\(leer.count) \(leer.count == 1 ? "Tag" : "Tage") mitten in der Reise ohne Beleg", fundort: nil, frage: nil, antwort: nil))
                    }
                }

                // Widersprüche.
                for (p, klasse) in zip(positionen, klassen) {
                    guard let datum = p.datum else { continue }
                    let pid = p.id ?? 0
                    if datum > ende || (datum < beginn && klasse.nurAmReisetag) {
                        befunde.append(Befund(schluessel: "\(id):zeit:\(pid)", art: .widerspruch, ampel: .gelb,
                                              text: "Zahlung außerhalb des Reisezeitraums: \(p.haendler) am \(datum)", fundort: nil,
                                              frage: Frage(text: "\(p.haendler) am \(datum) gehört zur Reise?", optionen: [
                                                Antwortoption(text: "Ja, gehört dazu", erledigt: true),
                                                Antwortoption(text: "Nein, andere Reise oder privat", erledigt: false)]), antwort: nil))
                    }
                    if klasse == .hotel || p.kostenart == .unterkunft,
                       wohnorte.contains(where: { Textnorm.kern(p.haendler + " " + (p.ort ?? "")).contains($0) }) {
                        befunde.append(Befund(schluessel: "\(id):wohnort:\(pid)", art: .widerspruch, ampel: .rot,
                                              text: "Hotel am Wohnort: \(p.haendler)", fundort: nil,
                                              frage: Frage(text: "\(p.haendler) ist dienstlich?", optionen: [
                                                Antwortoption(text: "Ja, dienstlich", erledigt: true),
                                                Antwortoption(text: "Nein, privat", erledigt: false)]), antwort: nil))
                    }
                    if let ort = p.ort, let ziel = reise.ort, !Textnorm.kern(ort).isEmpty, Textnorm.kern(ort) != Textnorm.kern(ziel) {
                        befunde.append(Befund(schluessel: "\(id):ort:\(pid)", art: .widerspruch, ampel: .gelb,
                                              text: "Ort „\(ort)“ passt nicht zum Reiseziel „\(ziel)“: \(p.haendler)", fundort: nil,
                                              frage: Frage(text: "\(p.haendler) in \(ort) gehört zur Reise nach \(ziel)?", optionen: [
                                                Antwortoption(text: "Ja, nur der Firmensitz des Anbieters", erledigt: true),
                                                Antwortoption(text: "Nein, gehört nicht dazu", erledigt: false)]), antwort: nil))
                    }
                }
                for p in positionen { try positionspruefung(p, bezug: id, befunde: &befunde, besorgen: &besorgen) }

                // Belege aus dem Verzeichnis, die dieser Reise zugeordnet und noch ohne Bild sind.
                for beleg in belege where !mitBild.contains(beleg.id) && nennt(beleg.belegt, id) {
                    let fundort = beleg.fundort ?? "Fundort offen"
                    let eintrag = Besorgung(bezug: id, text: "\(beleg.id) \(beleg.dokument)", fundort: fundort)
                    if !besorgen.contains(where: { $0.fundort == fundort && $0.text.contains(beleg.id) }) { besorgen.append(eintrag) }
                }

                if let heute, Reisestatus.allCases.firstIndex(of: reise.status)! < Reisestatus.allCases.firstIndex(of: .eingereicht)! {
                    let tage = ende.abstandInTagen(zu: heute)
                    if tage > frist {
                        befunde.append(Befund(schluessel: "\(id):wiedervorlage", art: .wiedervorlage, ampel: .gelb,
                                              text: "Seit \(tage) Tagen beendet und noch nicht eingereicht", fundort: nil, frage: nil, antwort: nil))
                    }
                }
                abschluss(id, reise.concurTitel ?? reise.anlass, typ, befunde, besorgen, laeuftNoch: heute.map { ende >= $0 } ?? false)
            }

            // Sachkosten: Rechnung, Zahlungsnachweis, Begründung.
            for abrechnung in try Sachkostenabrechnung.order(Column("id")).fetchAll(db) {
                let id = abrechnung.id
                var befunde: [Befund] = []
                var besorgen: [Besorgung] = []
                let positionen = try Position.filter(Column("sachkostenId") == id).order(Column("datum"), Column("id")).fetchAll(db)
                if positionen.isEmpty {
                    befunde.append(Befund(schluessel: "\(id):leer", art: .sollBeleg, ampel: .rot, text: "Keine Position: Rechnung und Betrag fehlen",
                                          fundort: "Rechnung beim Anbieter", frage: nil, antwort: nil))
                }
                if (abrechnung.hinweis ?? "").isEmpty {
                    befunde.append(Befund(schluessel: "\(id):begruendung", art: .sollBeleg, ampel: .gelb, text: "Begründung fehlt", fundort: nil, frage: nil, antwort: nil))
                }
                for p in positionen {
                    try positionspruefung(p, bezug: id, befunde: &befunde, besorgen: &besorgen)
                    if p.zahlungId == nil, (p.quelle ?? "").isEmpty || p.quelle == "offen" {
                        befunde.append(Befund(schluessel: "\(id):zahlung:\(p.id ?? 0)", art: .sollBeleg, ampel: .gelb,
                                              text: "Zahlungsnachweis fehlt: \(p.haendler)", fundort: "Kontoauszug oder Kartenabrechnung", frage: nil, antwort: nil))
                    }
                }
                abschluss(id, abrechnung.concurTitel ?? abrechnung.titel, nil, befunde, besorgen)
            }
            return berichte
        }
    }

    /// Nennt der Text die Nummer als ganzes Wort („D05 Berlin“, „D03, D05“)?
    static func nennt(_ text: String?, _ nummer: String) -> Bool {
        (text ?? "").split(whereSeparator: { !($0.isLetter || $0.isNumber) }).contains { $0 == nummer }
    }

    public enum Antwortfehler: Error, CustomStringConvertible {
        case keineFrage(String), keineOption(String, Int)
        public var description: String {
            switch self {
            case .keineFrage(let s): return "Zu „\(s)“ gibt es keine offene Frage"
            case .keineOption(let s, let n): return "Frage „\(s)“ hat keine Antwort Nr. \(n)"
            }
        }
    }

    /// Speichert die Antwort auf eine Nachfrage. `nummer` zählt ab 1.
    @discardableResult
    public static func beantworte(in datenbank: Datenbank, schluessel: String, nummer: Int, einstellungen: Einstellungen? = nil) throws -> String {
        let berichte = try pruefe(in: datenbank, einstellungen: einstellungen)
        guard let frage = berichte.flatMap(\.fragen).first(where: { $0.schluessel == schluessel })?.frage else {
            throw Antwortfehler.keineFrage(schluessel)
        }
        guard (1...frage.optionen.count).contains(nummer) else { throw Antwortfehler.keineOption(schluessel, nummer) }
        let antwort = frage.optionen[nummer - 1].text
        try datenbank.queue.write { db in
            var eintrag = Entscheidung(id: nil, objektTyp: "befund", objektId: schluessel, feld: "antwort", wert: antwort, quelle: "Nutzer",
                                       regelId: nil, sicherheit: .sicher, zeit: ISO8601DateFormatter().string(from: Date()))
            try eintrag.insert(db)
        }
        return antwort
    }
}
