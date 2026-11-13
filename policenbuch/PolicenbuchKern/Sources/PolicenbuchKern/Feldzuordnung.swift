import Foundation

/// Zielfelder eines Vertrags, auf die Quellspalten abgebildet werden können.
public enum Zielfeld: String, CaseIterable, Codable, Sendable, Identifiable {
    case versicherer, sparte, vertragsnummer, tarif, beginn, ablauf, kuendigungsfrist
    case beitrag, zahlweise, dynamikProzent, status, steuerlicheEinordnung, betreuer, notizen
    /// Feld bewusst nicht übernehmen (nur für Zugangsdaten u. Ä. gedacht).
    case ignorieren

    public var id: String { rawValue }

    public var anzeige: String {
        switch self {
        case .versicherer: "Versicherer"
        case .sparte: "Sparte"
        case .vertragsnummer: "Vertragsnummer"
        case .tarif: "Tarif"
        case .beginn: "Beginn"
        case .ablauf: "Ablauf"
        case .kuendigungsfrist: "Kündigungsfrist"
        case .beitrag: "Beitrag"
        case .zahlweise: "Zahlweise"
        case .dynamikProzent: "Dynamik (%)"
        case .status: "Status"
        case .steuerlicheEinordnung: "Steuerliche Einordnung"
        case .betreuer: "Betreuer"
        case .notizen: "→ Notizen"
        case .ignorieren: "Ignorieren"
        }
    }

    /// Bekannte Spaltennamen (normalisiert mit `Text.schluessel`).
    static let synonyme: [Zielfeld: [String]] = [
        .versicherer: ["versicherer", "gesellschaft", "versicherungsgesellschaft", "anbieter", "insurer", "insurancecompany",
                       "company", "carrier", "provider", "risikotraeger", "vu", "versicherungsunternehmen", "insurername",
                       "insurancename", "companyname", "providername"],
        .sparte: ["sparte", "versicherungsart", "art", "produktart", "kategorie", "category", "type", "insurancetype",
                  "line", "lineofbusiness", "produkt", "product", "productname", "sparteklartext", "categoryname"],
        .vertragsnummer: ["vertragsnummer", "vertragsnr", "vertragnr", "policennummer", "policennr", "policenummer", "polizzennummer",
                          "versicherungsscheinnummer", "versicherungsscheinnr", "vsnr", "vsnummer", "contractnumber",
                          "policynumber", "policyno", "contractno", "number", "nummer", "vertrag"],
        .tarif: ["tarif", "tarifname", "tarifbezeichnung", "tariff", "plan", "tarifvariante"],
        .beginn: ["beginn", "vertragsbeginn", "versicherungsbeginn", "start", "startdate", "startdatum", "begin",
                  "beginndatum", "contractstart", "inceptiondate", "validfrom"],
        .ablauf: ["ablauf", "ablaufdatum", "vertragsende", "ende", "enddatum", "end", "enddate", "expiry", "expirydate",
                  "vertragsablauf", "laufzeitende", "contractend", "validuntil", "auszahlungsdatum", "maturitydate"],
        .kuendigungsfrist: ["kuendigungsfrist", "kuendigung", "noticeperiod", "cancellationperiod", "frist"],
        .beitrag: ["beitrag", "beitrageur", "praemie", "premium", "betrag", "amount", "beitraginEUR", "zahlbeitrag",
                   "bruttobeitrag", "price", "preis", "kosten", "premiumamount"],
        .zahlweise: ["zahlweise", "zahlungsweise", "zahlungsintervall", "intervall", "paymentinterval", "paymentfrequency",
                     "frequency", "zahlungsrhythmus", "billingfrequency", "interval"],
        .dynamikProzent: ["dynamik", "dynamikprozent", "dynamiksatz", "dynamic", "dynamicpercent", "beitragsdynamik"],
        .status: ["status", "vertragsstatus", "state", "contractstatus", "zustand"],
        .steuerlicheEinordnung: ["steuerlicheeinordnung", "steuer", "steuerlich", "steuerart", "tax", "taxcategory",
                                 "taxtreatment", "schicht", "steuerschicht", "absetzbarkeit"],
        .betreuer: ["betreuer", "vermittler", "makler", "berater", "broker", "advisor", "betreuung", "agent"],
        .notizen: ["notizen", "notiz", "bemerkung", "bemerkungen", "kommentar", "comment", "comments", "notes", "note", "hinweis"]
    ]

