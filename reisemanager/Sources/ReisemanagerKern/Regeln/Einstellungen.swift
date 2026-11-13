import Foundation

/// Persönliche Festwerte. Die Datei liegt nur lokal; im Repository steht nur ein Beispiel mit Platzhaltern.
public struct Einstellungen: Codable, Equatable, Sendable {
    public struct Adresse: Codable, Equatable, Sendable {
        public var strasse: String
        public var plz: String
        public var ort: String
    }
    public struct Concur: Codable, Equatable, Sendable {
        public var anmeldung: String
        public var instanz: String
        public var logicalSystem: String
        public var companyCode: String
        public var businessArea: String
        public var costObjectType: String
        public var costObjectId: String
    }

    public var jahr: Int
    /// Abreise und Ankunft jeder Reise.
    public var privatadresse: Adresse
    public var concur: Concur
    public var belegordner: String?
    /// Reisen, die länger nicht eingereicht sind, kommen in die Wiedervorlage.
    public var wiedervorlageTage: Int?

    public static func laden(pfad: String) throws -> Einstellungen {
        try JSONDecoder().decode(Einstellungen.self, from: Data(contentsOf: URL(fileURLWithPath: pfad)))
    }
}
