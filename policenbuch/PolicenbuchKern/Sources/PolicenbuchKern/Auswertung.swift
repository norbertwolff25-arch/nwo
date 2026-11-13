import Foundation

// MARK: - Übersicht nach Sparte

public struct SpartenSumme: Sendable, Hashable, Identifiable {
    public var sparte: String
    public var anzahl: Int
    public var jahresbeitrag: Decimal
    public var monatsbeitrag: Decimal { Zahl.runden(jahresbeitrag / 12) }
    public var id: String { sparte }
}

public enum Uebersicht {
    public static let ohneSparte = "Ohne Sparte"

    /// Summen je Sparte (nur aktive und zu prüfende Verträge zählen zum Beitrag), absteigend nach Jahresbeitrag.
    public static func nachSparte(_ vertraege: [VertragsDaten]) -> [SpartenSumme] {
        var summen: [String: SpartenSumme] = [:]
        for v in vertraege where v.status != .beendet {
            let s = v.sparte.isEmpty ? ohneSparte : v.sparte
            var eintrag = summen[s] ?? SpartenSumme(sparte: s, anzahl: 0, jahresbeitrag: 0)
            eintrag.anzahl += 1
            eintrag.jahresbeitrag += v.jahresbeitrag
            summen[s] = eintrag
        }
        return summen.values.sorted {
            $0.jahresbeitrag != $1.jahresbeitrag ? $0.jahresbeitrag > $1.jahresbeitrag : $0.sparte < $1.sparte
        }
    }

    public static func jahresbeitragGesamt(_ vertraege: [VertragsDaten]) -> Decimal {
        vertraege.reduce(0) { $0 + $1.jahresbeitrag }
    }
}

// MARK: - Prüfliste

public struct Pruefliste: Sendable {
    public var zuPruefen: [VertragsDaten]
    public var zahlungenOhneVertrag: [ZahlungsDaten]
    public var ohneZahlungImJahr: [VertragsDaten]

    public var istLeer: Bool { zuPruefen.isEmpty && zahlungenOhneVertrag.isEmpty && ohneZahlungImJahr.isEmpty }

    /// - Parameter jahr: laufendes Jahr. Verträge, die erst in diesem Jahr beginnen, zählen nur ab Beginn.
    public static func erstellen(vertraege: [VertragsDaten], zahlungen: [ZahlungsDaten], jahr: Int, stichtag: Date) -> Pruefliste {
        let zuPruefen = vertraege.filter { $0.status == .pruefen }
        let ohneVertrag = zahlungen.filter { $0.vertragID == nil }.sorted { $0.datum > $1.datum }
        let mitZahlung = Set(zahlungen.filter { Datum.jahr($0.datum) == jahr }.compactMap(\.vertragID))
        let ohneZahlung = vertraege.filter { v in
            guard v.status == .aktiv, (v.zahlweise?.zahlungenProJahr ?? 1) > 0, (v.beitrag ?? 0) > 0 else { return false }
            if let beginn = v.beginn, beginn > stichtag { return false }
            if let ablauf = v.ablauf, Datum.jahr(ablauf) < jahr { return false }
            // Jährliche Zahler mit Fälligkeit später im Jahr nicht anmahnen
            if v.zahlweise == .jaehrlich, let beginn = v.beginn {
                let faellig = Datum.kalender.dateComponents([.month, .day], from: beginn)
                if let jahresTermin = Datum.tag(jahr, faellig.month ?? 1, min(faellig.day ?? 1, 28)), jahresTermin > stichtag {
                    return false
                }
            }
            return !mitZahlung.contains(v.id)
        }
        return Pruefliste(zuPruefen: zuPruefen, zahlungenOhneVertrag: ohneVertrag, ohneZahlungImJahr: ohneZahlung)
    }
}

// MARK: - Beitragsverlauf

public struct Verlaufspunkt: Sendable, Hashable, Identifiable {
    public var datum: Date
    public var betrag: Decimal
    public var id: Date { datum }
}

public enum Beitragsverlauf {
    /// Gezahlte Beiträge (Ausgänge als positive Werte) je Kalenderjahr.
    public static func jeJahr(_ zahlungen: [ZahlungsDaten]) -> [Verlaufspunkt] {
        var summen: [Int: Decimal] = [:]
        for z in zahlungen where z.betrag < 0 {
            summen[Datum.jahr(z.datum), default: 0] += -z.betrag
        }
        return summen.keys.sorted().compactMap { j in
            Datum.tag(j, 7, 1).map { Verlaufspunkt(datum: $0, betrag: summen[j]!) }
        }
    }