    /// Feldnamen, deren Werte nie gespeichert werden (Zugangsdaten).
    static let geheim: [String] = ["passwort", "password", "kennwort", "pin", "tan", "token", "secret", "geheim",
                                   "zugangsdaten", "login", "benutzername", "username", "apikey", "sessionid"]

    public static func istGeheim(_ feldname: String) -> Bool {
        let k = Text.schluessel(feldname)
        let woerter = feldname.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        return geheim.contains { g in k == g || woerter.contains(g) || (g.count >= 5 && k.hasSuffix(g)) }
    }

    /// Schlägt ein Zielfeld für einen Quellspaltennamen vor (auch für verschachtelte JSON-Pfade wie „insurer.name“).
    public static func vorschlag(fuer spalte: String) -> Zielfeld? {
        vorschlagMitGuete(fuer: spalte)?.feld
    }

    /// Güte 3: ganzer Name, 2: letztes Segment oder „eltern+feld“, 1: nur Elternobjekt („insurer.bafin_id“).
    static func vorschlagMitGuete(fuer spalte: String) -> (feld: Zielfeld, guete: Int)? {
        if istGeheim(spalte) { return (.ignorieren, 3) }
        let ganz = Text.schluessel(spalte)
        if let treffer = suche(ganz) { return (treffer, 3) }
        // verschachtelt ("insurer.name", "premium.amount", "contract.number")
        let segmente = spalte.split(whereSeparator: { $0 == "." || $0 == "/" }).map { Text.schluessel(String($0)) }
        if segmente.count > 1, let letztes = segmente.last {
            let generisch = ["name", "value", "id", "number", "nr", "type", "bezeichnung", "text", "amount", "wert"]
            if !generisch.contains(letztes), let treffer = suche(letztes) { return (treffer, 2) }
            if let treffer = suche(segmente.suffix(2).joined()) { return (treffer, 2) }
            if generisch.contains(letztes), let treffer = suche(segmente[segmente.count - 2]) { return (treffer, 2) }
            if let treffer = suche(segmente[segmente.count - 2]) { return (treffer, 1) }
        }
        return nil
    }

    private static func suche(_ k: String) -> Zielfeld? {
        for feld in Zielfeld.allCases {
            if let liste = synonyme[feld], liste.contains(where: { Text.schluessel($0) == k }) { return feld }
        }
        return nil
    }
}

/// Zuordnung Quellspalte → Zielfeld. Nicht zugeordnete Spalten wandern in die Notizen.
public struct Feldzuordnung: Codable, Sendable, Equatable {
    public var zuordnung: [String: Zielfeld]

    public init(zuordnung: [String: Zielfeld] = [:]) {
        self.zuordnung = zuordnung
    }

    /// Automatische Zuordnung; jedes Zielfeld (außer Notizen/Ignorieren) höchstens einmal.
    public static func automatisch(fuer spalten: [String]) -> Feldzuordnung {
        var ergebnis: [String: Zielfeld] = [:]
        var belegt: Set<Zielfeld> = []
        let vorschlaege = spalten.enumerated().compactMap { (i, spalte) -> (Int, String, Zielfeld, Int)? in
            Zielfeld.vorschlagMitGuete(fuer: spalte).map { (i, spalte, $0.feld, $0.guete) }
        }
        // stärkste Treffer zuerst, bei Gleichstand Spaltenreihenfolge
        for (_, spalte, ziel, _) in vorschlaege.sorted(by: { ($1.3, $0.0) < ($0.3, $1.0) }) {
            if ziel == .notizen || ziel == .ignorieren {
                ergebnis[spalte] = ziel
            } else if !belegt.contains(ziel) {
                // schwacher Treffer nur, wenn kein Geschwisterfeld schon stark zugeordnet ist
                ergebnis[spalte] = ziel
                belegt.insert(ziel)
            }
        }
        return Feldzuordnung(zuordnung: ergebnis)
    }

