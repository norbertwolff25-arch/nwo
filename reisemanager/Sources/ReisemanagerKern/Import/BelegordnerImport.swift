import Foundation
import GRDB

/// Liest die Dateien des Belegordners ein. Gleicher Inhalt unter anderem Namen wird als Dublette markiert.
public enum BelegordnerImport {
    public static let endungen: Set<String> = ["pdf", "jpg", "jpeg", "png", "heic", "tif", "tiff"]

    public static func importiere(ordner: String, in datenbank: Datenbank) throws -> Importergebnis {
        let wurzel = URL(fileURLWithPath: ordner).standardizedFileURL
        guard let zaehler = FileManager.default.enumerator(at: wurzel, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw Importfehler.nichtLesbar(datei: ordner, grund: "Ordner nicht lesbar")
        }
        var dateien: [URL] = []
        for case let url as URL in zaehler where endungen.contains(url.pathExtension.lowercased()) {
            if url.lastPathComponent.hasPrefix(".") { continue }
            dateien.append(url.standardizedFileURL)
        }
        dateien.sort { $0.path < $1.path }

        var ergebnis = Importergebnis()
        try datenbank.queue.write { db in
            for url in dateien {
                let pfad = String(url.path.dropFirst(wurzel.path.count).drop(while: { $0 == "/" }))
                let daten: Data
                do { daten = try Data(contentsOf: url) } catch {
                    ergebnis.fehler.append("\(pfad): nicht lesbar"); continue
                }
                let hash = SHA256.hex(daten)
                if var vorhandenes = try Belegbild.filter(Column("pfad") == pfad).fetchOne(db) {
                    if vorhandenes.sha256 != hash {
                        vorhandenes.sha256 = hash
                        vorhandenes.groesse = daten.count
                        try vorhandenes.update(db)
                    }
                    ergebnis.bekannt += 1
                    continue
                }
                let original = try Belegbild
                    .filter(Column("sha256") == hash && Column("dubletteVonId") == nil)
                    .order(Column("id")).fetchOne(db)
                var bild = Belegbild(id: nil, pfad: pfad, sha256: hash, groesse: daten.count, dubletteVonId: original?.id)
                try bild.insert(db)
                if original != nil { ergebnis.zusammengefuehrt += 1 } else { ergebnis.neu += 1 }
                for nummer in belegnummern(imDateinamen: url.lastPathComponent) where try Beleg.exists(db, key: nummer) {
                    try BelegbildBeleg(belegbildId: bild.id!, belegId: nummer).insert(db, onConflict: .ignore)
                }
            }
        }
        return ergebnis
    }

    /// „B07_B08_Bahnticket.pdf“ → ["B07", "B08"]. Nur führende Belegnummern zählen.
    static func belegnummern(imDateinamen name: String) -> [String] {
        var nummern: [String] = []
        let stamm = name.split(separator: ".").first.map(String.init) ?? name
        for teil in stamm.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " }) {
            guard teil.count >= 3, teil.first == "B", teil.dropFirst().allSatisfy(\.isNumber) else { break }
            nummern.append(String(teil))
        }
        return nummern
    }
}
