import XCTest
import GRDB
@testable import ReisemanagerKern

/// Etappe 4: Lesesicht und Bearbeitung hinter der Oberfläche. Alle Daten sind erfunden.
final class AnsichtTests: XCTestCase {
    func bestand() throws -> Datenbank {
        let db = try Datenbank()
        let json = StartbestandTests.mappe.data(using: .utf8)!
        _ = try StartbestandImport.importiere(JSONDecoder().decode(Startbestand.self, from: json), in: db)
        _ = try StartbestandImport.importiere(JSONDecoder().decode(Startbestand.self, from: Data(StartbestandTests.zusatz.utf8)), in: db)
        return db
    }

    func testUebersichtUndDetail() throws {
        let db = try bestand()
        let u = try Ansicht.uebersicht(in: db, heute: Tag(iso: "2026-11-13"))
        XCTAssertEqual(u.reisen.map(\.id).sorted(), ["D00", "D01", "D02", "D03"])
        XCTAssertEqual(u.privat.map(\.id), ["P01"])
        XCTAssertEqual(u.sachkosten.map(\.id), ["S1", "S5"])
        XCTAssertEqual(u.summeDienstreisenCent, 15478 + 27960 + 52600 + 1100, "Privatreisen zählen nicht")
        let d01 = try XCTUnwrap(u.reisen.first { $0.id == "D01" })
        XCTAssertEqual(d01.titel, "Kongress Muster 12.-14.03.26")
        XCTAssertEqual(d01.zeitraum, "12.03.2026 – 14.03.2026")
        XCTAssertEqual(d01.status, .concurEntwurf)
        XCTAssertEqual(d01.concurNr, "ABC123")
        XCTAssertEqual(d01.ohneBetrag, 1)
        XCTAssertEqual(d01.ampel, .rot)
        XCTAssertEqual(u.reisen.first { $0.id == "D00" }?.zeitraum, "Zeitraum offen")
        XCTAssertTrue(try XCTUnwrap(u.reisen.first { $0.id == "D02" }).istStammeinsatz)

        let detail = try XCTUnwrap(Ansicht.detail(in: db, bezug: "D01", heute: Tag(iso: "2026-11-13")))
        XCTAssertEqual(detail.beginn?.wert, "12.03.2026")
        XCTAssertEqual(detail.beginn?.sicherheit, .wahrscheinlich)
        XCTAssertEqual(detail.beginn?.quelle, "Reisen_Test.xlsx")
        XCTAssertEqual(detail.positionen.count, 3)
        let bahn = try XCTUnwrap(detail.positionen.first { $0.haendler == "Bahn Vertrieb" })
        XCTAssertEqual(bahn.betrag, "154,78 €")
        XCTAssertTrue(bahn.vorauskauf)
        XCTAssertEqual(bahn.belege, ["B01"])
        XCTAssertEqual(bahn.belegAmpel, .gelb, "Beleg bekannt, Bild fehlt")
        XCTAssertEqual(detail.positionen.first { $0.haendler == "Betrag fehlt" }?.betrag, "fehlt")
        XCTAssertEqual(detail.offenePunkte.map(\.text), ["Kongressticket fehlt", "Hotelrechnung herunterladen"])
        XCTAssertTrue(detail.titelGueltig)
        XCTAssertNil(try Ansicht.detail(in: db, bezug: "D99"))
        XCTAssertEqual(try Ansicht.detail(in: db, bezug: "S1")?.positionen.count, 2)
    }

