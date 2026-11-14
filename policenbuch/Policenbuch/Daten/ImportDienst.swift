import Foundation
import SwiftData
import PolicenbuchKern

/// Vorschau eines Vertragsimports: der Nutzer sieht neue Verträge und Konflikte, bevor gespeichert wird.
struct ImportVorschau: Identifiable {
    let id = UUID()
    var quelle: String
    var abgleich: Abgleich
    var warnungen: [(zeile: Int, text: String)]
    var loesungen: [UUID: Konfliktloesung]

    init(quelle: String, abgleich: Abgleich, warnungen: [(zeile: Int, text: String)]) {
        self.quelle = quelle
        self.abgleich = abgleich
        self.warnungen = warnungen
        // Vorgabe: zusammenführen – nichts geht verloren
        self.loesungen = Dictionary(uniqueKeysWithValues: abgleich.konflikte.map { ($0.id, Konfliktloesung.zusammenfuehren) })
    }
}

struct ImportBericht: Identifiable {
    let id = UUID()
    var titel: String
    var zeilen: [String]
}

@MainActor
enum ImportDienst {
    static func alleVertraege(_ kontext: ModelContext) -> [Vertrag] {
        (try? kontext.fetch(FetchDescriptor<Vertrag>())) ?? []
    }

    // MARK: Verträge

    static func vorschau(_ ergebnis: VertragsImport, kontext: ModelContext) -> ImportVorschau {
        let bestand = alleVertraege(kontext).map(\.daten)
        let abgleich = Dubletten.abgleichen(bestand: bestand, importiert: ergebnis.vertraege)
        return ImportVorschau(quelle: ergebnis.quelle, abgleich: abgleich, warnungen: ergebnis.warnungen)
    }

