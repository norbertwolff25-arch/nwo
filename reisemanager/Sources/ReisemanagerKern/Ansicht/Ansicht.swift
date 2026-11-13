import Foundation
import GRDB

extension Reisestatus {
    public var text: String {
        switch self {
        case .erkannt: return "erkannt"
        case .bestaetigt: return "bestätigt"
        case .belegeVollstaendig: return "Belege vollständig"
        case .concurEntwurf: return "Concur-Entwurf"
        case .concurPositionen: return "Concur-Positionen erfasst"
        case .eingereicht: return "von mir eingereicht"
        case .erstattet: return "erstattet"
        }
    }
}

extension Sicherheit {
    public var text: String {
        switch self {
        case .sicher: return "sicher"
        case .wahrscheinlich: return "wahrscheinlich"
        case .geschaetzt: return "geschätzt"
        }
    }
}

extension Kostenart {
    public var text: String {
        switch self {
        case .fahrt: return "Fahrt"
        case .unterkunft: return "Unterkunft"
        case .paket: return "Fahrt + Unterkunft (Paket)"
        case .verpflegung: return "Verpflegung"
        case .sonstiges: return "Sonstiges"
        }
    }
}

/// Zeile des Dashboards: eine Reise oder eine Sachkostenabrechnung.
public struct Abrechnungszeile: Identifiable, Equatable, Sendable {
    public var id: String
    public var titel: String
    public var zeitraum: String
    public var summeCent: Int
    public var ohneBetrag: Int
    public var status: Reisestatus
    public var ampel: Ampel
    public var concurNr: String?
    public var offeneFragen: Int
    public var zuBesorgen: Int
    public var typ: String?
    public var istSachkosten: Bool
    public var istStammeinsatz: Bool
}

public struct Positionszeile: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var datum: String
    public var haendler: String
    public var kostenart: String
    public var betrag: String
    public var quelle: String
    /// grün = Belegbild da, gelb = Beleg bekannt, rot = ohne Beleg.
    public var belegAmpel: Ampel
    public var vorauskauf: Bool
    public var belege: [String]
}

public struct Zeitangabe: Equatable, Sendable {
    public var wert: String
    public var quelle: String?
    public var sicherheit: Sicherheit?
}

public struct Abrechnungsdetail: Sendable {
    public var zeile: Abrechnungszeile
    public var anlass: String
    public var beginn: Zeitangabe?
    public var ende: Zeitangabe?
    public var concurTitel: String?
    public var titelGueltig: Bool
    public var hinweis: String?
    public var positionen: [Positionszeile]
    public var bericht: Pruefbericht
    public var offenePunkte: [OffenerPunkt]
    public var verlauf: [Reiseabschnitt]
}

public struct Vorschlagszeile: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var datum: String
    public var haendler: String
    public var betrag: String
    public var art: Vorschlagsart
    public var ziel: String
    public var begruendung: String
    public var sicherheit: Sicherheit
}

public struct Uebersicht: Sendable {
    public var reisen: [Abrechnungszeile]
    public var sachkosten: [Abrechnungszeile]
    public var privat: [Abrechnungszeile]
    public var summeDienstreisenCent: Int
    public var offeneVorschlaege: Int
    public var zuBesorgen: Int
}

/// Lesesicht für die Oberfläche. Alles hier ist ohne SwiftUI testbar.
public enum Ansicht {
    static func zeitraum(_ beginn: Tag?, _ ende: Tag?) -> String {
        func kurz(_ t: Tag) -> String { String(format: "%02d.%02d.%04d", t.tag, t.monat, t.jahr) }
        switch (beginn, ende) {
        case let (b?, e?) where b == e: return kurz(b)
        case let (b?, e?): return "\(kurz(b)) – \(kurz(e))"
        case let (b?, nil): return "ab \(kurz(b))"
        default: return "Zeitraum offen"
        }
    }

