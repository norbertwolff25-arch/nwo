import Foundation

/// Concur-Abrechnungstitel: höchstens 32 Zeichen, Muster `<Anlass> <Ort> TT.-TT.MM.JJ`.
public enum Abrechnungstitel {
    public static let maxLaenge = 32

    public struct ZuLang: Error, Equatable {
        public let titel: String
        public var laenge: Int { titel.count }
    }

    public static func istGueltig(_ titel: String) -> Bool {
        !titel.isEmpty && titel.count <= maxLaenge
    }

    /// Zeitraum im Titel: „25.-28.01.26“, über Monatsgrenze „29.09.-02.10.26“, Tagesreise „22.10.26“.
    public static func zeitraum(beginn: Tag, ende: Tag) -> String {
        let jj = String(format: "%02d", ende.jahr % 100)
        let bis = String(format: "%02d.%02d.", ende.tag, ende.monat) + jj
        if beginn == ende { return bis }
        if beginn.jahr != ende.jahr {
            return String(format: "%02d.%02d.%02d-", beginn.tag, beginn.monat, beginn.jahr % 100) + bis
        }
        if beginn.monat != ende.monat {
            return String(format: "%02d.%02d.-", beginn.tag, beginn.monat) + bis
        }
        return String(format: "%02d.-", beginn.tag) + bis
    }

    /// Bildet den Titel. Ist er zu lang, wird nicht gekürzt, sondern gemeldet: Den kürzeren Anlass wählt der Nutzer.
    public static func bilden(anlass: String, ort: String?, beginn: Tag, ende: Tag) -> Result<String, ZuLang> {
        var teile = [anlass.trimmingCharacters(in: .whitespaces)]
        if let ort = ort?.trimmingCharacters(in: .whitespaces), !ort.isEmpty, !teile[0].contains(ort) { teile.append(ort) }
        teile.append(zeitraum(beginn: beginn, ende: ende))
        let titel = teile.joined(separator: " ")
        return titel.count <= maxLaenge ? .success(titel) : .failure(ZuLang(titel: titel))
    }
}