    /// Speichert neue Verträge und gelöste Konflikte. Danach werden offene Zahlungen und Dokumente neu zugeordnet.
    @discardableResult
    static func uebernehmen(_ vorschau: ImportVorschau, kontext: ModelContext) throws -> ImportBericht {
        let bestand = Dictionary(alleVertraege(kontext).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var neu = 0, geaendert = 0
        for d in vorschau.abgleich.neu {
            kontext.insert(Vertrag(d))
            neu += 1
        }
        for k in vorschau.abgleich.konflikte {
            let loesung = vorschau.loesungen[k.id] ?? .zusammenfuehren
            guard loesung != .bestandBehalten else { continue }
            let ergebnis = Dubletten.loesen(k, mit: loesung)
            if let vorhanden = bestand[k.bestand.id] {
                vorhanden.uebernehmen(ergebnis)
                geaendert += 1
            }
        }
        try kontext.save()
        let zahlungen = try zahlungenZuordnen(kontext: kontext)
        let dokumente = try dokumenteZuordnen(kontext: kontext)
        var zeilen = ["\(neu) neue Verträge", "\(geaendert) Verträge aktualisiert",
                      "\(vorschau.abgleich.unveraendert.count) unverändert übersprungen"]
        if zahlungen > 0 { zeilen.append("\(zahlungen) Zahlungen nachträglich zugeordnet") }
        if dokumente > 0 { zeilen.append("\(dokumente) Dokumente nachträglich zugeordnet") }
        return ImportBericht(titel: "Import aus \(vorschau.quelle)", zeilen: zeilen)
    }

    // MARK: Zahlungen (NWO-Pay)

    static func zahlungenImportieren(_ daten: Data, dateiname: String, kontext: ModelContext) throws -> ImportBericht {
        let (gelesen, warnungen) = try PayImport.lesen(daten, dateiname: dateiname)
        let vorhanden = Set(((try? kontext.fetch(FetchDescriptor<Zahlung>())) ?? []).compactMap(\.externeID))
        let vertraege = alleVertraege(kontext)
        let nachID = Dictionary(vertraege.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let kernVertraege = vertraege.map(\.daten)
        var neu = 0, doppelt = 0, zugeordnet = 0
        for var z in gelesen {
            if let ext = z.externeID, vorhanden.contains(ext) { doppelt += 1; continue }
            z.vertragID = ZahlungsZuordnung.vertrag(fuer: z.buchungstext, in: kernVertraege)
            let vertrag = z.vertragID.flatMap { nachID[$0] }
            if vertrag != nil { zugeordnet += 1 }
            kontext.insert(Zahlung(z, vertrag: vertrag))
            neu += 1
        }
        try kontext.save()
        var zeilen = ["\(neu) neue Zahlungen", "\(zugeordnet) davon einem Vertrag zugeordnet",
                      "\(neu - zugeordnet) ohne Vertrag (siehe Prüfliste)", "\(doppelt) bereits vorhanden, übersprungen"]
        zeilen += warnungen.map { "Zeile \($0.zeile): \($0.text)" }
        return ImportBericht(titel: "NWO-Pay: \(dateiname)", zeilen: zeilen)
    }

    /// Ordnet alle Zahlungen ohne Vertrag erneut zu (z. B. nach einem Vertragsimport).
    @discardableResult
    static func zahlungenZuordnen(kontext: ModelContext) throws -> Int {
        let offen = try kontext.fetch(FetchDescriptor<Zahlung>(predicate: #Predicate { $0.vertrag == nil }))
        guard !offen.isEmpty else { return 0 }
        let vertraege = alleVertraege(kontext)
        let nachID = Dictionary(vertraege.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let kern = vertraege.map(\.daten)
        var anzahl = 0
        for z in offen {
            if let id = ZahlungsZuordnung.vertrag(fuer: z.buchungstext, in: kern), let v = nachID[id] {
                z.vertrag = v
                anzahl += 1
            }
        }
        try kontext.save()
        return anzahl
    }

    // MARK: Dokumente

    static func dokumentVorhanden(pfad: String, kontext: ModelContext) -> Bool {
        let anzahl = (try? kontext.fetchCount(FetchDescriptor<Dokument>(predicate: #Predicate { $0.pfad == pfad }))) ?? 0
        return anzahl > 0
    }

    /// Legt ein Dokument an und ordnet es per erkannter Vertragsnummer zu.
    @discardableResult
    static func dokumentAnlegen(pfad: String, text: String, kontext: ModelContext) -> Dokument {
        let vertraege = alleVertraege(kontext)
        let befund = Dokumenterkennung.auswerten(text: text, vertraege: vertraege.map(\.daten))
        let vertrag = befund.vertragID.flatMap { id in vertraege.first { $0.id == id } }
        let dokument = Dokument(pfad: pfad, typ: befund.typ, datum: befund.datum, vertrag: vertrag,
                                erkannterText: text, kandidaten: befund.kandidaten)
        kontext.insert(dokument)
        return dokument
    }

    /// Ordnet Dokumente ohne Vertrag anhand des gespeicherten Texts erneut zu.
    @discardableResult
    static func dokumenteZuordnen(kontext: ModelContext) throws -> Int {
        let offen = try kontext.fetch(FetchDescriptor<Dokument>(predicate: #Predicate { $0.vertrag == nil }))
        guard !offen.isEmpty else { return 0 }
        let vertraege = alleVertraege(kontext)
        let kern = vertraege.map(\.daten)
        var anzahl = 0
        for d in offen where !d.erkannterText.isEmpty {
            let befund = Dokumenterkennung.auswerten(text: d.erkannterText, vertraege: kern)
            if let id = befund.vertragID, let v = vertraege.first(where: { $0.id == id }) {
                d.vertrag = v
                anzahl += 1
            }
        }
        try kontext.save()
        return anzahl
    }
}

// MARK: - Vorschläge, Sicherung, Wiederherstellung

@MainActor
extension ImportDienst {
    /// Vorschläge für alle Zahlungen ohne Vertrag (Schlüssel: Zahlungs-ID).
    static func vorschlaege(kontext: ModelContext) -> [UUID: [Zuordnungsvorschlag]] {
        let alle = (try? kontext.fetch(FetchDescriptor<Zahlung>())) ?? []
        let kern = alle.map(\.daten)
        let vertraege = alleVertraege(kontext).map(\.daten)
        var ergebnis: [UUID: [Zuordnungsvorschlag]] = [:]
        for z in kern where z.vertragID == nil {
            let v = ZahlungsZuordnung.vorschlaege(fuer: z, vertraege: vertraege, zugeordnet: kern)
            if !v.isEmpty { ergebnis[z.id] = v }
        }
        return ergebnis
    }

    /// Übernimmt nur eindeutige Vorschläge mit hoher Punktzahl.
    @discardableResult
    static func sichereVorschlaegeUebernehmen(kontext: ModelContext) throws -> Int {
        let vorschlaege = vorschlaege(kontext: kontext)
        let zahlungen = Dictionary(((try? kontext.fetch(FetchDescriptor<Zahlung>())) ?? []).map { ($0.id, $0) },
                                   uniquingKeysWith: { a, _ in a })
        let vertraege = Dictionary(alleVertraege(kontext).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var anzahl = 0
        for (zahlungID, liste) in vorschlaege {
            guard let erster = liste.first, erster.sicher, let z = zahlungen[zahlungID], let v = vertraege[erster.vertragID] else { continue }
            z.vertrag = v
            anzahl += 1
        }
        try kontext.save()
        return anzahl
    }

    static func sicherung(kontext: ModelContext) throws -> Sicherung {
        let dokumente = try kontext.fetch(FetchDescriptor<Dokument>()).map {
            Sicherung.Dokument(daten: $0.daten, erkannterText: $0.erkannterText, kandidaten: $0.kandidaten)
        }
        return Sicherung(erstellt: .now,
                         vertraege: alleVertraege(kontext).map(\.daten),
                         zahlungen: try kontext.fetch(FetchDescriptor<Zahlung>()).map(\.daten),
                         dokumente: dokumente,
                         aufgaben: try kontext.fetch(FetchDescriptor<Aufgabe>()).map(\.daten))
    }

    /// Ersetzt den gesamten Bestand durch die Sicherung.
    static func wiederherstellen(_ s: Sicherung, kontext: ModelContext) throws {
        // einzeln löschen: Stapellöschung scheitert bei Beziehungen mit „nullify“
        for a in try kontext.fetch(FetchDescriptor<Aufgabe>()) { kontext.delete(a) }
        for d in try kontext.fetch(FetchDescriptor<Dokument>()) { kontext.delete(d) }
        for z in try kontext.fetch(FetchDescriptor<Zahlung>()) { kontext.delete(z) }
        for v in try kontext.fetch(FetchDescriptor<Vertrag>()) { kontext.delete(v) }
        try kontext.save()
        var nachID: [UUID: Vertrag] = [:]
        for d in s.vertraege {
            let v = Vertrag(d)
            kontext.insert(v)
            nachID[d.id] = v
        }
        for z in s.zahlungen { kontext.insert(Zahlung(z, vertrag: z.vertragID.flatMap { nachID[$0] })) }
        for d in s.dokumente {
            let dok = Dokument(id: d.daten.id, pfad: d.daten.pfad, typ: d.daten.typ, datum: d.daten.datum,
                               vertrag: d.daten.vertragID.flatMap { nachID[$0] }, erkannterText: d.erkannterText)
            dok.kandidaten = d.kandidaten
            kontext.insert(dok)
        }
        for a in s.aufgaben {
            kontext.insert(Aufgabe(id: a.id, titel: a.titel, faelligkeit: a.faelligkeit,
                                   vertrag: a.vertragID.flatMap { nachID[$0] }, erledigt: a.erledigt))
        }
        try kontext.save()
    }
}