    public func ziel(fuer spalte: String) -> Zielfeld {
        if Zielfeld.istGeheim(spalte) { return .ignorieren }
        return zuordnung[spalte] ?? .notizen
    }

    /// Baut einen Vertrag aus einem Datensatz. Unbekannte oder nicht lesbare Werte landen in den Notizen.
    public func vertrag(aus datensatz: [(String, String)], quelle: String, deutscheZahlen: Bool) -> (VertragsDaten, [String]) {
        var v = VertragsDaten()
        var warnungen: [String] = []
        var statusGesetzt = false
        var extraNotizen: [String] = []

        func merken(_ spalte: String, _ wert: String) {
            extraNotizen.append("\(spalte): \(wert)")
        }

        for (spalte, rohwert) in datensatz {
            let wert = rohwert.trimmingCharacters(in: .whitespacesAndNewlines)
            let ziel = ziel(fuer: spalte)
            if wert.isEmpty || ziel == .ignorieren { continue }
            switch ziel {
            case .versicherer: v.versicherer = wert
            case .sparte: v.sparte = wert
            case .vertragsnummer: v.vertragsnummer = wert
            case .tarif: v.tarif = wert
            case .kuendigungsfrist: v.kuendigungsfrist = wert
            case .steuerlicheEinordnung: v.steuerlicheEinordnung = wert
            case .beginn, .ablauf:
                if let d = Datum.lesen(wert) {
                    if ziel == .beginn { v.beginn = d } else { v.ablauf = d }
                } else {
                    warnungen.append("\(spalte): Datum „\(wert)“ nicht lesbar")
                    merken(spalte, wert)
                }
            case .beitrag:
                if let z = Zahl.lesen(wert, deutsch: deutscheZahlen) { v.beitrag = abs(z) }
                else { warnungen.append("\(spalte): Betrag „\(wert)“ nicht lesbar"); merken(spalte, wert) }
            case .dynamikProzent:
                if let z = Zahl.lesen(wert, deutsch: deutscheZahlen) {
                    // 0,03 als 3 % deuten
                    v.dynamikProzent = (z > 0 && z < 1 && !wert.contains("%")) ? z * 100 : z
                } else { merken(spalte, wert) }
            case .zahlweise:
                if let z = Zahlweise.erkennen(wert) { v.zahlweise = z }
                else { warnungen.append("\(spalte): Zahlweise „\(wert)“ unbekannt"); merken(spalte, wert) }
            case .status:
                if let s = VertragsStatus.erkennen(wert) { v.status = s; statusGesetzt = true }
                else { merken(spalte, wert) }
            case .betreuer:
                if let b = Betreuer.erkennen(wert) { v.betreuer = b } else { merken(spalte, wert) }
            case .notizen:
                // echte Notizspalte ohne Präfix, andere Spalten mit Namen
                if Zielfeld.vorschlag(fuer: spalte) == .notizen { v.notizAnhaengen(wert) } else { merken(spalte, wert) }
            case .ignorieren:
                break
            }
        }
        for n in extraNotizen { v.notizAnhaengen(n) }
        if !statusGesetzt && (v.vertragsnummer.isEmpty || v.versicherer.isEmpty) {
            v.status = .pruefen
        }
        if v.vertragsnummer.isEmpty { warnungen.append("Keine Vertragsnummer (\(quelle))") }
        return (v, warnungen)
    }
}
