import Foundation
import GRDB

/// Eine Zahlung aus NWO-Pay, Amex oder PayPal. Betrag aus Sicht des Kontos: negativ = Abgang.
public struct Zahlung: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "zahlung"
    public var id: String
    public var quelle: Zahlungsquelle
    public var konto: String
    public var datum: Tag
    /// Euro-Betrag in Cent. nil = Euro-Betrag fehlt noch (Fremdwährung).
    public var betragCent: Int?
    public var haendler: String
    public var zweck: String?
    public var fremdbetragCent: Int?
    public var fremdwaehrung: String?
    /// Nur die letzten vier Ziffern, nie die ganze Kartennummer.
    public var karteLetzteVier: String?
    /// Kennung der Gegenseite, z. B. "PP-<Transaktionscode>".
    public var externId: String?
    public var kategorie: String?
    /// false = Gegenbuchung, zählt in keiner Summe.
    public var zaehlt: Bool
    public var gepaartMitId: String?
    public var paarSicherheit: Sicherheit?
    public var herkunftsdatei: String
    public var herkunftsRef: String?
}

/// Jede Fundstelle einer Zahlung. Eine PayPal-Zahlung mit Amex-Finanzierung hat mehrere.
public struct ZahlungHerkunft: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "zahlungHerkunft"
    public var id: Int64?
    public var zahlungId: String
    public var quelle: Zahlungsquelle
    public var datei: String
    public var ref: String?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Dienstreise (D..) oder Privatreise (P..). Privatreisen gehen in keine Summe ein.
public struct Reise: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "reise"
    public var id: String
    public var art: Reiseart
    public var typ: String?
    public var anlass: String
    public var ort: String?
    /// Einsatz beim Stammkunden. Wird über Regeln gesetzt, Ausnahmen markiert der Nutzer.
    public var istStammeinsatz: Bool
    public var beginn: Tag?
    public var beginnZeit: String?
    public var beginnQuelle: String?
    public var beginnSicherheit: Sicherheit?
    public var ende: Tag?
    public var endeZeit: String?
    public var endeQuelle: String?
    public var endeSicherheit: Sicherheit?
    public var verkehrsmittel: String?
    public var unterkunft: String?
    public var hinweis: String?
    public var status: Reisestatus
    public var concurNr: String?
    public var concurTitel: String?
}

/// Sachkostenabrechnung ohne Tagespauschalen, eine je Sachkostenart.
public struct Sachkostenabrechnung: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "sachkostenabrechnung"
    public var id: String
    public var titel: String
    public var hinweis: String?
    public var status: Reisestatus
    public var concurNr: String?
    public var concurTitel: String?
}

/// Abschnitt des Reiseverlaufs: Vorlauf, Hauptlauf, Nachlauf. Start und Ziel ist die Privatadresse.
public struct Reiseabschnitt: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "reiseabschnitt"
    public var id: Int64?
    public var reiseId: String
    public var reihenfolge: Int
    public var art: String
    public var von: String?
    public var nach: String?
    public var abfahrt: String?
    public var ankunft: String?
    public var verkehrsmittel: String?
    public var quelle: String?
    public var sicherheit: Sicherheit?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Kostenposition einer Reise oder Sachkostenabrechnung. Betrag positiv in Euro-Cent, nil = fehlt noch.
public struct Position: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "position"
    public var id: Int64?
    public var reiseId: String?
    public var sachkostenId: String?
    public var datum: Tag?
    public var quelle: String?
    public var kostenart: Kostenart
    public var kostenartText: String?
    public var haendler: String
    public var ort: String?
    public var betragCent: Int?
    public var fremdbetragCent: Int?
    public var fremdwaehrung: String?
    public var zahlungId: String?
    public var privatVorgestreckt: Bool
    public var erstattung: Erstattung
    /// Bezahlt vor der Reise (Bahnticket, Konferenzticket): Zahlungstag ist nicht Reisetag.
    public var vorauskauf: Bool
    public var belegHinweis: String?
    /// Vorschlag für noch nicht zugeordnete Posten, z. B. Uber/Bolt.
    public var vorschlag: String?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Eintrag des Belegverzeichnisses (B01 …).
public struct Beleg: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "beleg"
    public var id: String
    public var dokument: String
    public var art: String?
    public var fundort: String?
    public var belegt: String?
    public var status: String?
}

public struct PositionBeleg: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "positionBeleg"
    public var positionId: Int64
    public var belegId: String
}

/// Datei im Belegordner. Gleicher Inhalt unter anderem Namen ist eine Dublette.
public struct Belegbild: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "belegbild"
    public var id: Int64?
    public var pfad: String
    public var sha256: String
    public var groesse: Int
    public var dubletteVonId: Int64?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct BelegbildBeleg: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "belegbildBeleg"
    public var belegbildId: Int64
    public var belegId: String
}

/// Gelernte Regel aus einer Entscheidung, z. B. „Hotels in Düsseldorf = privat“.
public struct Regel: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "regel"
    public var id: Int64?
    public var feld: String
    public var muster: String
    public var aktion: String
    public var wert: String
    public var herkunft: String?
    public var aktiv: Bool
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Protokoll jeder automatischen oder manuellen Entscheidung: Quelle, Regel, Sicherheitsstufe.
public struct Entscheidung: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "entscheidung"
    public var id: Int64?
    public var objektTyp: String
    public var objektId: String
    public var feld: String
    public var wert: String?
    public var quelle: String
    public var regelId: Int64?
    public var sicherheit: Sicherheit?
    public var zeit: String
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct OffenerPunkt: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "offenerPunkt"
    public var id: Int64?
    public var reiseId: String?
    public var sachkostenId: String?
    public var text: String
    public var fundort: String?
    public var erledigt: Bool
    public var herkunft: String?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