    func testBearbeitungUndBericht() throws {
        let db = try bestand()
        let parkhaus = try XCTUnwrap(db.queue.read { try Position.filter(Column("haendler") == "Parkhaus").fetchOne($0) })

        // Drag & Drop: Position von D02 nach D01, dann in die Sachkostenabrechnung.
        try Bearbeitung.verschiebe(in: db, position: parkhaus.id!, nach: "D01")
        XCTAssertEqual(try Summen.jeReise(in: db)["D01"]?.sonstigesCent, 1100)
        XCTAssertEqual(try Summen.jeReise(in: db)["D02"]?.sonstigesCent, 0)
        try Bearbeitung.verschiebe(in: db, position: parkhaus.id!, nach: "S1")
        XCTAssertEqual(try Summen.jeSachkostenabrechnung(in: db)["S1"]?.summeCent, 3872 + 1100)
        XCTAssertThrowsError(try Bearbeitung.verschiebe(in: db, position: parkhaus.id!, nach: "D99"))
        XCTAssertThrowsError(try Bearbeitung.verschiebe(in: db, position: 9999, nach: "D01"))

        try Bearbeitung.setzeStatus(in: db, bezug: "D01", status: .eingereicht)
        try Bearbeitung.setzeStatus(in: db, bezug: "S1", status: .erstattet)
        try Bearbeitung.setzeArt(in: db, reise: "D03", art: .privat)
        try Bearbeitung.setzeAnlass(in: db, reise: "D02", anlass: "Workshop Hamburg", ort: "Hamburg")
        let punkt = try XCTUnwrap(db.queue.read { try OffenerPunkt.filter(Column("text") == "Kongressticket fehlt").fetchOne($0) })
        try Bearbeitung.erledige(in: db, offenerPunkt: punkt.id!)

        let u = try Ansicht.uebersicht(in: db, heute: Tag(iso: "2026-11-13"))
        XCTAssertEqual(u.reisen.first { $0.id == "D01" }?.status, .eingereicht)
        XCTAssertEqual(u.sachkosten.first { $0.id == "S1" }?.status, .erstattet)
        XCTAssertEqual(u.privat.map(\.id).sorted(), ["D03", "P01"])
        XCTAssertEqual(try db.queue.read { try Entscheidung.filter(Column("quelle") == "Nutzer").fetchCount($0) }, 6, "jede Änderung ist protokolliert")

        let text = try XCTUnwrap(Bericht.markdown(in: db, bezug: "D01", heute: Tag(iso: "2026-11-13")))
        XCTAssertTrue(text.hasPrefix("# D01 Kongress Muster 12.-14.03.26\n"))
        XCTAssertTrue(text.contains("- **Beginn:** 12.03.2026 (Reisen_Test.xlsx, wahrscheinlich)"))
        XCTAssertTrue(text.contains("- **Status:** von mir eingereicht"))
        XCTAssertTrue(text.contains("- **Concur:** ABC123"))
        XCTAssertTrue(text.contains("| 2026-02-20 | Bahn Vertrieb | Fahrt, Vorauskauf | 154,78 € | B01 (gelb) |"))
        XCTAssertTrue(text.contains("## Was ich noch besorgen muss"))
        XCTAssertTrue(text.contains("- Hotelrechnung herunterladen – Hotelportal"))
        XCTAssertFalse(text.contains("Kongressticket fehlt\n"), "erledigter Punkt steht nicht mehr im Bericht")
        XCTAssertNil(try Bericht.markdown(in: db, bezug: "D99"))
    }

    func testVorschlagszeilenUndBesorgungsliste() throws {
        let db = try bestand()
        try db.queue.write { d in
            try Zahlung(id: "Z1", quelle: .manuell, konto: "Amex", datum: Tag(iso: "2026-03-13")!, betragCent: -1290, haendler: "BOLT OPERATIONS",
                        zweck: nil, fremdbetragCent: nil, fremdwaehrung: nil, karteLetzteVier: nil, externId: nil, kategorie: nil, zaehlt: true,
                        gepaartMitId: nil, paarSicherheit: nil, herkunftsdatei: "test", herkunftsRef: nil).insert(d)
        }
        XCTAssertEqual(try Zuordnung.vorschlaegeBilden(in: db), 1)
        let zeilen = try Ansicht.vorschlaege(in: db)
        XCTAssertEqual(zeilen.count, 1)
        XCTAssertEqual(zeilen[0].ziel, "D01")
        XCTAssertEqual(zeilen[0].betrag, "12,90 €")
        XCTAssertEqual(try Ansicht.uebersicht(in: db).offeneVorschlaege, 1)

        let liste = try Ansicht.besorgungsliste(in: db)
        XCTAssertEqual(liste.map(\.fundort), liste.map(\.fundort).sorted())
        XCTAssertEqual(liste.map(\.eintraege.count).reduce(0, +), try Ansicht.uebersicht(in: db).zuBesorgen)
        XCTAssertTrue(liste.contains { $0.fundort == "bahn.de" }, "Fundort aus dem Belegverzeichnis")
    }
}
