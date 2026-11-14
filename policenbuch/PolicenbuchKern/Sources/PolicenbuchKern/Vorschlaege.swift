import Foundation

/// Vorschlag für eine Zahlung ohne Vertragsnummer im Verwendungszweck. Wird nie automatisch übernommen.
public struct Zuordnungsvorschlag: Sendable, Hashable, Identifiable {
    public var vertragID: UUID
    /// 0 bis 100
    public var punkte: Int
    public var gruende: [String]
    /// Eindeutig und mit hoher Punktzahl – darf per Sammelknopf übernommen werden.
    public var sicher: Bool
    public var id: UUID { vertragID }
}

extension ZahlungsZuordnung {
    public static let mindestpunkte = 40

    /// Bewertet jeden Vertrag nach Versicherer im Buchungstext, Betrag passend zum Beitrag
    /// und Übereinstimmung mit bereits zugeordneten Zahlungen.
    public static func vorschlaege(fuer zahlung: ZahlungsDaten, vertraege: [VertragsDaten],
                                   zugeordnet: [ZahlungsDaten]) -> [Zuordnungsvorschlag] {
        let text = Textnorm.schluessel(zahlung.buchungstext)
        let betrag = abs(zahlung.betrag)
        let gegenpartei = gegenparteiTeil(zahlung.buchungstext)
        var ergebnis: [Zuordnungsvorschlag] = []

        for v in vertraege {
            var punkte = 0
            var gruende: [String] = []

            // 1. Versicherer im Buchungstext
            let woerter = Textnorm.versichererSchluessel(v.versicherer).split(separator: " ").map(String.init).filter { $0.count >= 3 }
            if let erstes = woerter.first, text.contains(erstes) {
                punkte += 50
                gruende.append("Versicherer „\(v.versicherer)“ im Buchungstext")
            }

            // 2. Betrag passt zum Beitrag (nur Ausgänge)
            if zahlung.betrag < 0, let beitrag = v.beitrag, beitrag > 0 {
                let abweichung = abs(betrag - beitrag)
                if abweichung <= Decimal(string: "0.01")! {
                    punkte += 40
                    gruende.append("Betrag entspricht dem Beitrag (\(Zahl.euro(beitrag)))")
                } else if abweichung <= beitrag * Decimal(string: "0.05")! {
                    punkte += 20
                    gruende.append("Betrag nahe am Beitrag (\(Zahl.euro(beitrag)), z. B. Dynamik)")
                }
            }

            // 3. Frühere Zahlungen dieses Vertrags
            let frueher = zugeordnet.filter { $0.vertragID == v.id && $0.id != zahlung.id }
            if !gegenpartei.isEmpty, frueher.contains(where: { gegenparteiTeil($0.buchungstext) == gegenpartei }) {
                punkte += 30
                gruende.append("Gleiche Gegenpartei wie frühere Zahlungen")
            }
            if frueher.contains(where: { abs($0.betrag) == betrag && ($0.betrag < 0) == (zahlung.betrag < 0) }) {
                punkte += 20
                gruende.append("Gleicher Betrag wie eine frühere Zahlung")
            }

            if v.status == .beendet { punkte -= 30 }
            punkte = min(punkte, 100)
            if punkte >= mindestpunkte {
                ergebnis.append(Zuordnungsvorschlag(vertragID: v.id, punkte: punkte, gruende: gruende, sicher: false))
            }
        }
        ergebnis.sort { $0.punkte != $1.punkte ? $0.punkte > $1.punkte : $0.vertragID.uuidString < $1.vertragID.uuidString }
        if let erster = ergebnis.first, erster.punkte >= 80 {
            let zweiter = ergebnis.count > 1 ? ergebnis[1].punkte : 0
            if erster.punkte - zweiter >= 20 { ergebnis[0].sicher = true }
        }
        return ergebnis
    }

    /// Teil vor „ – “ (so baut der NWO-Pay-Import den Buchungstext), normalisiert.
    static func gegenparteiTeil(_ buchungstext: String) -> String {
        let teil = buchungstext.components(separatedBy: " – ").first ?? ""
        return teil == buchungstext ? "" : Textnorm.schluessel(teil)
    }
}
