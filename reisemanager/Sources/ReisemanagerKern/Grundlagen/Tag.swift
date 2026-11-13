import Foundation

/// Kalendertag ohne Uhrzeit und Zeitzone. Gespeichert als "JJJJ-MM-TT".
public struct Tag: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let jahr: Int
    public let monat: Int
    public let tag: Int

    public init?(jahr: Int, monat: Int, tag: Int) {
        guard (1...12).contains(monat), tag >= 1, tag <= Tag.tageImMonat(jahr: jahr, monat: monat) else { return nil }
        self.jahr = jahr
        self.monat = monat
        self.tag = tag
    }

    /// Liest "JJJJ-MM-TT".
    public init?(iso: String) {
        let teile = iso.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard teile.count == 3, teile[0].count == 4,
              let j = Int(teile[0]), let m = Int(teile[1]), let t = Int(teile[2]) else { return nil }
        self.init(jahr: j, monat: m, tag: t)
    }

    /// Liest "TT/MM/JJJJ" (Amex) oder "TT.MM.JJJJ" (PayPal, deutsch).
    public init?(tagMonatJahr text: String) {
        let teile = text.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "/" || $0 == "." })
        guard teile.count == 3, teile[2].count == 4,
              let t = Int(teile[0]), let m = Int(teile[1]), let j = Int(teile[2]) else { return nil }
        self.init(jahr: j, monat: m, tag: t)
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", jahr, monat, tag)
    }

    public var description: String { iso }

    static func tageImMonat(jahr: Int, monat: Int) -> Int {
        switch monat {
        case 4, 6, 9, 11: return 30
        case 2: return (jahr % 4 == 0 && jahr % 100 != 0) || jahr % 400 == 0 ? 29 : 28
        default: return 31
        }
    }

    /// Fortlaufende Tagesnummer, nur für Abstände.
    var tagesnummer: Int {
        let a = (14 - monat) / 12
        let y = jahr + 4800 - a
        let m = monat + 12 * a - 3
        return tag + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public func abstandInTagen(zu anderer: Tag) -> Int {
        anderer.tagesnummer - tagesnummer
    }

    public static func < (links: Tag, rechts: Tag) -> Bool {
        (links.jahr, links.monat, links.tag) < (rechts.jahr, rechts.monat, rechts.tag)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let wert = Tag(iso: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Kein Datum: \(text)"))
        }
        self = wert
    }

    public func encode(to encoder: Encoder) throws {
        var behaelter = encoder.singleValueContainer()
        try behaelter.encode(iso)
    }
}
