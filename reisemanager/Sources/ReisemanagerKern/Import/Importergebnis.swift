import Foundation

/// Bilanz eines Imports. Unlesbare Zeilen werden gemeldet, nie geraten.
public struct Importergebnis: Equatable, Sendable {
    public var neu = 0
    public var bekannt = 0
    public var zusammengefuehrt = 0
    public var fehler: [String] = []
    public init() {}

    public var zusammenfassung: String {
        var teile = ["\(neu) neu", "\(bekannt) bekannt"]
        if zusammengefuehrt > 0 { teile.append("\(zusammengefuehrt) zusammengeführt") }
        if !fehler.isEmpty { teile.append("\(fehler.count) Fehler") }
        return teile.joined(separator: ", ")
    }
}

public enum Importfehler: Error, CustomStringConvertible {
    case spaltenFehlen(datei: String, spalten: [String])
    case nichtLesbar(datei: String, grund: String)

    public var description: String {
        switch self {
        case .spaltenFehlen(let datei, let spalten):
            return "\(datei): Spalten fehlen: \(spalten.joined(separator: ", "))"
        case .nichtLesbar(let datei, let grund):
            return "\(datei): \(grund)"
        }
    }
}

enum Textnorm {
    /// Großbuchstaben ohne Akzente, nur Buchstaben und Ziffern. Für Händlervergleiche.
    static func kern(_ text: String) -> String {
        let gefaltet = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        return String(gefaltet.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func leerAlsNil(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    static func dateiLesen(_ pfad: String) throws -> String {
        let daten = try Data(contentsOf: URL(fileURLWithPath: pfad))
        if let text = String(data: daten, encoding: .utf8) { return text }
        if let text = String(data: daten, encoding: .isoLatin1) { return text }
        throw Importfehler.nichtLesbar(datei: pfad, grund: "Zeichensatz unbekannt")
    }

    static func pruefeSpalten(_ kopf: [String], noetig: [String], datei: String) throws {
        let fehlend = noetig.filter { !kopf.contains($0) }
        if !fehlend.isEmpty { throw Importfehler.spaltenFehlen(datei: datei, spalten: fehlend) }
    }
}
