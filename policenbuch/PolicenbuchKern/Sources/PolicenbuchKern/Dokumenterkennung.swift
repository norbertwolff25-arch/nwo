import Foundation

/// Auswertung des per OCR oder PDFKit gewonnenen Texts eines Dokuments.
public struct Dokumentbefund: Sendable, Equatable {
    /// Zugeordneter Vertrag aus dem Bestand (eindeutiger Treffer).
    public var vertragID: UUID?
    /// Im Text gefundene Nummern hinter „Versicherungsschein-Nr.“ o. Ä.
    public var kandidaten: [String]
    public var typ: DokumentTyp
    public var datum: Date?
}

public enum Dokumenterkennung {
    /// Begriffe, hinter denen eine Vertragsnummer steht.
    static let nummernMarker = [
        "versicherungsscheinnummer", "versicherungsschein-nr", "versicherungsschein nr", "versicherungsscheinnr",
        "vertragsnummer", "vertrags-nr", "vertragsnr", "vertrag nr", "vertrag-nr",
        "policennummer", "policen-nr", "policennr", "police nr", "police-nr", "polizzennummer",
        "vers.-nr", "vers-nr", "vers. nr", "vsnr", "vs-nr", "versicherungsnummer", "versicherungs-nr", "mitgliedsnummer"
    ]

    /// Findet Kandidaten für Vertragsnummern hinter bekannten Markern.
    public static func kandidaten(in text: String) -> [String] {
        var ergebnis: [String] = []
        let klein = text.lowercased()
        for marker in nummernMarker {
            var suchbereich = klein.startIndex..<klein.endIndex
            while let fund = klein.range(of: marker, range: suchbereich) {
                suchbereich = fund.upperBound..<klein.endIndex
                // Original-Text ab Markerende (gleiche Indizes, da lowercased bei Umlauten länger sein kann → per Offset)
                let offset = klein.distance(from: klein.startIndex, to: fund.upperBound)
                guard let start = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex) else { continue }
                var rest = text[start...].drop(while: { ".:# \t".contains($0) || $0 == "\u{00A0}" })
                if rest.lowercased().hasPrefix("nummer") { rest = rest.dropFirst(6).drop(while: { ".:# \t".contains($0) }) }
                if rest.lowercased().hasPrefix("nr") { rest = rest.dropFirst(2).drop(while: { ".:# \t".contains($0) }) }
                var nummer = ""
                let zeichen = Array(rest)
                for (i, c) in zeichen.enumerated() {
                    if c.isNewline { break }
                    if c.isLetter || c.isNumber || "-./".contains(c) { nummer.append(c); continue }
                    // Leerzeichen innerhalb der Nummer („LV 123 456 78“), wenn eine Ziffer folgt
                    if c == " ", !nummer.isEmpty, i + 1 < zeichen.count, zeichen[i + 1].isNumber { nummer.append(c); continue }
                    break
                }
                nummer = nummer.trimmingCharacters(in: CharacterSet(charactersIn: " -./"))
                // Ein angehängtes Wort („12345 vom“) abschneiden
                if let letzteLuecke = nummer.lastIndex(of: " "), nummer[nummer.index(after: letzteLuecke)...].allSatisfy(\.isLetter) {
                    nummer = String(nummer[..<letzteLuecke])
                }
                let n = Text.vertragsnummer(nummer)
                if n.count >= 5, n.contains(where: \.isNumber), !ergebnis.contains(where: { Text.vertragsnummer($0) == n }) {
                    ergebnis.append(nummer)
                }
            }
        }
        return ergebnis
    }

    public static func typ(in text: String) -> DokumentTyp {
        let t = Text.schluessel(text.prefix(3000).description)
        if t.contains("jahresbescheinigung") || t.contains("bescheinigungfuerdasfinanzamt") || t.contains("steuerbescheinigung")
            || t.contains("vorlagebeimfinanzamt") || t.contains("beitragsbescheinigung") {
            return .jahresbescheinigung
        }
        if t.contains("nachtrag") || t.contains("aenderungsmitteilung") || t.contains("vertragsaenderung") {
            return .nachtrag
        }
        if t.contains("beitragsrechnung") || t.contains("beitragsmitteilung") || t.contains("rechnung")
            || t.contains("beitragsanpassung") || t.contains("zahlungsaufforderung") {
            return .beitragsrechnung
        }
        if t.contains("versicherungsschein") || t.contains("police") || t.contains("policierung") {
            return .police
        }
        return .sonstiges
    }

    /// Erstes plausibles Datum im Text (bevorzugt nach „Datum“, „vom“ oder Ortsangabe „, den“).
    public static func datum(in text: String) -> Date? {
        let muster = #"(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: muster) else { return nil }
        let ns = text as NSString
        let treffer = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var bevorzugt: Date? = nil
        var erstes: Date? = nil
        for m in treffer {
            guard let t = Int(ns.substring(with: m.range(at: 1))), let mo = Int(ns.substring(with: m.range(at: 2))),
                  let j = Int(ns.substring(with: m.range(at: 3))), let d = Datum.tag(j, mo, t) else { continue }
            if erstes == nil { erstes = d }
            let davorStart = max(0, m.range.location - 12)
            let davor = ns.substring(with: NSRange(location: davorStart, length: m.range.location - davorStart)).lowercased()
            if bevorzugt == nil, davor.contains("datum") || davor.contains("vom") || davor.contains(", den") {
                bevorzugt = d
            }
        }
        return bevorzugt ?? erstes
    }

    /// Ordnet den Text einem Vertrag zu: zuerst bekannte Nummern irgendwo im Text, dann Kandidaten.
    public static func auswerten(text: String, vertraege: [VertragsDaten]) -> Dokumentbefund {
        let kandidaten = kandidaten(in: text)
        var id = ZahlungsZuordnung.vertrag(fuer: text, in: vertraege)
        if id == nil {
            for k in kandidaten {
                let n = Text.vertragsnummer(k)
                let passende = vertraege.filter { Text.vertragsnummer($0.vertragsnummer) == n }
                if passende.count == 1 { id = passende[0].id; break }
            }
        }
        return Dokumentbefund(vertragID: id, kandidaten: kandidaten, typ: typ(in: text), datum: datum(in: text))
    }
}
