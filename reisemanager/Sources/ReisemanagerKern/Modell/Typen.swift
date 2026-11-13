import Foundation
import GRDB

/// Wie verlässlich ein automatisch gesetzter Wert ist.
public enum Sicherheit: String, Codable, DatabaseValueConvertible, Sendable {
    case sicher, wahrscheinlich, geschaetzt
}

public enum Zahlungsquelle: String, Codable, DatabaseValueConvertible, Sendable {
    case nwoPay = "nwopay", amex, paypal, manuell
}

public enum Reiseart: String, Codable, DatabaseValueConvertible, Sendable {
    case dienstreise, privat
}

public enum Kostenart: String, Codable, DatabaseValueConvertible, Sendable {
    case fahrt, unterkunft, paket, verpflegung, sonstiges

    /// Spalte der Arbeitsmappe, in der die Kostenart summiert wird.
    public var summenspalte: Summenspalte {
        switch self {
        case .fahrt: return .fahrt
        case .unterkunft, .paket: return .unterkunft
        case .verpflegung, .sonstiges: return .sonstiges
        }
    }
}

public enum Summenspalte: Sendable { case fahrt, unterkunft, sonstiges }

/// Stufen des Dashboards, in dieser Reihenfolge.
public enum Reisestatus: String, Codable, DatabaseValueConvertible, CaseIterable, Sendable {
    case erkannt, bestaetigt, belegeVollstaendig, concurEntwurf, concurPositionen, eingereicht, erstattet
}

public enum Erstattung: String, Codable, DatabaseValueConvertible, Sendable {
    case offen, erstattet
}

extension Tag: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { iso.databaseValue }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Tag? {
        String.fromDatabaseValue(dbValue).flatMap { Tag(iso: $0) }
    }
}
