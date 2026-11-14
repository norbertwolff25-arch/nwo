import Foundation

/// Textnormalisierung für Vergleiche und Feldnamen.
public enum Textnorm {
    /// Kleinbuchstaben, Umlaute gefaltet (ä→ae, ß→ss), nur Buchstaben und Ziffern.
    public static func schluessel(_ s: String) -> String {
        var ergebnis = ""
        for zeichen in s.lowercased() {
            switch zeichen {
            case "ä": ergebnis += "ae"
            case "ö": ergebnis += "oe"
            case "ü": ergebnis += "ue"
            case "ß": ergebnis += "ss"
            default:
                if zeichen.isLetter || zeichen.isNumber {
                    // Akzente entfernen (é → e)
                    let gefaltet = String(zeichen).folding(options: .diacriticInsensitive, locale: nil)
                    ergebnis += gefaltet
                }
            }
        }
        return ergebnis
    }

    /// Vertragsnummer ohne Leer- und Trennzeichen, in Großbuchstaben.
    public static func vertragsnummer(_ s: String) -> String {
        String(s.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    private static let rechtsformen: Set<String> = [
        "ag", "se", "vvag", "gmbh", "kgaa", "aktiengesellschaft", "versicherungsverein", "auf", "gegenseitigkeit",
        "a", "g", "co", "kg", "der", "die", "das", "und"
    ]

    /// Versicherer ohne Rechtsform, für Dublettenerkennung.
    public static func versichererSchluessel(_ s: String) -> String {
        let woerter = s.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "/" || $0 == "&" })
            .map { schluessel(String($0)) }
            .filter { !$0.isEmpty && !rechtsformen.contains($0) }
        return woerter.joined(separator: " ")
    }

