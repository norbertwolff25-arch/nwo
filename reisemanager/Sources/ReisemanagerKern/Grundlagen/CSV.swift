import Foundation

/// CSV-Leser nach RFC 4180: Anführungszeichen, doppelte Anführungszeichen, Zeilenumbrüche in Feldern.
public enum CSV {
    public static func zeilen(_ text: String, trenner: Character) -> [[String]] {
        var ergebnis: [[String]] = []
        var zeile: [String] = []
        var feld = ""
        var inAnfuehrung = false
        var feldBegonnen = false
        var zeichen = Array(text)
        if zeichen.first == "\u{FEFF}" { zeichen.removeFirst() }
        var i = 0
        func zeileBeenden() {
            zeile.append(feld)
            if !(zeile.count == 1 && zeile[0].isEmpty) { ergebnis.append(zeile) }
            zeile = []
            feld = ""
            feldBegonnen = false
        }
        while i < zeichen.count {
            let z = zeichen[i]
            if inAnfuehrung {
                if z == "\"" {
                    if i + 1 < zeichen.count, zeichen[i + 1] == "\"" { feld.append("\""); i += 1 }
                    else { inAnfuehrung = false }
                } else {
                    feld.append(z)
                }
            } else if z == "\"" && !feldBegonnen {
                inAnfuehrung = true
                feldBegonnen = true
            } else if z == trenner {
                zeile.append(feld)
                feld = ""
                feldBegonnen = false
            } else if z == "\n" || z == "\r\n" {
                zeileBeenden()
            } else if z == "\r" {
                zeileBeenden()
            } else {
                feld.append(z)
                feldBegonnen = true
            }
            i += 1
        }
        if feldBegonnen || !feld.isEmpty || !zeile.isEmpty { zeileBeenden() }
        return ergebnis
    }

    /// Zeilen als Wörterbuch Kopfspalte → Wert. Kopfspalten werden getrimmt.
    public static func datensaetze(_ text: String, trenner: Character) -> (kopf: [String], saetze: [[String: String]]) {
        let alle = zeilen(text, trenner: trenner)
        guard let erste = alle.first else { return ([], []) }
        let kopf = erste.map { $0.trimmingCharacters(in: .whitespaces) }
        let saetze = alle.dropFirst().map { werte -> [String: String] in
            var satz: [String: String] = [:]
            for (index, name) in kopf.enumerated() where index < werte.count {
                satz[name] = werte[index]
            }
            return satz
        }
        return (kopf, saetze)
    }
}
