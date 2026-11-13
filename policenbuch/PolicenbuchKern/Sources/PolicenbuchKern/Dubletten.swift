import Foundation

/// Ein Feld, in dem sich Bestand und Import unterscheiden.
public struct Feldunterschied: Sendable, Hashable, Identifiable {
    public var feld: Zielfeld
    public var bestand: String
    public var importiert: String
    public var id: Zielfeld { feld }
}

/// Bestandsvertrag und importierter Vertrag mit gleicher Vertragsnummer und gleichem Versicherer.
public struct Dublettenkonflikt: Sendable, Identifiable {
    public var bestand: VertragsDaten
    public var importiert: VertragsDaten
    public var unterschiede: [Feldunterschied]
    public var id: UUID { importiert.id }
}

public enum Konfliktloesung: String, Sendable, CaseIterable, Identifiable {
    case bestandBehalten
    case importUebernehmen
    case zusammenfuehren
    public var id: String { rawValue }

    public var anzeige: String {
        switch self {
        case .bestandBehalten: "Bestand behalten"
        case .importUebernehmen: "Import übernehmen"
        case .zusammenfuehren: "Zusammenführen"
        }
    }
}

public struct Abgleich: Sendable {
    /// Wirklich neue Verträge.
    public var neu: [VertragsDaten]
    /// Gleiche Verträge ohne inhaltlichen Unterschied (werden übersprungen).
    public var unveraendert: [VertragsDaten]
    /// Gleiche Verträge mit Unterschieden – der Nutzer entscheidet.
    public var konflikte: [Dublettenkonflikt]
}

public enum Dubletten {
    /// Gleiche Nummer und Versicherer. Versicherer gelten als gleich, wenn sie normalisiert übereinstimmen
    /// oder das erste Wort gleich ist („Allianz“ ↔ „Allianz Lebensversicherungs-AG“).
    public static func gleich(_ a: VertragsDaten, _ b: VertragsDaten) -> Bool {
        let na = Text.vertragsnummer(a.vertragsnummer)
        let nb = Text.vertragsnummer(b.vertragsnummer)
        guard !na.isEmpty, na == nb else { return false }
        let va = Text.versichererSchluessel(a.versicherer)
        let vb = Text.versichererSchluessel(b.versicherer)
        if va == vb { return true }
        if va.isEmpty || vb.isEmpty { return false }
        let ersteA = va.split(separator: " ").first
        let ersteB = vb.split(separator: " ").first
        return ersteA == ersteB
    }

    public static func unterschiede(_ a: VertragsDaten, _ b: VertragsDaten) -> [Feldunterschied] {
        let felder: [(Zielfeld, (VertragsDaten) -> String)] = [
            (.versicherer, { $0.versicherer }),
            (.sparte, { $0.sparte }),
            (.vertragsnummer, { $0.vertragsnummer }),
            (.tarif, { $0.tarif }),
            (.beginn, { Datum.deutsch($0.beginn) }),
            (.ablauf, { Datum.deutsch($0.ablauf) }),
            (.kuendigungsfrist, { $0.kuendigungsfrist }),
            (.beitrag, { $0.beitrag.map { Zahl.euro($0) } ?? "" }),
            (.zahlweise, { $0.zahlweise?.anzeige ?? "" }),
            (.dynamikProzent, { $0.dynamikProzent.map { Zahl.deutsch($0) + " %" } ?? "" }),
            (.status, { $0.status.anzeige }),
            (.steuerlicheEinordnung, { $0.steuerlicheEinordnung }),
            (.betreuer, { $0.betreuer?.anzeige ?? "" }),
            (.notizen, { $0.notizen })
        ]
        return felder.compactMap { feld, wert in
            let x = wert(a), y = wert(b)
            if feld == .vertragsnummer && Text.vertragsnummer(x) == Text.vertragsnummer(y) { return nil }
            if feld == .versicherer && Text.versichererSchluessel(x) == Text.versichererSchluessel(y) { return nil }
            // leerer Importwert ist kein Widerspruch
            if y.isEmpty || x == y { return nil }
            return Feldunterschied(feld: feld, bestand: x, importiert: y)
        }
    }

    /// Gleicht importierte Verträge mit dem Bestand ab, auch Dubletten innerhalb der Importdatei.
    public static func abgleichen(bestand: [VertragsDaten], importiert: [VertragsDaten]) -> Abgleich {
        var neu: [VertragsDaten] = []
        var unveraendert: [VertragsDaten] = []
        var konflikte: [Dublettenkonflikt] = []
        for kandidat in importiert {
            if let vorhanden = bestand.first(where: { gleich($0, kandidat) }) ?? neu.first(where: { gleich($0, kandidat) }) {
                let u = unterschiede(vorhanden, kandidat)
                if u.isEmpty {
                    unveraendert.append(kandidat)
                } else {
                    konflikte.append(Dublettenkonflikt(bestand: vorhanden, importiert: kandidat, unterschiede: u))
                }
            } else {
                neu.append(kandidat)
            }
        }
        return Abgleich(neu: neu, unveraendert: unveraendert, konflikte: konflikte)
    }

    /// Ergebnis einer Konfliktlösung. Die ID des Bestands bleibt immer erhalten.
    public static func loesen(_ konflikt: Dublettenkonflikt, mit loesung: Konfliktloesung) -> VertragsDaten {
        switch loesung {
        case .bestandBehalten:
            return konflikt.bestand
        case .importUebernehmen:
            var v = konflikt.importiert
            v.id = konflikt.bestand.id
            // Notizen nie verlieren
            for zeile in konflikt.bestand.notizen.split(separator: "\n") { v.notizAnhaengen(String(zeile)) }
            return v
        case .zusammenfuehren:
            return zusammenfuehren(bestand: konflikt.bestand, neu: konflikt.importiert)
        }
    }

    /// Leere Felder im Bestand werden aus dem Import gefüllt; abweichende Werte kommen in die Notizen.
    public static func zusammenfuehren(bestand: VertragsDaten, neu: VertragsDaten) -> VertragsDaten {
        var v = bestand
        func fuellen(_ ziel: WritableKeyPath<VertragsDaten, String>) {
            if v[keyPath: ziel].isEmpty { v[keyPath: ziel] = neu[keyPath: ziel] }
        }
        fuellen(\.sparte); fuellen(\.tarif); fuellen(\.kuendigungsfrist); fuellen(\.steuerlicheEinordnung)
        if v.beginn == nil { v.beginn = neu.beginn }
        if v.ablauf == nil { v.ablauf = neu.ablauf }
        if v.beitrag == nil { v.beitrag = neu.beitrag }
        if v.zahlweise == nil { v.zahlweise = neu.zahlweise }
        if v.dynamikProzent == nil { v.dynamikProzent = neu.dynamikProzent }
        if v.betreuer == nil { v.betreuer = neu.betreuer }
        for u in unterschiede(v, neu) where u.feld != .notizen {
            v.notizAnhaengen("Import abweichend – \(u.feld.anzeige): \(u.importiert)")
        }
        for zeile in neu.notizen.split(separator: "\n") { v.notizAnhaengen(String(zeile)) }
        return v
    }
}