    public static func getrimmt(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Zahlen in deutscher und englischer Schreibweise.
public enum Zahl {
    /// Liest „1.234,56 €“, „-12,30“, „12.50“, „1234“, „3 %“.
    /// - Parameter deutsch: Bei mehrdeutigem „1.234“ als Tausenderpunkt lesen.
    public static func lesen(_ roh: String, deutsch: Bool = true) -> Decimal? {
        var s = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        var negativ = false
        // Buchhaltungsschreibweise "123,45-" oder "(123,45)"
        if s.hasSuffix("-") { negativ = true; s.removeLast() }
        if s.hasPrefix("(") && s.hasSuffix(")") { negativ = true; s = String(s.dropFirst().dropLast()) }
        s = s.replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
        s = String(s.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" || $0 == "+" })
        if s.hasPrefix("-") { negativ.toggle(); s.removeFirst() }
        if s.hasPrefix("+") { s.removeFirst() }
        if s.isEmpty || s.contains("-") || s.contains("+") { return nil }

        let letztesKomma = s.lastIndex(of: ",")
        let letzterPunkt = s.lastIndex(of: ".")
        let normal: String
        switch (letztesKomma, letzterPunkt) {
        case (nil, nil):
            normal = s
        case (.some, nil):
            // nur Komma: Dezimalkomma (mehrere Kommas: Tausender englisch)
            if s.filter({ $0 == "," }).count > 1 {
                normal = s.replacingOccurrences(of: ",", with: "")
            } else {
                normal = s.replacingOccurrences(of: ",", with: ".")
            }
        case (nil, .some):
            let punkte = s.filter { $0 == "." }.count
            if punkte > 1 {
                normal = s.replacingOccurrences(of: ".", with: "")
            } else if deutsch, istTausendergruppe(s, trenner: ".") {
                normal = s.replacingOccurrences(of: ".", with: "")
            } else {
                normal = s
            }
        case let (.some(k), .some(p)):
            if k > p { // 1.234,56
                normal = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else { // 1,234.56
                normal = s.replacingOccurrences(of: ",", with: "")
            }
        }
        guard let wert = Decimal(string: normal, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negativ ? -wert : wert
    }

    private static func istTausendergruppe(_ s: String, trenner: Character) -> Bool {
        let teile = s.split(separator: trenner, omittingEmptySubsequences: false)
        guard teile.count == 2, let erster = teile.first, let letzter = teile.last else { return false }
        return !erster.isEmpty && erster.count <= 3 && letzter.count == 3
    }

    public static func runden(_ wert: Decimal, stellen: Int = 2) -> Decimal {
        var eingabe = wert
        var ergebnis = Decimal()
        NSDecimalRound(&ergebnis, &eingabe, stellen, .plain)
        return ergebnis
    }

    /// „1234,50“ (ohne Tausenderpunkt) für CSV.
    public static func deutsch(_ wert: Decimal, stellen: Int = 2) -> String {
        let gerundet = runden(wert, stellen: stellen)
        var text = NSDecimalNumber(decimal: gerundet).stringValue // "1234.5"
        if stellen > 0 {
            var teile = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if teile.count == 1 { teile.append("") }
            while teile[1].count < stellen { teile[1] += "0" }
            text = teile[0] + "," + teile[1]
        }
        return text
    }

    /// „1.234,50 €“ für Anzeige ohne Formatter (plattformunabhängig).
    public static func euro(_ wert: Decimal) -> String {
        let text = deutsch(wert)
        let negativ = text.hasPrefix("-")
        let ohneVorzeichen = negativ ? String(text.dropFirst()) : text
        let teile = ohneVorzeichen.split(separator: ",").map(String.init)
        var ganz = Array(teile[0])
        var gruppiert = ""
        while ganz.count > 3 {
            gruppiert = "." + String(ganz.suffix(3)) + gruppiert
            ganz.removeLast(3)
        }
        gruppiert = String(ganz) + gruppiert
        return (negativ ? "-" : "") + gruppiert + "," + (teile.count > 1 ? teile[1] : "00") + " €"
    }
}

/// Kalendertage in Europe/Berlin. Ein Datum wird immer als 12:00 Uhr Ortszeit abgelegt,
/// damit Sommerzeit und Zeitzonen den Tag nicht verschieben.
public enum Datum {
    public static let kalender: Calendar = {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        k.locale = Locale(identifier: "de_DE")
        return k
    }()

    public static func tag(_ jahr: Int, _ monat: Int, _ tag: Int) -> Date? {
        guard (1...12).contains(monat), (1...31).contains(tag), jahr > 1800 else { return nil }
        var k = DateComponents()
        k.year = jahr; k.month = monat; k.day = tag; k.hour = 12
        guard let d = kalender.date(from: k) else { return nil }
        // ungültige Tage wie 31.02. ablehnen
        let pruefung = kalender.dateComponents([.year, .month, .day], from: d)
        guard pruefung.year == jahr, pruefung.month == monat, pruefung.day == tag else { return nil }
        return d
    }

    /// Liest „31.12.2026“, „1.6.28“, „2026-12-31“, „2026-12-31T00:00:00Z“, „06/2028“, „12.2026“, „2026“.
    public static func lesen(_ roh: String) -> Date? {
        let s = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let zahlen = s.split(whereSeparator: { !$0.isNumber }).map(String.init)
        guard !zahlen.isEmpty else { return nil }

        func jahr(_ t: String) -> Int? {
            guard let j = Int(t) else { return nil }
            if t.count == 4 { return j }
            if t.count == 2 { return j < 70 ? 2000 + j : 1900 + j }
            return nil
        }

        // ISO: 2026-12-31 (auch mit Uhrzeit), 2026.12.31
        if zahlen[0].count == 4, zahlen.count >= 3, let j = Int(zahlen[0]), let m = Int(zahlen[1]), let t = Int(zahlen[2]) {
            return tag(j, m, t) // 2026.12.31
        }
        if zahlen[0].count == 8, zahlen.count == 1, let j = Int(zahlen[0].prefix(4)),
           let m = Int(zahlen[0].dropFirst(4).prefix(2)), let t = Int(zahlen[0].suffix(2)) {
            return tag(j, m, t) // 20261231 (GDV-Format JJJJMMTT)
        }
        if zahlen.count >= 3, let t = Int(zahlen[0]), let m = Int(zahlen[1]), let j = jahr(zahlen[2]) {
            return tag(j, m, t) // 31.12.2026
        }
        if zahlen.count == 2, let m = Int(zahlen[0]), let j = jahr(zahlen[1]), zahlen[1].count == 4 {
            return tag(j, m, 1) // 06/2028
        }
        if zahlen.count == 2, zahlen[0].count == 4, let j = Int(zahlen[0]), let m = Int(zahlen[1]) {
            return tag(j, m, 1) // 2028-06
        }
        if zahlen.count == 1, zahlen[0].count == 4, let j = Int(zahlen[0]) {
            return tag(j, 1, 1)
        }
        return nil
    }

    public static func deutsch(_ d: Date?) -> String {
        guard let d else { return "" }
        let k = kalender.dateComponents([.year, .month, .day], from: d)
        return String(format: "%02d.%02d.%04d", k.day ?? 0, k.month ?? 0, k.year ?? 0)
    }

    public static func iso(_ d: Date?) -> String {
        guard let d else { return "" }
        let k = kalender.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", k.year ?? 0, k.month ?? 0, k.day ?? 0)
    }

    public static func jahr(_ d: Date) -> Int { kalender.component(.year, from: d) }

    public static func plus(monate: Int = 0, tage: Int = 0, zu d: Date) -> Date {
        var k = DateComponents()
        k.month = monate
        k.day = tage
        return kalender.date(byAdding: k, to: d) ?? d
    }

    public static func tageZwischen(_ von: Date, _ bis: Date) -> Int {
        let a = kalender.startOfDay(for: von)
        let b = kalender.startOfDay(for: bis)
        return kalender.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
