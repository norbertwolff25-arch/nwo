import Foundation

// MARK: - Aufzählungen

public enum VertragsStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case aktiv
    case beitragsfrei
    case beendet
    case pruefen = "prüfen"

    public var id: String { rawValue }

    public var anzeige: String {
        switch self {
        case .aktiv: "Aktiv"
        case .beitragsfrei: "Beitragsfrei"
        case .beendet: "Beendet"
        case .pruefen: "Prüfen"
        }
    }

    /// Erkennt deutsche und englische Schreibweisen (z. B. aus einem Clark-Export).
    public static func erkennen(_ text: String) -> VertragsStatus? {
        let t = Textnorm.schluessel(text)
        if t.isEmpty { return nil }
        let tabelle: [(VertragsStatus, [String])] = [
            (.pruefen, ["pruefen", "prufen", "review", "unklar", "offen", "check", "pending"]),
            (.beitragsfrei, ["beitragsfrei", "beitragsfreigestellt", "ruhend", "paidup", "premiumfree", "dormant"]),
            (.beendet, ["beendet", "gekuendigt", "gekundigt", "storniert", "abgelaufen", "erloschen", "terminated",
                        "cancelled", "canceled", "inactive", "ended", "expired", "closed"]),
            (.aktiv, ["aktiv", "active", "laufend", "inkraft", "running", "valid"])
        ]
        for (status, woerter) in tabelle where woerter.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return status
        }
        return nil
    }
}

public enum Zahlweise: String, Codable, CaseIterable, Sendable, Identifiable {
    case monatlich
    case vierteljaehrlich = "vierteljährlich"
    case halbjaehrlich = "halbjährlich"
    case jaehrlich = "jährlich"
    case einmalig
    case beitragsfrei

    public var id: String { rawValue }

    public var anzeige: String {
        switch self {
        case .monatlich: "monatlich"
        case .vierteljaehrlich: "vierteljährlich"
        case .halbjaehrlich: "halbjährlich"
        case .jaehrlich: "jährlich"
        case .einmalig: "einmalig"
        case .beitragsfrei: "beitragsfrei"
        }
    }

    /// Anzahl der laufenden Zahlungen pro Jahr (Einmalbeitrag und beitragsfrei: 0).
    public var zahlungenProJahr: Int {
        switch self {
        case .monatlich: 12
        case .vierteljaehrlich: 4
        case .halbjaehrlich: 2
        case .jaehrlich: 1
        case .einmalig, .beitragsfrei: 0
        }
    }

    public static func erkennen(_ text: String) -> Zahlweise? {
        let t = Textnorm.schluessel(text)
        if t.isEmpty { return nil }
        let tabelle: [(Zahlweise, [String])] = [
            (.vierteljaehrlich, ["vierteljaehrlich", "vierteljahrlich", "vj", "vierteljahr", "quarterly", "quartal", "quartalsweise", "4"]),
            (.halbjaehrlich, ["halbjaehrlich", "halbjahrlich", "hj", "halbjahr", "semiannually", "semiannual", "halfyearly", "biannual", "2"]),
            (.monatlich, ["monatlich", "mtl", "monthly", "monat", "12"]),
            (.jaehrlich, ["jaehrlich", "jahrlich", "jhrl", "jaehrl", "annually", "annual", "yearly", "jahr", "1"]),
            (.einmalig, ["einmalig", "einmalbeitrag", "einmal", "single", "once", "oneoff", "6"]),
            (.beitragsfrei, ["beitragsfrei", "keine", "none", "paidup", "0"])
        ]
        for (weise, woerter) in tabelle where woerter.contains(t) { return weise }
        for (weise, woerter) in tabelle where woerter.contains(where: { $0.count > 3 && t.hasPrefix($0) }) {
            return weise
        }
        return nil
    }
}

public enum Betreuer: String, Codable, CaseIterable, Sendable, Identifiable {
    case clark = "Clark"
    case neu
    case direkt

    public var id: String { rawValue }

    public var anzeige: String {
        switch self {
        case .clark: "Clark"
        case .neu: "Neuer Berater"
        case .direkt: "Direkt beim Versicherer"
        }
    }

    public static func erkennen(_ text: String) -> Betreuer? {
        let t = Textnorm.schluessel(text)
        if t.isEmpty { return nil }
        if t.contains("clark") { return .clark }
        if t.hasPrefix("neu") || t.contains("new") { return .neu }
        if t.hasPrefix("direkt") || t.hasPrefix("direct") || t == "ohne" || t == "keiner" { return .direkt }
        return nil
    }
}

public enum DokumentTyp: String, Codable, CaseIterable, Sendable, Identifiable {
    case police = "Police"
    case nachtrag = "Nachtrag"
    case beitragsrechnung = "Beitragsrechnung"
    case jahresbescheinigung = "Jahresbescheinigung"
    case sonstiges = "Sonstiges"

