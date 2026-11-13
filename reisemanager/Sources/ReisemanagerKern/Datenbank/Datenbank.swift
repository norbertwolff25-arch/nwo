import Foundation
import GRDB

/// Lokale SQLite-Datenbank. Alle Daten bleiben auf dem Mac.
public final class Datenbank {
    public let queue: DatabaseQueue

    /// Datenbank im Arbeitsspeicher, für Tests.
    public init() throws {
        queue = try DatabaseQueue()
        try Datenbank.migrator.migrate(queue)
    }

    public init(pfad: String) throws {
        let ordner = URL(fileURLWithPath: pfad).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: pfad)
        try Datenbank.migrator.migrate(queue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "zahlung") { t in
                t.primaryKey("id", .text)
                t.column("quelle", .text).notNull()
                t.column("konto", .text).notNull()
                t.column("datum", .text).notNull().indexed()
                t.column("betragCent", .integer)
                t.column("haendler", .text).notNull()
                t.column("zweck", .text)
                t.column("fremdbetragCent", .integer)
                t.column("fremdwaehrung", .text)
                t.column("karteLetzteVier", .text)
                t.column("externId", .text).indexed()
                t.column("kategorie", .text)
                t.column("zaehlt", .boolean).notNull()
                t.column("gepaartMitId", .text).references("zahlung", onDelete: .setNull)
                t.column("paarSicherheit", .text)
                t.column("herkunftsdatei", .text).notNull()
                t.column("herkunftsRef", .text)
            }
            try db.create(table: "zahlungHerkunft") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("zahlungId", .text).notNull().indexed().references("zahlung", onDelete: .cascade)
                t.column("quelle", .text).notNull()
                t.column("datei", .text).notNull()
                t.column("ref", .text)
            }
            try db.create(table: "reise") { t in
                t.primaryKey("id", .text)
                t.column("art", .text).notNull()
                t.column("typ", .text)
                t.column("anlass", .text).notNull()
                t.column("ort", .text)
                t.column("istStammeinsatz", .boolean).notNull()
                t.column("beginn", .text)
                t.column("beginnZeit", .text)
                t.column("beginnQuelle", .text)
                t.column("beginnSicherheit", .text)
                t.column("ende", .text)
                t.column("endeZeit", .text)
                t.column("endeQuelle", .text)
                t.column("endeSicherheit", .text)
                t.column("verkehrsmittel", .text)
                t.column("unterkunft", .text)
                t.column("hinweis", .text)
                t.column("status", .text).notNull()
                t.column("concurNr", .text)
                t.column("concurTitel", .text)
            }
            try db.create(table: "sachkostenabrechnung") { t in
                t.primaryKey("id", .text)
                t.column("titel", .text).notNull()
                t.column("hinweis", .text)
                t.column("status", .text).notNull()
                t.column("concurNr", .text)
                t.column("concurTitel", .text)
            }
            try db.create(table: "reiseabschnitt") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("reiseId", .text).notNull().indexed().references("reise", onDelete: .cascade)
                t.column("reihenfolge", .integer).notNull()
                t.column("art", .text).notNull()
                t.column("von", .text)
                t.column("nach", .text)
                t.column("abfahrt", .text)
                t.column("ankunft", .text)
                t.column("verkehrsmittel", .text)
                t.column("quelle", .text)
                t.column("sicherheit", .text)
            }
            try db.create(table: "position") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("reiseId", .text).indexed().references("reise", onDelete: .setNull)
                t.column("sachkostenId", .text).indexed().references("sachkostenabrechnung", onDelete: .setNull)
                t.column("datum", .text)
                t.column("quelle", .text)
                t.column("kostenart", .text).notNull()
                t.column("kostenartText", .text)
                t.column("haendler", .text).notNull()
                t.column("ort", .text)
                t.column("betragCent", .integer)
                t.column("fremdbetragCent", .integer)
                t.column("fremdwaehrung", .text)
                t.column("zahlungId", .text).indexed()
                t.column("privatVorgestreckt", .boolean).notNull()
                t.column("erstattung", .text).notNull()
                t.column("vorauskauf", .boolean).notNull()
                t.column("belegHinweis", .text)
                t.column("vorschlag", .text)
            }
            try db.create(table: "beleg") { t in
                t.primaryKey("id", .text)
                t.column("dokument", .text).notNull()
                t.column("art", .text)
                t.column("fundort", .text)
                t.column("belegt", .text)
                t.column("status", .text)
            }
            try db.create(table: "positionBeleg") { t in
                t.column("positionId", .integer).notNull().references("position", onDelete: .cascade)
                t.column("belegId", .text).notNull().references("beleg", onDelete: .cascade)
                t.primaryKey(["positionId", "belegId"])
            }
            try db.create(table: "belegbild") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pfad", .text).notNull().unique()
                t.column("sha256", .text).notNull().indexed()
                t.column("groesse", .integer).notNull()
                t.column("dubletteVonId", .integer).references("belegbild", onDelete: .setNull)
            }
            try db.create(table: "belegbildBeleg") { t in
                t.column("belegbildId", .integer).notNull().references("belegbild", onDelete: .cascade)
                t.column("belegId", .text).notNull().references("beleg", onDelete: .cascade)
                t.primaryKey(["belegbildId", "belegId"])
            }
            try db.create(table: "regel") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("feld", .text).notNull()
                t.column("muster", .text).notNull()
                t.column("aktion", .text).notNull()
                t.column("wert", .text).notNull()
                t.column("herkunft", .text)
                t.column("aktiv", .boolean).notNull()
            }
            try db.create(table: "entscheidung") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("objektTyp", .text).notNull()
                t.column("objektId", .text).notNull()
                t.column("feld", .text).notNull()
                t.column("wert", .text)
                t.column("quelle", .text).notNull()
                t.column("regelId", .integer).references("regel", onDelete: .setNull)
                t.column("sicherheit", .text)
                t.column("zeit", .text).notNull()
            }
            try db.create(table: "offenerPunkt") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("reiseId", .text).references("reise", onDelete: .cascade)
                t.column("sachkostenId", .text).references("sachkostenabrechnung", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("fundort", .text)
                t.column("erledigt", .boolean).notNull()
                t.column("herkunft", .text)
            }
        }
        m.registerMigration("v2") { db in
            try db.create(table: "hotelaufenthalt") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("reiseId", .text).indexed().references("reise", onDelete: .setNull)
                t.column("hotel", .text).notNull()
                t.column("ort", .text)
                t.column("anreise", .text).notNull()
                t.column("abreise", .text).notNull()
                t.column("quelle", .text)
            }
            try db.create(table: "termin") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("titel", .text).notNull()
                t.column("ort", .text)
                t.column("beginn", .text).notNull()
                t.column("beginnZeit", .text)
                t.column("ende", .text).notNull()
                t.column("endeZeit", .text)
                t.column("quelle", .text)
            }
            try db.create(table: "vorschlag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("zahlungId", .text).notNull().unique().references("zahlung", onDelete: .cascade)
                t.column("art", .text).notNull()
                t.column("zielId", .text)
                t.column("kostenart", .text).notNull()
                t.column("begruendung", .text).notNull()
                t.column("sicherheit", .text).notNull()
                t.column("status", .text).notNull()
                t.column("gruppe", .text)
                t.column("regelId", .integer).references("regel", onDelete: .setNull)
            }
        }
        m.registerMigration("v3") { db in
            try db.alter(table: "position") { t in
                t.add(column: "concurErfasstIn", .text)
            }
            try db.create(table: "concurAbrechnung") { t in
                t.primaryKey("nr", .text)
                t.column("titel", .text).notNull()
                t.column("status", .text)
                t.column("betragCent", .integer)
                t.column("gelesenAm", .text)
            }
            try db.create(table: "concurPosition") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("abrechnungNr", .text).indexed().references("concurAbrechnung", onDelete: .cascade)
                t.column("datum", .text)
                t.column("ausgabentyp", .text)
                t.column("lieferant", .text)
                t.column("betragCent", .integer)
                t.column("waehrung", .text)
                t.column("hatBeleg", .boolean).notNull()
            }
            try db.create(table: "concurFreigabe") { t in
                t.primaryKey("bezug", .text)
                t.column("planHash", .text).notNull()
                t.column("stapel", .boolean).notNull()
                t.column("zeit", .text).notNull()
            }
            try db.create(table: "concurProtokoll") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bezug", .text).notNull().indexed()
                t.column("schritt", .text).notNull()
                t.column("beschreibung", .text).notNull()
                t.column("ergebnis", .text).notNull()
                t.column("zeit", .text).notNull()
            }
        }
        return m
    }
}
