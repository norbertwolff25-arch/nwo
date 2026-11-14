import Foundation

public enum CSVFehler: Error, Equatable, LocalizedError {
    case keineTextdatei
    case leer

    public var errorDescription: String? {
        switch self {
        case .keineTextdatei: "Die Datei ist keine lesbare Textdatei (erwartet: UTF-8 oder Windows-1252)."
        case .leer: "Die Datei enthält keine Datenzeilen."
        }
    }
}

/// Eine eingelesene CSV-Tabelle mit Kopfzeile.
public struct CSVTabelle: Sendable, Equatable {
    public var kopf: [String]
    public var zeilen: [[String]]

    /// Zeilen als Wörterbuch Spaltenname → Wert (fehlende Zellen = "").
    public var datensaetze: [[String: String]] {
        zeilen.map { zeile in
            var d: [String: String] = [:]
            for (i, name) in kopf.enumerated() where !name.isEmpty {
                d[name] = i < zeile.count ? zeile[i] : ""
            }
            return d
        }
    }
}

public enum CSV {
    /// Dekodiert Bytes: UTF-8 (mit/ohne BOM), sonst Windows-1252 (Excel-Export).
    public static func text(aus daten: Data) throws -> String {
        var d = daten
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        if let s = String(data: d, encoding: .utf8) { return s }
        if let s = String(data: d, encoding: .windowsCP1252) { return s }
        throw CSVFehler.keineTextdatei
    }

    /// Ermittelt das Trennzeichen aus der ersten Zeile (Semikolon bevorzugt).
    public static func trennzeichen(fuer text: String) -> Character {
        let erste = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let kandidaten: [Character] = [";", "\t", ",", "|"]
        return kandidaten.max(by: { a, b in erste.filter { $0 == a }.count < erste.filter { $0 == b }.count }) ?? ";"
    }

    /// RFC-4180-Leser mit wählbarem Trennzeichen, Anführungszeichen, "" als Escape und CRLF.
    public static func zerlegen(_ text: String, trenner: Character? = nil) -> [[String]] {
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        let sep = trenner ?? trennzeichen(fuer: t)
        var zeilen: [[String]] = []
        var zeile: [String] = []
        var feld = ""
        var inAnfuehrung = false
        var iter = Array(t.unicodeScalars).makeIterator()
        var vorschau: Unicode.Scalar? = nil
        let sepScalar = sep.unicodeScalars.first!

        func naechstes() -> Unicode.Scalar? {
            if let v = vorschau { vorschau = nil; return v }
            return iter.next()
        }

        while let z = naechstes() {
            if inAnfuehrung {
                if z == "\"" {
                    let n = naechstes()
                    if n == "\"" { feld.unicodeScalars.append("\"") }
                    else { inAnfuehrung = false; vorschau = n }
                } else {
                    feld.unicodeScalars.append(z)
                }
                continue
            }
            switch z {
            case "\"" where feld.isEmpty:
                inAnfuehrung = true
            case sepScalar:
                zeile.append(feld); feld = ""
            case "\r":
                let n = naechstes()
                if n != "\n" { vorschau = n }
                zeile.append(feld); feld = ""
                zeilen.append(zeile); zeile = []
            case "\n":
                zeile.append(feld); feld = ""
                zeilen.append(zeile); zeile = []
            default:
                feld.unicodeScalars.append(z)
            }
        }
        if !feld.isEmpty || !zeile.isEmpty {
            zeile.append(feld)
            zeilen.append(zeile)
        }
        // Leerzeilen entfernen
        return zeilen.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    public static func tabelle(aus daten: Data) throws -> CSVTabelle {
        let text = try text(aus: daten)
        return try tabelle(aus: text)
    }

    public static func tabelle(aus text: String) throws -> CSVTabelle {
        let zeilen = zerlegen(text)
        guard let kopf = zeilen.first else { throw CSVFehler.leer }
        return CSVTabelle(
            kopf: kopf.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            zeilen: Array(zeilen.dropFirst())
        )
    }

    // MARK: Schreiben

    public static func feld(_ s: String, trenner: Character = ";") -> String {
        if s.contains(trenner) || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// Schreibt eine Tabelle als UTF-8 mit BOM, Semikolon und CRLF (Excel-tauglich).
    public static func schreiben(kopf: [String], zeilen: [[String]], trenner: Character = ";") -> Data {
        var text = "\u{FEFF}"
        let alle = [kopf] + zeilen
        for z in alle {
            text += z.map { feld($0, trenner: trenner) }.joined(separator: String(trenner)) + "\r\n"
        }
        return Data(text.utf8)
    }
}