    public var id: String { rawValue }
    public var anzeige: String { rawValue }
}

// MARK: - Datensätze (Wertetypen, unabhängig von SwiftData)

public struct VertragsDaten: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var versicherer: String
    public var sparte: String
    public var vertragsnummer: String
    public var tarif: String
    public var beginn: Date?
    public var ablauf: Date?
    public var kuendigungsfrist: String
    /// Beitrag je Zahlungsperiode laut `zahlweise`.
    public var beitrag: Decimal?
    public var zahlweise: Zahlweise?
    public var dynamikProzent: Decimal?
    public var status: VertragsStatus
    public var steuerlicheEinordnung: String
    public var betreuer: Betreuer?
    public var notizen: String

    public init(
        id: UUID = UUID(),
        versicherer: String = "",
        sparte: String = "",
        vertragsnummer: String = "",
        tarif: String = "",
        beginn: Date? = nil,
        ablauf: Date? = nil,
        kuendigungsfrist: String = "",
        beitrag: Decimal? = nil,
        zahlweise: Zahlweise? = nil,
        dynamikProzent: Decimal? = nil,
        status: VertragsStatus = .aktiv,
        steuerlicheEinordnung: String = "",
        betreuer: Betreuer? = nil,
        notizen: String = ""
    ) {
        self.id = id
        self.versicherer = versicherer
        self.sparte = sparte
        self.vertragsnummer = vertragsnummer
        self.tarif = tarif
        self.beginn = beginn
        self.ablauf = ablauf
        self.kuendigungsfrist = kuendigungsfrist
        self.beitrag = beitrag
        self.zahlweise = zahlweise
        self.dynamikProzent = dynamikProzent
        self.status = status
        self.steuerlicheEinordnung = steuerlicheEinordnung
        self.betreuer = betreuer
        self.notizen = notizen
    }

    /// Jahresbeitrag aus Beitrag und Zahlweise. Ohne Zahlweise wird jährlich angenommen.
    public var jahresbeitrag: Decimal {
        guard let beitrag else { return 0 }
        guard status == .aktiv || status == .pruefen else { return 0 }
        let faktor = zahlweise?.zahlungenProJahr ?? 1
        return beitrag * Decimal(faktor)
    }

    public var monatsbeitrag: Decimal { Zahl.runden(jahresbeitrag / 12) }

    /// Schlüssel für die Dublettenerkennung.
    public var dublettenSchluessel: String {
        Textnorm.vertragsnummer(vertragsnummer) + "|" + Textnorm.versichererSchluessel(versicherer)
    }

    /// Hängt eine Notiz zeilenweise an, ohne Doppelungen.
    public mutating func notizAnhaengen(_ zeile: String) {
        let z = zeile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !z.isEmpty else { return }
        let vorhanden = notizen.split(separator: "\n").map { String($0) }
        if vorhanden.contains(z) { return }
        notizen = notizen.isEmpty ? z : notizen + "\n" + z
    }
}

public struct ZahlungsDaten: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Eindeutige Kennung der Quelle (z. B. `pay_id`), verhindert doppelten Import.
    public var externeID: String?
    public var datum: Date
    /// Vorzeichenbehaftet: Ausgang (Beitrag) negativ, Eingang (Erstattung, Auszahlung) positiv.
    public var betrag: Decimal
    public var buchungstext: String
    public var quelle: String
    public var vertragID: UUID?

    public init(id: UUID = UUID(), externeID: String? = nil, datum: Date, betrag: Decimal,
                buchungstext: String, quelle: String, vertragID: UUID? = nil) {
        self.id = id
        self.externeID = externeID
        self.datum = datum
        self.betrag = betrag
        self.buchungstext = buchungstext
        self.quelle = quelle
        self.vertragID = vertragID
    }
}

public struct DokumentDaten: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var pfad: String
    public var typ: DokumentTyp
    public var datum: Date?
    public var vertragID: UUID?

    public init(id: UUID = UUID(), pfad: String, typ: DokumentTyp, datum: Date?, vertragID: UUID?) {
        self.id = id
        self.pfad = pfad
        self.typ = typ
        self.datum = datum
        self.vertragID = vertragID
    }

    public var dateiname: String { (pfad as NSString).lastPathComponent }
}

public struct AufgabeDaten: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var titel: String
    public var faelligkeit: Date?
    public var vertragID: UUID?
    public var erledigt: Bool

    public init(id: UUID = UUID(), titel: String, faelligkeit: Date?, vertragID: UUID?, erledigt: Bool = false) {
        self.id = id
        self.titel = titel
        self.faelligkeit = faelligkeit
        self.vertragID = vertragID
        self.erledigt = erledigt
    }
}
