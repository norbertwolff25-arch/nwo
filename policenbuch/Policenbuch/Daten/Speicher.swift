import Foundation
import SwiftData

/// Lokaler Speicherort. Kein CloudKit, kein Server: Die Konfiguration schaltet die Cloud-Datenbank ausdrücklich ab.
enum Speicher {
    static var schema: Schema { Schema([Vertrag.self, Zahlung.self, Dokument.self, Aufgabe.self]) }

    /// ~/Library/Application Support/Policenbuch
    static var ordner: URL {
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return basis.appendingPathComponent("Policenbuch", isDirectory: true)
    }

    static var datei: URL { ordner.appendingPathComponent("Policenbuch.store") }

    static func container() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let konfiguration = ModelConfiguration("Policenbuch", schema: schema, url: datei,
                                               allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: konfiguration)
    }

    static func imSpeicher() throws -> ModelContainer {
        let konfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: konfiguration)
    }
}
