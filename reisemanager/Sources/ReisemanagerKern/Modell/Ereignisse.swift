import Foundation
import GRDB

/// Hotelaufenthalt mit An- und Abreise, z. B. aus dem Hotelportal.
public struct Hotelaufenthalt: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "hotelaufenthalt"
    public var id: Int64?
    public var reiseId: String?
    public var hotel: String
    public var ort: String?
    public var anreise: Tag
    public var abreise: Tag
    public var quelle: String?
    public var naechte: Int { anreise.abstandInTagen(zu: abreise) }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Kalendertermin: Konferenz, Kundentermin, Anlass.
public struct Termin: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "termin"
    public var id: Int64?
    public var titel: String
    public var ort: String?
    public var beginn: Tag
    public var beginnZeit: String?
    public var ende: Tag
    public var endeZeit: String?
    public var quelle: String?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum Vorschlagsart: String, Codable, DatabaseValueConvertible, Sendable {
    /// Zahlung liegt im Zeitraum einer Dienstreise.
    case zuReise
    /// Zahlung gehört in eine Sachkostenabrechnung, z. B. Tanken.
    case zuSachkosten
    /// Mehrere Zahlungen außerhalb bekannter Reisen: mögliche neue Reise.
    case neueReise
    /// Zahlung ist voraussichtlich privat.
    case privat
    /// Vorab bezahltes Ticket: Die Reise ergibt sich aus dem Reisedatum, nicht aus dem Zahlungstag.
    case vorauskaufOffen
}

public enum Vorschlagsstatus: String, Codable, DatabaseValueConvertible, Sendable {
    case offen, angenommen, abgelehnt
}

/// Vorschlag zur Zuordnung einer Zahlung. Der Nutzer bestätigt oder ändert.
public struct Vorschlag: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "vorschlag"
    public var id: Int64?
    public var zahlungId: String
    public var art: Vorschlagsart
    public var zielId: String?
    public var kostenart: Kostenart
    public var begruendung: String
    public var sicherheit: Sicherheit
    public var status: Vorschlagsstatus
    /// Zahlungen derselben erkannten Reise tragen dieselbe Gruppe.
    public var gruppe: String?
    public var regelId: Int64?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