    /// Einzelzahlungen als Beitragsverlauf (für Erkennung von Dynamik-Erhöhungen).
    public static func einzeln(_ zahlungen: [ZahlungsDaten]) -> [Verlaufspunkt] {
        zahlungen.filter { $0.betrag < 0 }
            .sorted { $0.datum < $1.datum }
            .map { Verlaufspunkt(datum: $0.datum, betrag: -$0.betrag) }
    }
}

// MARK: - Fristen

public enum FristArt: String, Sendable, CaseIterable {
    case kuendigung = "Kündigung"
    case ablauf = "Ablauf"
    case aufgabe = "Aufgabe"
}

public struct Frist: Sendable, Hashable, Identifiable {
    public var art: FristArt
    public var datum: Date
    public var vertragID: UUID?
    public var titel: String
    /// Wann erinnert werden soll.
    public var erinnerung: Date

    public var id: String { "\(art.rawValue)|\(vertragID?.uuidString ?? titel)|\(Datum.iso(datum))" }
}

public enum Fristen {
    /// Liest Kündigungsfristen wie „3 Monate“, „3 Monate zum Ablauf“, „1 Monat“, „6 Wochen“, „14 Tage“, „3“.
    public static func dauer(_ text: String) -> (monate: Int, tage: Int)? {
        let t = text.lowercased()
        guard let zahl = t.split(whereSeparator: { !$0.isNumber }).first.flatMap({ Int($0) }) else {
            if t.contains("ein monat") || t.contains("einen monat") { return (1, 0) }
            if t.contains("drei monate") { return (3, 0) }
            return nil
        }
        if t.contains("woche") { return (0, zahl * 7) }
        if t.contains("tag") { return (0, zahl) }
        if t.contains("jahr") { return (zahl * 12, 0) }
        return (zahl, 0)
    }

    /// Nächste Hauptfälligkeit (Jahrestag des Beginns) ab Stichtag.
    public static func naechsteHauptfaelligkeit(beginn: Date, ab stichtag: Date) -> Date {
        var kandidat = beginn
        var schritte = 0
        while kandidat <= stichtag && schritte < 200 {
            kandidat = Datum.plus(monate: 12, zu: kandidat)
            schritte += 1
        }
        return kandidat
    }

    /// Kündigungs- und Ablauftermine aller laufenden Verträge ab Stichtag.
    /// - Parameter vorlaufTage: Erinnerung so viele Tage vor dem Termin (Ablauf: dreifach, mind. 90 Tage).
    public static func berechnen(vertraege: [VertragsDaten], aufgaben: [AufgabeDaten] = [], stichtag: Date,
                                 vorlaufTage: Int = 30) -> [Frist] {
        var ergebnis: [Frist] = []
        for v in vertraege where v.status != .beendet {
            let name = [v.versicherer, v.sparte].filter { !$0.isEmpty }.joined(separator: " · ")
            // Ablauf (z. B. Kapitalauszahlung)
            if let ablauf = v.ablauf, ablauf >= stichtag {
                let vorlauf = max(90, vorlaufTage * 3)
                ergebnis.append(Frist(art: .ablauf, datum: ablauf, vertragID: v.id, titel: "Ablauf \(name)",
                                      erinnerung: max(stichtag, Datum.plus(tage: -vorlauf, zu: ablauf))))
            }
            // Kündigungstermin: Ablauf bzw. nächste Hauptfälligkeit minus Frist
            guard v.status == .aktiv || v.status == .pruefen, let frist = dauer(v.kuendigungsfrist) else { continue }
            let bezug: Date?
            if let ablauf = v.ablauf {
                bezug = ablauf
            } else if let beginn = v.beginn {
                var hf = naechsteHauptfaelligkeit(beginn: beginn, ab: stichtag)
                // Termin dieses Jahr schon vorbei? Dann nächstes Jahr.
                if Datum.plus(monate: -frist.monate, tage: -frist.tage, zu: hf) < stichtag {
                    hf = Datum.plus(monate: 12, zu: hf)
                }
                bezug = hf
            } else {
                bezug = nil
            }
            guard let bezug else { continue }
            let termin = Datum.plus(monate: -frist.monate, tage: -frist.tage, zu: bezug)
            guard termin >= stichtag else { continue }
            ergebnis.append(Frist(art: .kuendigung, datum: termin, vertragID: v.id,
                                  titel: "Kündigung spätestens \(name)",
                                  erinnerung: max(stichtag, Datum.plus(tage: -vorlaufTage, zu: termin))))
        }
        for a in aufgaben where !a.erledigt {
            guard let f = a.faelligkeit else { continue }
            ergebnis.append(Frist(art: .aufgabe, datum: f, vertragID: a.vertragID, titel: a.titel,
                                  erinnerung: max(stichtag, Datum.plus(tage: -3, zu: f))))
        }
        return ergebnis.sorted { $0.datum < $1.datum }
    }
}
