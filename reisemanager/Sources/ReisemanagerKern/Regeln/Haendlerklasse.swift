import Foundation

/// Grobe Einordnung eines Händlers. Bestimmt Kostenart, Vorauskauf-Fähigkeit und den Fundort des Belegs.
public enum Haendlerklasse: String, Sendable {
    case bahn, flug, hotel, taxi, oepnv, parken, tanken, abo, sonstige

    public var kostenart: Kostenart {
        switch self {
        case .bahn, .flug, .taxi, .oepnv: return .fahrt
        case .hotel: return .unterkunft
        case .parken, .tanken, .abo, .sonstige: return .sonstiges
        }
    }

    /// Wird typischerweise Wochen vor der Reise bezahlt: Zahlungstag ist nicht Reisetag.
    public var vorauskaufUeblich: Bool { self == .bahn || self == .flug }

    /// Fällt nur am Reisetag an. Liegt die Zahlung außerhalb der Reise, ist das ein Widerspruch.
    public var nurAmReisetag: Bool { self == .taxi || self == .oepnv || self == .parken }

    public var istReisebezogen: Bool { ![.tanken, .abo, .sonstige].contains(self) }

    static let muster: [(Haendlerklasse, [String])] = [
        // Reihenfolge zählt: „EASYJET“ ist ein Flug, kein „JET“.
        (.abo, ["UBER BV"]),
        (.flug, ["EUROWINGS", "LUFTHANSA", "RYANAIR", "EASYJET", "KLM", "AIRLINES", "AIRWAYS", "FLUG"]),
        (.bahn, ["DB VERTRIEB", "DEUTSCHE BAHN", "BAHN", "NATIONAL RAIL", "RAIL", "EUROSTAR", "SNCF", "NS INTERNATIONAL", "OEBB", "SBB"]),
        (.oepnv, ["RHEINBAHN", "BVG", "BERLINER VERKEHRSBETRIEBE", "KVB", "LOGPAY", "TFL", "TRAVEL CHARGE", "GVB", "VRR", "HVV", "MVG", "VERKEHRSBETRIEBE"]),
        (.taxi, ["UBER", "BOLT", "TAXI", "FREENOW", "FREE NOW"]),
        (.hotel, ["HOTEL", "IBIS", "MERCURE", "ADAGIO", "NOVOTEL", "HYATT", "STEIGENBERGER", "MOTEL ONE", "HILTON", "MARRIOTT", "PREMIER INN", "INTERCITYHOTEL", "LEONARDO"]),
        (.parken, ["PARKHAUS", "PARKEN", "PARKING", "PARKSCHEIN", "APCOA", "CONTIPARK", "Q PARK"]),
        (.tanken, ["TANKSTELLE", "SHELL", "ARAL", "ESSO", "TOTAL", "OIL", "JET", "AVIA", "BP", "TS"]),
    ]

    public static func bestimme(_ haendler: String) -> Haendlerklasse {
        let worte = haendler.uppercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        let satz = " " + worte.joined(separator: " ") + " "
        for (klasse, liste) in muster {
            for eintrag in liste {
                if eintrag.contains(" ") {
                    if satz.contains(" " + eintrag + " ") { return klasse }
                } else if worte.contains(where: { $0 == eintrag || (klasse != .tanken && eintrag.count >= 5 && $0.hasPrefix(eintrag)) }) {
                    // Markennamen stehen in Kartenabrechnungen oft zusammengezogen („HOTELMUSTERSTADT“), daher der Wortanfang.
                    // Tankstellenmarken sind kurze Alltagswörter und zählen nur als ganzes Wort.
                    return klasse
                }
            }
        }
        return .sonstige
    }

    static let accor = ["IBIS", "MERCURE", "ADAGIO", "NOVOTEL", "SOFITEL", "PULLMAN"]

    /// Wo der Beleg zu holen ist. Für die Liste „Was ich noch besorgen muss“.
    public static func fundort(haendler: String, quelle: String?, datum: Tag?) -> String {
        let gross = haendler.uppercased()
        switch bestimme(haendler) {
        case .bahn: return "bahn.de → Meine Reisen → Rechnung herunterladen"
        case .flug: return "Buchungsportal der Fluggesellschaft → Rechnung"
        case .hotel: return accor.contains(where: { gross.contains($0) }) ? "ALL Accor → Rechnung" : "Hotel → Rechnung anfordern"
        case .taxi: return "Uber-/Bolt-App oder Mail-Quittung"
        case .oepnv: return "App oder Mail des Verkehrsbetriebs"
        case .parken: return "Parkschein scannen"
        case .tanken: return "Kassenbon oder Amex-Abrechnung"
        case .abo, .sonstige: break
        }
        let q = (quelle ?? "").lowercased()
        if q.contains("amex"), let datum { return "Amex-Abrechnung \(String(format: "%02d/%04d", datum.monat, datum.jahr))" }
        if q.contains("amex") { return "Amex-Abrechnung" }
        if q.contains("paypal") { return "PayPal → Aktivitäten → Beleg" }
        return "Rechnung oder Quittung beim Anbieter anfordern"
    }
}
