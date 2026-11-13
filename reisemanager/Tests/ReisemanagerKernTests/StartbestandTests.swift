import XCTest
import GRDB
@testable import ReisemanagerKern

/// Erfundener Startbestand im Aufbau der Arbeitsmappe.
final class StartbestandTests: XCTestCase {
    static let mappe = """
    {
      "jahr": 2026, "quelle": "Reisen_Test.xlsx",
      "belege": [
        {"nr": "B01", "dokument": "Bahnticket Musterstadt", "art": "Rechnung", "fundort": "bahn.de", "belegt": "D01", "status": "vorhanden"},
        {"nr": "B02", "dokument": "Parkschein", "art": "Quittung", "fundort": "Scan", "belegt": "D02", "status": "vorhanden"}
      ],
      "reisen": [
        {"nr": "D00", "anlass": "Reisenebenkosten ohne Einzelreise", "beginn": null, "ende": null, "offen": "BahnCard-Betrag nachtragen"},
        {"nr": "D01", "anlass": "Kongress Musterstadt", "beginn": "2026-03-12", "ende": "2026-03-14", "verkehrsmittel": "Bahn", "unterkunft": "Hotel Muster (2 Nächte)", "offen": "Kongressticket fehlt"},
        {"nr": "D02", "anlass": "Kundeneinsatz Hamburg", "beginn": "2026-07-20", "ende": "2026-07-23"},
        {"nr": "D03", "anlass": "Hamburger Hafenfest", "beginn": "2026-08-01", "ende": "2026-08-01"}
      ],
      "regeln": [
        {"feld": "anlass", "muster": "Hamburg", "aktion": "stammeinsatz", "wert": "Stammkunde"}
      ],
      "positionen": [
        {"reise": "D01", "datum": "2026-02-20", "quelle": "Amex+PayPal", "kostenart": "fahrt", "kostenartText": "Fahrt", "haendler": "Bahn Vertrieb", "betragCent": 15478, "zahlungId": "NP26-00010", "belege": ["B01"]},
        {"reise": "D01", "datum": "2026-03-12", "quelle": "Amex", "kostenart": "unterkunft", "haendler": "Hotel Muster", "betragCent": 27960},
        {"reise": "D01", "datum": "2026-03-13", "quelle": "offen", "kostenart": "sonstiges", "kostenartText": "Sonstiges (Kongressticket)", "haendler": "Betrag fehlt", "betragCent": null, "belegHinweis": "nachtragen"},
        {"reise": "D02", "datum": "2026-06-15", "quelle": "PayPal", "kostenart": "paket", "kostenartText": "Fahrt + Unterkunft (Paket)", "haendler": "Reisepaket GmbH", "betragCent": 52600},
        {"reise": "D02", "datum": "2026-07-20", "quelle": "bar", "kostenart": "sonstiges", "haendler": "Parkhaus", "betragCent": 1100, "belege": ["B02", "B99"]},
        {"reise": "D77", "datum": "2026-07-20", "kostenart": "fahrt", "haendler": "Irrläufer", "betragCent": 100}
      ],
      "privat": [
        {"nr": "P01", "reise": "Urlaub Insel", "beginn": "2026-07-01", "ende": "2026-07-10", "hinweis": "privat – nicht abrechnen"}
      ],
      "offenePosten": [
        {"datum": "2026-04-14", "quelle": "Uber/Bolt offen", "kostenart": "fahrt", "haendler": "Fahrdienst BV", "betragCent": 978, "zahlungId": "NP26-00020", "vorschlag": "offen – welcher Termin?"}
      ],
      "sachkosten": [
        {"nr": "S1", "titel": "Sachkostenabrechnung Tanken 2026", "hinweis": "Tankkarte defekt", "positionen": [
          {"datum": "2026-04-14", "quelle": "Amex", "kostenart": "sonstiges", "haendler": "Tankstelle Muster", "ort": "Musterstadt", "betragCent": 2394},
          {"datum": "2026-04-19", "quelle": "Amex", "kostenart": "sonstiges", "haendler": "Tankstelle Nord", "ort": "Nordstadt", "betragCent": 1478}
        ]}
      ]
    }
    """

