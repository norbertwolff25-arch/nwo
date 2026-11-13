import Foundation

/// Geldbeträge werden als ganze Cent geführt, nie als Gleitkommazahl.
public enum Geld {
    /// Liest "1.234,56", "-12,50", "12.5", "1,267.13" oder "55". Unlesbares ergibt nil, nie 0.
    public static func cent(aus text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: "\u{00A0}", with: "")
        s = s.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "EUR", with: "")
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var negativ = false
        if s.hasPrefix("-") || s.hasPrefix("−") { negativ = true; s.removeFirst() }
        else if s.hasPrefix("+") { s.removeFirst() }

        // Das letzte Trennzeichen entscheidet: Folgen ihm 1–2 Ziffern, ist es das Dezimalzeichen.
        var ganz = s
        var bruch = ""
        if let letztes = s.lastIndex(where: { $0 == "," || $0 == "." }) {
            let danach = s[s.index(after: letztes)...]
            let davorHatTrenner = s[..<letztes].contains(where: { $0 == "," || $0 == "." })
            if danach.count <= 2 || (s[letztes] == "," && !davorHatTrenner && danach.count != 3) {
                ganz = String(s[..<letztes])
                bruch = String(danach)
            }
        }
        ganz = ganz.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        guard !ganz.isEmpty || !bruch.isEmpty,
              ganz.allSatisfy(\.isNumber), bruch.allSatisfy(\.isNumber), bruch.count <= 2 else { return nil }
        while bruch.count < 2 { bruch += "0" }
        guard let g = Int(ganz.isEmpty ? "0" : ganz), let b = Int(bruch) else { return nil }
        let wert = g * 100 + b
        return negativ ? -wert : wert
    }

    /// "1.234,56" in deutscher Schreibweise.
    public static func text(cent: Int) -> String {
        let betrag = abs(cent)
        var ganz = String(betrag / 100)
        var gruppen: [String] = []
        while ganz.count > 3 {
            gruppen.insert(String(ganz.suffix(3)), at: 0)
            ganz = String(ganz.dropLast(3))
        }
        gruppen.insert(ganz, at: 0)
        return (cent < 0 ? "-" : "") + gruppen.joined(separator: ".") + "," + String(format: "%02d", betrag % 100)
    }
}