    public static func uebersicht(in datenbank: Datenbank, einstellungen: Einstellungen? = nil, heute: Tag? = nil) throws -> Uebersicht {
        let berichte = try Plausi.pruefe(in: datenbank, einstellungen: einstellungen, heute: heute)
            .reduce(into: [String: Pruefbericht]()) { $0[$1.bezug] = $1 }
        let jeReise = try Summen.jeReise(in: datenbank)
        let jeSachkosten = try Summen.jeSachkostenabrechnung(in: datenbank)
        return try datenbank.queue.read { db in
            var reisen: [Abrechnungszeile] = []
            var privat: [Abrechnungszeile] = []
            for reise in try Reise.order(Column("beginn"), Column("id")).fetchAll(db) {
                let summe = jeReise[reise.id] ?? Reisesumme()
                let bericht = berichte[reise.id]
                let zeile = Abrechnungszeile(
                    id: reise.id, titel: reise.concurTitel ?? reise.anlass, zeitraum: zeitraum(reise.beginn, reise.ende),
                    summeCent: summe.summeCent, ohneBetrag: summe.ohneBetrag, status: reise.status, ampel: bericht?.ampel ?? .gruen,
                    concurNr: reise.concurNr, offeneFragen: bericht?.fragen.count ?? 0, zuBesorgen: bericht?.besorgen.count ?? 0,
                    typ: bericht?.typ?.text, istSachkosten: false, istStammeinsatz: reise.istStammeinsatz)
                if reise.art == .privat { privat.append(zeile) } else { reisen.append(zeile) }
            }
            let sachkosten = try Sachkostenabrechnung.order(Column("id")).fetchAll(db).map { s -> Abrechnungszeile in
                let summe = jeSachkosten[s.id] ?? Reisesumme()
                let bericht = berichte[s.id]
                return Abrechnungszeile(
                    id: s.id, titel: s.concurTitel ?? s.titel, zeitraum: "", summeCent: summe.summeCent, ohneBetrag: summe.ohneBetrag,
                    status: s.status, ampel: bericht?.ampel ?? .gruen, concurNr: s.concurNr, offeneFragen: bericht?.fragen.count ?? 0,
                    zuBesorgen: bericht?.besorgen.count ?? 0, typ: nil, istSachkosten: true, istStammeinsatz: false)
            }
            return Uebersicht(
                reisen: reisen, sachkosten: sachkosten, privat: privat,
                summeDienstreisenCent: reisen.map(\.summeCent).reduce(0, +),
                offeneVorschlaege: try Vorschlag.filter(Column("status") == Vorschlagsstatus.offen.rawValue).fetchCount(db),
                zuBesorgen: berichte.values.map(\.besorgen.count).reduce(0, +))
        }
    }

    public static func detail(in datenbank: Datenbank, bezug: String, einstellungen: Einstellungen? = nil, heute: Tag? = nil) throws -> Abrechnungsdetail? {
        let uebersicht = try uebersicht(in: datenbank, einstellungen: einstellungen, heute: heute)
        guard let zeile = (uebersicht.reisen + uebersicht.sachkosten + uebersicht.privat).first(where: { $0.id == bezug }) else { return nil }
        let bericht = try Plausi.pruefe(in: datenbank, einstellungen: einstellungen, heute: heute).first { $0.bezug == bezug }
            ?? Pruefbericht(bezug: bezug, titel: zeile.titel, typ: nil, typGrund: nil, ampel: .gruen, befunde: [], besorgen: [])
        return try datenbank.queue.read { db in
            let reise = try Reise.fetchOne(db, key: bezug)
            let sachkosten = try Sachkostenabrechnung.fetchOne(db, key: bezug)
            let spalte = reise != nil ? "reiseId" : "sachkostenId"
            let positionen = try Position.filter(Column(spalte) == bezug).order(Column("datum"), Column("id")).fetchAll(db).map { p -> Positionszeile in
                let bild = bericht.befunde.first { $0.schluessel == "\(bezug):bild:\(p.id ?? 0)" }
                let betrag: String
                if let cent = p.betragCent { betrag = Geld.text(cent: cent) + " €" }
                else if let fremd = p.fremdbetragCent { betrag = "\(Geld.text(cent: fremd)) \(p.fremdwaehrung ?? "") – Euro fehlt" }
                else { betrag = "fehlt" }
                return Positionszeile(
                    id: p.id ?? 0, datum: p.datum?.iso ?? "", haendler: p.haendler, kostenart: p.kostenartText ?? p.kostenart.text, betrag: betrag,
                    quelle: p.quelle ?? "", belegAmpel: bild?.ampel ?? .gruen, vorauskauf: p.vorauskauf,
                    belege: try String.fetchAll(db, sql: "SELECT belegId FROM positionBeleg WHERE positionId = ? ORDER BY belegId", arguments: [p.id]))
            }
            func angabe(_ tag: Tag?, _ zeit: String?, _ quelle: String?, _ sicherheit: Sicherheit?) -> Zeitangabe? {
                tag.map { Zeitangabe(wert: zeitraum($0, $0) + (zeit.map { ", \($0) Uhr" } ?? ""), quelle: quelle, sicherheit: sicherheit) }
            }
            let titel = reise?.concurTitel ?? sachkosten?.concurTitel
            return Abrechnungsdetail(
                zeile: zeile, anlass: reise?.anlass ?? sachkosten?.titel ?? "",
                beginn: angabe(reise?.beginn, reise?.beginnZeit, reise?.beginnQuelle, reise?.beginnSicherheit),
                ende: angabe(reise?.ende, reise?.endeZeit, reise?.endeQuelle, reise?.endeSicherheit),
                concurTitel: titel, titelGueltig: titel.map(Abrechnungstitel.istGueltig) ?? true, hinweis: reise?.hinweis ?? sachkosten?.hinweis,
                positionen: positionen, bericht: bericht,
                offenePunkte: try OffenerPunkt.filter(Column(spalte) == bezug && Column("erledigt") == false).order(Column("id")).fetchAll(db),
                verlauf: try Reiseabschnitt.filter(Column("reiseId") == bezug).order(Column("abfahrt"), Column("reihenfolge")).fetchAll(db))
        }
    }