    static let zusatz = """
    {
      "jahr": 2026, "quelle": "Concur-Stand Test",
      "concur": [
        {"nr": "D01", "titel": "Kongress Muster 12.-14.03.26", "concurNr": "ABC123"},
        {"nr": "D02", "titel": "Kunde Hamburg 20.-23.07.26", "concurNr": null},
        {"nr": "S1", "titel": "Sachkosten Tanken 2026", "concurNr": "FVA000"},
        {"nr": "S5", "titel": "Sachkosten BahnCard 25 erste Klasse 2026", "concurNr": "BC0000"},
        {"nr": "D09", "titel": "Ein viel zu langer Titel für eine Abrechnung 01.-02.09.26", "concurNr": "XYZ999"}
      ],
      "offenePunkte": [
        {"bezug": "D01", "text": "Hotelrechnung herunterladen", "fundort": "Hotelportal"},
        {"text": "Reiseverläufe mit Uhrzeiten nachtragen", "fundort": "bahn.de"}
      ]
    }
    """

    func lade(_ json: String, in db: Datenbank) throws -> Importergebnis {
        try StartbestandImport.importiere(JSONDecoder().decode(Startbestand.self, from: Data(json.utf8)), in: db)
    }

    func testStartbestandErgibtReisenUndSummen() throws {
        let db = try Datenbank()
        let ergebnis = try lade(Self.mappe, in: db)
        XCTAssertEqual(ergebnis.fehler.count, 2, "unbekannte Reise D77 und unbekannter Beleg B99: \(ergebnis.fehler)")

        let je = try Summen.jeReise(in: db)
        XCTAssertEqual(je["D01"]?.fahrtCent, 15478)
        XCTAssertEqual(je["D01"]?.unterkunftCent, 27960)
        XCTAssertEqual(je["D01"]?.sonstigesCent, 0)
        XCTAssertEqual(je["D01"]?.ohneBetrag, 1, "fehlender Betrag zählt 0 und wird ausgewiesen")
        XCTAssertEqual(je["D02"]?.unterkunftCent, 52600, "Paket steht in der Spalte Unterkunft")
        XCTAssertEqual(je["D02"]?.sonstigesCent, 1100)

        let gesamt = try Summen.dienstreisen(in: db)
        XCTAssertEqual(gesamt.summeCent, 15478 + 27960 + 52600 + 1100)
        XCTAssertEqual(try Summen.jeSachkostenabrechnung(in: db)["S1"]?.summeCent, 3872)

        try db.queue.read { d in
            XCTAssertEqual(try Reise.filter(Column("art") == "dienstreise").fetchCount(d), 4)
            XCTAssertEqual(try Reise.filter(Column("art") == "privat").fetchCount(d), 1)
            XCTAssertNil(try Reise.fetchOne(d, key: "D00")!.beginn, "Jahresangabe ist kein Datum")
            XCTAssertTrue(try Reise.fetchOne(d, key: "D02")!.istStammeinsatz, "Regel: Anlass enthält Hamburg")
            XCTAssertFalse(try Reise.fetchOne(d, key: "D01")!.istStammeinsatz)
            XCTAssertFalse(try Reise.fetchOne(d, key: "D03")!.istStammeinsatz, "nur ganze Wörter treffen")
            let protokoll = try Entscheidung.filter(Column("objektId") == "D02").fetchAll(d)
            XCTAssertEqual(protokoll.count, 1)
            XCTAssertEqual(protokoll.first?.sicherheit, .wahrscheinlich)
            XCTAssertNotNil(protokoll.first?.regelId)
            XCTAssertEqual(try Reise.fetchOne(d, key: "D01")!.beginnSicherheit, .geschaetzt)

            let bahn = try XCTUnwrap(Position.filter(Column("haendler") == "Bahn Vertrieb").fetchOne(d))
            XCTAssertTrue(bahn.vorauskauf, "Zahlung vor Reisebeginn")
            XCTAssertTrue(bahn.privatVorgestreckt)
            XCTAssertEqual(bahn.erstattung, .offen)
            XCTAssertEqual(try PositionBeleg.filter(Column("positionId") == bahn.id!).fetchCount(d), 1)
            XCTAssertFalse(try XCTUnwrap(Position.filter(Column("haendler") == "Hotel Muster").fetchOne(d)).vorauskauf)

            let offen = try XCTUnwrap(Position.filter(Column("vorschlag") != nil).fetchOne(d))
            XCTAssertNil(offen.reiseId)
            XCTAssertEqual(try OffenerPunkt.fetchCount(d), 2)
        }
    }

    func testZweiterImportVerdoppeltNichts() throws {
        let db = try Datenbank()
        _ = try lade(Self.mappe, in: db)
        let vorher = try db.queue.read { try Position.fetchCount($0) }
        let nochmal = try lade(Self.mappe, in: db)
        XCTAssertEqual(nochmal.neu, 0)
        XCTAssertEqual(try db.queue.read { try Position.fetchCount($0) }, vorher)
        XCTAssertEqual(try db.queue.read { try OffenerPunkt.fetchCount($0) }, 2)
    }

