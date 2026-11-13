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