    public static func vorschlaege(in datenbank: Datenbank) throws -> [Vorschlagszeile] {
        try datenbank.queue.read { db in
            try Vorschlag.filter(Column("status") == Vorschlagsstatus.offen.rawValue).order(Column("gruppe"), Column("id")).fetchAll(db).compactMap { v in
                guard let z = try Zahlung.fetchOne(db, key: v.zahlungId), let id = v.id else { return nil }
                let ziel: String
                switch v.art {
                case .zuReise, .zuSachkosten: ziel = v.zielId ?? "Ziel fehlt"
                case .neueReise: ziel = "neue Reise"
                case .privat: ziel = "privat"
                case .vorauskaufOffen: ziel = "Reise offen"
                }
                return Vorschlagszeile(id: id, datum: z.datum.iso, haendler: z.haendler, betrag: z.betragCent.map { Geld.text(cent: -$0) + " €" } ?? "Euro fehlt",
                                       art: v.art, ziel: ziel, begruendung: v.begruendung, sicherheit: v.sicherheit)
            }
        }
    }

    /// „Was ich noch besorgen muss“, nach Fundort gruppiert und sortiert.
    public static func besorgungsliste(in datenbank: Datenbank, einstellungen: Einstellungen? = nil, heute: Tag? = nil) throws -> [(fundort: String, eintraege: [Besorgung])] {
        let alle = try Plausi.pruefe(in: datenbank, einstellungen: einstellungen, heute: heute).flatMap(\.besorgen)
        return Dictionary(grouping: alle, by: \.fundort).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

/// Änderungen aus der Oberfläche. Jede wird als Entscheidung des Nutzers protokolliert.
public enum Bearbeitung {
    public enum Fehler: Error, CustomStringConvertible {
        case unbekannt(String)
        public var description: String {
            if case .unbekannt(let was) = self { return "\(was) gibt es nicht" }
            return ""
        }
    }

    static func protokoll(_ db: Database, typ: String, id: String, feld: String, wert: String?) throws {
        var eintrag = Entscheidung(id: nil, objektTyp: typ, objektId: id, feld: feld, wert: wert, quelle: "Nutzer", regelId: nil,
                                   sicherheit: .sicher, zeit: ISO8601DateFormatter().string(from: Date()))
        try eintrag.insert(db)
    }

    /// Drag & Drop: Position in eine andere Reise oder Sachkostenabrechnung ziehen.
    public static func verschiebe(in datenbank: Datenbank, position id: Int64, nach bezug: String) throws {
        try datenbank.queue.write { db in
            guard var position = try Position.fetchOne(db, key: id) else { throw Fehler.unbekannt("Position \(id)") }
            if let reise = try Reise.fetchOne(db, key: bezug) {
                position.reiseId = bezug
                position.sachkostenId = nil
                position.vorauskauf = position.datum.flatMap { d in reise.beginn.map { d < $0 } } ?? false
            } else if try Sachkostenabrechnung.exists(db, key: bezug) {
                position.reiseId = nil
                position.sachkostenId = bezug
                position.vorauskauf = false
            } else {
                throw Fehler.unbekannt(bezug)
            }
            position.vorschlag = nil
            try position.update(db)
            try protokoll(db, typ: "position", id: String(id), feld: "zuordnung", wert: bezug)
        }
    }

    public static func setzeStatus(in datenbank: Datenbank, bezug: String, status: Reisestatus) throws {
        try datenbank.queue.write { db in
            if var reise = try Reise.fetchOne(db, key: bezug) {
                reise.status = status
                try reise.update(db)
            } else if var sachkosten = try Sachkostenabrechnung.fetchOne(db, key: bezug) {
                sachkosten.status = status
                try sachkosten.update(db)
            } else {
                throw Fehler.unbekannt(bezug)
            }
            try protokoll(db, typ: "abrechnung", id: bezug, feld: "status", wert: status.rawValue)
        }
    }

    /// Dienstlich oder privat. Privatreisen gehen in keine Summe ein.
    public static func setzeArt(in datenbank: Datenbank, reise id: String, art: Reiseart) throws {
        try datenbank.queue.write { db in
            guard var reise = try Reise.fetchOne(db, key: id) else { throw Fehler.unbekannt(id) }
            reise.art = art
            try reise.update(db)
            try protokoll(db, typ: "reise", id: id, feld: "art", wert: art.rawValue)
        }
    }

    public static func setzeAnlass(in datenbank: Datenbank, reise id: String, anlass: String, ort: String?) throws {
        try datenbank.queue.write { db in
            guard var reise = try Reise.fetchOne(db, key: id) else { throw Fehler.unbekannt(id) }
            reise.anlass = anlass
            reise.ort = ort.flatMap { $0.isEmpty ? nil : $0 }
            try reise.update(db)
            try protokoll(db, typ: "reise", id: id, feld: "anlass", wert: anlass)
        }
    }

    public static func erledige(in datenbank: Datenbank, offenerPunkt id: Int64) throws {
        try datenbank.queue.write { db in
            guard var punkt = try OffenerPunkt.fetchOne(db, key: id) else { throw Fehler.unbekannt("Offener Punkt \(id)") }
            punkt.erledigt = true
            try punkt.update(db)
        }
    }
}

/// Kurzbericht je Reise als Markdown: Reisedaten, Positionen, Belegliste, offene Punkte. Auf dem iPhone lesbar.
public enum Bericht {
    public static func markdown(in datenbank: Datenbank, bezug: String, einstellungen: Einstellungen? = nil, heute: Tag? = nil) throws -> String? {
        guard let d = try Ansicht.detail(in: datenbank, bezug: bezug, einstellungen: einstellungen, heute: heute) else { return nil }
        var z: [String] = ["# \(d.zeile.id) \(d.zeile.titel)", ""]
        z.append("- **Anlass:** \(d.anlass)")
        if let typ = d.zeile.typ { z.append("- **Reisetyp:** \(typ)") }
        for (name, angabe) in [("Beginn", d.beginn), ("Ende", d.ende)] {
            if let a = angabe {
                let zusatz = [a.quelle, a.sicherheit?.text].compactMap { $0 }.joined(separator: ", ")
                z.append("- **\(name):** \(a.wert)\(zusatz.isEmpty ? "" : " (\(zusatz))")")
            }
        }
        z.append("- **Status:** \(d.zeile.status.text)")
        if let nr = d.zeile.concurNr { z.append("- **Concur:** \(nr)") }
        z.append("- **Ampel:** \(d.zeile.ampel.text)")
        z.append("- **Summe:** \(Geld.text(cent: d.zeile.summeCent)) €\(d.zeile.ohneBetrag > 0 ? " (\(d.zeile.ohneBetrag) Positionen ohne Betrag)" : "")")
        if !d.verlauf.isEmpty {
            z += ["", "## Reiseverlauf", ""]
            for a in d.verlauf {
                z.append("- \(a.abfahrt ?? "?") \(a.von ?? "?") → \(a.nach ?? "?") \(a.ankunft.map { "(an \($0))" } ?? "")\(a.verkehrsmittel.map { ", \($0)" } ?? "")")
            }
        }
        z += ["", "## Positionen", "", "| Datum | Händler | Kostenart | Betrag | Beleg |", "|---|---|---|---:|---|"]
        for p in d.positionen {
            let beleg = p.belege.isEmpty ? p.belegAmpel.text : "\(p.belege.joined(separator: ", ")) (\(p.belegAmpel.text))"
            z.append("| \(p.datum) | \(p.haendler.replacingOccurrences(of: "|", with: "/")) | \(p.kostenart)\(p.vorauskauf ? ", Vorauskauf" : "") | \(p.betrag) | \(beleg) |")
        }
        let befunde = d.bericht.befunde.filter { $0.art != .belegbild }
        if !befunde.isEmpty {
            z += ["", "## Befunde", ""]
            for b in befunde { z.append("- \(b.ampel.text): \(b.text)\(b.antwort.map { " (Antwort: \($0))" } ?? "")") }
        }
        if !d.bericht.besorgen.isEmpty {
            z += ["", "## Was ich noch besorgen muss", ""]
            for b in d.bericht.besorgen { z.append("- \(b.text) – \(b.fundort)") }
        }
        if !d.offenePunkte.isEmpty {
            z += ["", "## Offene Punkte", ""]
            for p in d.offenePunkte { z.append("- \(p.text)\(p.fundort.map { " – \($0)" } ?? "")") }
        }
        return z.joined(separator: "\n") + "\n"
    }
}