    func testConcurEntwuerfeUndOffenePunkte() throws {
        let db = try Datenbank()
        _ = try lade(Self.mappe, in: db)
        let ergebnis = try lade(Self.zusatz, in: db)
        XCTAssertEqual(ergebnis.fehler.count, 1, "D09 gibt es nicht: \(ergebnis.fehler)")
        try db.queue.read { d in
            let d01 = try Reise.fetchOne(d, key: "D01")!
            XCTAssertEqual(d01.concurNr, "ABC123")
            XCTAssertEqual(d01.concurTitel, "Kongress Muster 12.-14.03.26")
            XCTAssertEqual(d01.status, .concurEntwurf)
            XCTAssertEqual(try Reise.fetchOne(d, key: "D00")!.status, .erkannt)
            XCTAssertEqual(try Sachkostenabrechnung.fetchOne(d, key: "S1")!.concurNr, "FVA000")
            XCTAssertEqual(try Sachkostenabrechnung.fetchOne(d, key: "S5")!.status, .concurEntwurf, "S5 entsteht aus dem Concur-Stand")

            let s5 = try OffenerPunkt.filter(Column("sachkostenId") == "S5").fetchAll(d).map(\.text)
            XCTAssertEqual(s5.count, 1)
            XCTAssertTrue(s5[0].contains("40 Zeichen"), "zu langer Titel wird offener Punkt: \(s5)")
            let d02 = try OffenerPunkt.filter(Column("reiseId") == "D02").fetchAll(d).map(\.text)
            XCTAssertEqual(d02, ["Concur-Nummer prüfen"])
            let allgemein = try OffenerPunkt.filter(Column("reiseId") == nil && Column("sachkostenId") == nil).fetchAll(d)
            XCTAssertEqual(allgemein.map(\.text), ["Reiseverläufe mit Uhrzeiten nachtragen"])
            XCTAssertEqual(allgemein.first?.fundort, "bahn.de")
        }
        _ = try lade(Self.zusatz, in: db)
        let alle = try db.queue.read { try OffenerPunkt.fetchAll($0).map { "\($0.reiseId ?? $0.sachkostenId ?? "-"): \($0.text)" } }
        XCTAssertEqual(alle.count, 6, "offene Punkte entstehen nicht doppelt: \(alle)")
    }

    func testBelegordnerErkenntDubletten() throws {
        let db = try Datenbank()
        _ = try lade(Self.mappe, in: db)
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("rm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner.appendingPathComponent("unter"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        try Data("Parkschein".utf8).write(to: ordner.appendingPathComponent("B02_Parkschein.pdf"))
        try Data("Parkschein".utf8).write(to: ordner.appendingPathComponent("unter/Scan_1.pdf"))
        try Data("Ticket".utf8).write(to: ordner.appendingPathComponent("B01_B02_Ticket.jpg"))
        try Data("Notiz".utf8).write(to: ordner.appendingPathComponent("Notiz.md"))

        let ergebnis = try BelegordnerImport.importiere(ordner: ordner.path, in: db)
        XCTAssertEqual(ergebnis.neu, 2)
        XCTAssertEqual(ergebnis.zusammengefuehrt, 1)
        try db.queue.read { d in
            XCTAssertEqual(try Belegbild.fetchCount(d), 3, "Markdown ist kein Belegbild")
            let dublette = try XCTUnwrap(Belegbild.filter(Column("pfad") == "unter/Scan_1.pdf").fetchOne(d))
            let original = try XCTUnwrap(Belegbild.filter(Column("pfad") == "B02_Parkschein.pdf").fetchOne(d))
            XCTAssertEqual(dublette.dubletteVonId, original.id)
            XCTAssertEqual(try BelegbildBeleg.filter(Column("belegId") == "B02").fetchCount(d), 2)
            XCTAssertEqual(try BelegbildBeleg.filter(Column("belegId") == "B01").fetchCount(d), 1)
        }
        let nochmal = try BelegordnerImport.importiere(ordner: ordner.path, in: db)
        XCTAssertEqual(nochmal.neu, 0)
        XCTAssertEqual(nochmal.bekannt, 3)
        XCTAssertEqual(BelegordnerImport.belegnummern(imDateinamen: "B28_B29_Southern_Buchung_B30.pdf"), ["B28", "B29"])
        XCTAssertEqual(BelegordnerImport.belegnummern(imDateinamen: "Reisen_2026_v19.xlsx"), [])
    }
}
