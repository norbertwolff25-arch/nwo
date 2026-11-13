import XCTest
import GRDB
@testable import ReisemanagerKern

/// Etappe 3: Vorbelegung, Zuordnungsvorschläge, Plausi-Prüfer. Alle Daten sind erfunden.
final class ErkennungTests: XCTestCase {
    func t(_ iso: String) -> Tag { Tag(iso: iso)! }

    func reise(_ id: String, _ anlass: String, _ von: String?, _ bis: String?, art: Reiseart = .dienstreise, mittel: String? = nil, ort: String? = nil) -> Reise {
        Reise(id: id, art: art, typ: nil, anlass: anlass, ort: ort, istStammeinsatz: false,
              beginn: von.map(t), beginnZeit: nil, beginnQuelle: "Mappe", beginnSicherheit: von == nil ? nil : .geschaetzt,
              ende: bis.map(t), endeZeit: nil, endeQuelle: "Mappe", endeSicherheit: bis == nil ? nil : .geschaetzt,
              verkehrsmittel: mittel, unterkunft: nil, hinweis: nil, status: .erkannt, concurNr: nil, concurTitel: nil)
    }

    @discardableResult
    func position(_ d: Database, _ reiseId: String?, _ datum: String, _ art: Kostenart, _ haendler: String, _ cent: Int?,
                  zahlung: String? = nil, quelle: String? = "Amex", ort: String? = nil, sachkosten: String? = nil, fremd: Int? = nil) throws -> Position {
        var p = Position(id: nil, reiseId: reiseId, sachkostenId: sachkosten, datum: t(datum), quelle: quelle, kostenart: art, kostenartText: nil,
                         haendler: haendler, ort: ort, betragCent: cent, fremdbetragCent: fremd, fremdwaehrung: fremd == nil ? nil : "GBP",
                         zahlungId: zahlung, privatVorgestreckt: true, erstattung: .offen, vorauskauf: false, belegHinweis: nil, vorschlag: nil)
        try p.insert(d)
        return p
    }

    func zahlung(_ d: Database, _ id: String, _ datum: String, _ cent: Int, _ haendler: String, konto: String = "Amex", kategorie: String? = nil) throws {
        try Zahlung(id: id, quelle: .manuell, konto: konto, datum: t(datum), betragCent: cent, haendler: haendler, zweck: nil, fremdbetragCent: nil,
                    fremdwaehrung: nil, karteLetzteVier: nil, externId: nil, kategorie: kategorie, zaehlt: true, gepaartMitId: nil,
                    paarSicherheit: nil, herkunftsdatei: "test", herkunftsRef: nil).insert(d)
    }

    func testHaendlerklassen() {
        XCTAssertEqual(Haendlerklasse.bestimme("DB Vertrieb GmbH"), .bahn)
        XCTAssertEqual(Haendlerklasse.bestimme("Uber Payments BV"), .taxi)
        XCTAssertEqual(Haendlerklasse.bestimme("Uber BV"), .abo, "Abo, keine Fahrt")
        XCTAssertEqual(Haendlerklasse.bestimme("EASYJET 000ABC"), .flug, "nicht Tankstelle JET")
        XCTAssertEqual(Haendlerklasse.bestimme("JET Tankstelle 12"), .tanken)
        XCTAssertEqual(Haendlerklasse.bestimme("IBIS MUSTERSTADT CITY"), .hotel)
        XCTAssertEqual(Haendlerklasse.bestimme("TFL TRAVEL CHARGE TFL.GOV.UK/CP"), .oepnv)
        XCTAssertEqual(Haendlerklasse.bestimme("Parkhaus am Dom"), .parken)
        XCTAssertEqual(Haendlerklasse.bestimme("Total Musterdorf"), .tanken)
        XCTAssertEqual(Haendlerklasse.bestimme("Totalschaden Gutachter"), .sonstige)
        XCTAssertEqual(Haendlerklasse.bestimme("Buchhandlung Muster"), .sonstige)
        XCTAssertEqual(Haendlerklasse.fundort(haendler: "IBIS MUSTERSTADT", quelle: "Amex", datum: nil), "ALL Accor → Rechnung")
        XCTAssertEqual(Haendlerklasse.fundort(haendler: "Buchhandlung", quelle: "Amex", datum: t("2026-03-09")), "Amex-Abrechnung 03/2026")
    }

    func testVorbelegungFolgtDerRangfolge() throws {
        let db = try Datenbank()
        try db.queue.write { d in
            try reise("D01", "Kundentermin Musterstadt", "2026-05-19", "2026-05-21").insert(d)
            try reise("D02", "Workshop Nordstadt", "2026-06-10", "2026-06-11").insert(d)
            try reise("D03", "Termin Südstadt", nil, nil).insert(d)
            try position(d, "D02", "2026-06-09", .fahrt, "Uber Payments BV", 1200)
            try position(d, "D02", "2026-06-12", .fahrt, "Uber Payments BV", 1400)
            try position(d, "D03", "2026-04-01", .fahrt, "DB Vertrieb", 9000) // Vorauskauf: kein Reisetag
            try position(d, "D03", "2026-04-20", .unterkunft, "Hotel Süd", 8000)
            try position(d, "D03", "2026-04-21", .fahrt, "Stadtbus Süd", 300)
        }
        _ = try EreignisImport.importiere(Ereignisse(
            abschnitte: [
                .init(reise: "D01", art: "vorlauf", von: "Privatadresse", nach: "Hbf", abfahrt: "2026-05-19 06:40", ankunft: "2026-05-19 07:05", verkehrsmittel: "Taxi", quelle: nil),
                .init(reise: "D01", art: "hauptlauf", von: "Hbf", nach: "Musterstadt", abfahrt: "2026-05-19 07:27", ankunft: "2026-05-19 11:42", verkehrsmittel: "ICE", quelle: "bahn.de Auftrag 1"),
                .init(reise: "D01", art: "hauptlauf", von: "Musterstadt", nach: "Hbf", abfahrt: "2026-05-22T15:10", ankunft: "2026-05-22T19:31", verkehrsmittel: "ICE", quelle: "bahn.de Auftrag 1"),
            ],
            aufenthalte: [.init(reise: "D01", hotel: "Hotel Muster", ort: "Musterstadt", anreise: t("2026-05-19"), abreise: t("2026-05-21"), quelle: "Hotelportal")],
            termine: nil), in: db)

        XCTAssertEqual(try Vorbelegung.anwenden(in: db), 3)
        try db.queue.read { d in
            let d01 = try Reise.fetchOne(d, key: "D01")!
            XCTAssertEqual(d01.beginn, t("2026-05-19"))
            XCTAssertEqual(d01.beginnZeit, "06:40", "Vorlauf zählt zum Beginn")
            XCTAssertEqual(d01.beginnSicherheit, .sicher)
            XCTAssertTrue(d01.beginnQuelle!.contains("Vorlauf"))
            XCTAssertEqual(d01.ende, t("2026-05-22"), "Zugzeit schlägt Hotel-Abreise")
            XCTAssertEqual(d01.endeZeit, "19:31")
            XCTAssertEqual(d01.endeQuelle, "bahn.de Auftrag 1")

            let d02 = try Reise.fetchOne(d, key: "D02")!
            XCTAssertEqual(d02.beginn, t("2026-06-09"), "erste Uber-Fahrt ist verlässlicher als die Schätzung")
            XCTAssertEqual(d02.ende, t("2026-06-12"))
            XCTAssertEqual(d02.beginnSicherheit, .wahrscheinlich)

            let d03 = try Reise.fetchOne(d, key: "D03")!
            XCTAssertEqual(d03.beginn, t("2026-04-20"), "Bahnticket vom 1.4. ist Vorauskauf, kein Reisetag")
            XCTAssertEqual(d03.ende, t("2026-04-21"))
            XCTAssertEqual(d03.beginnSicherheit, .geschaetzt)
            XCTAssertTrue(try Position.filter(Column("haendler") == "DB Vertrieb").fetchOne(d)!.vorauskauf)
            XCTAssertEqual(try Entscheidung.filter(Column("objektTyp") == "reise").fetchCount(d), 6, "jede Änderung ist protokolliert")
        }
        XCTAssertEqual(try Vorbelegung.anwenden(in: db), 0, "zweiter Lauf ändert nichts")

        // Vom Nutzer bestätigte Werte bleiben stehen, auch wenn später eine bessere Quelle kommt.
        try Vorbelegung.bestaetige(in: db, reise: "D02", beginn: Zeitpunkt(text: "2026-06-10 08:00"), ende: nil)
        _ = try EreignisImport.importiere(Ereignisse(abschnitte: [
            .init(reise: "D02", art: nil, von: "A", nach: "B", abfahrt: "2026-06-09 18:00", ankunft: "2026-06-09 20:00", verkehrsmittel: "Bahn", quelle: nil)],
            aufenthalte: nil, termine: nil), in: db)
        _ = try Vorbelegung.anwenden(in: db)
        try db.queue.read { d in
            let d02 = try Reise.fetchOne(d, key: "D02")!
            XCTAssertEqual(d02.beginn, t("2026-06-10"))
            XCTAssertEqual(d02.beginnQuelle, "Nutzer")
            XCTAssertEqual(d02.ende, t("2026-06-09"), "Ende war nicht bestätigt und folgt der Zugzeit")
        }
    }

    func testZuordnungsvorschlaege() throws {
        let db = try Datenbank()
        try db.queue.write { d in
            try reise("D01", "Kundentermin Musterstadt", "2026-05-19", "2026-05-21").insert(d)
            try reise("P01", "Urlaub Insel", "2026-07-01", "2026-07-10", art: .privat).insert(d)
            try Sachkostenabrechnung(id: "S1", titel: "Sachkosten Tanken 2026", hinweis: "Tankkarte defekt", status: .erkannt, concurNr: nil, concurTitel: nil).insert(d)
            try zahlung(d, "Z01", "2026-05-20", -1290, "BOLT OPERATIONS OU")             // in D01
            try zahlung(d, "Z02", "2026-05-19", -27783, "HOTEL MUSTER MUSTERSTADT")      // schon Position
            try position(d, "D01", "2026-05-19", .unterkunft, "HOTEL MUSTER MUSTERSTADT", 27783, zahlung: "Z02")
            try zahlung(d, "Z03", "2026-07-03", -2856, "Uber Payments BV", konto: "PayPal") // in P01
            try zahlung(d, "Z04", "2026-04-14", -2394, "Shell Station 123")              // Tanken
            try zahlung(d, "Z05", "2026-01-24", -15000, "STEIGENBERGER HEIMSTADT")       // Hotel am Wohnort
            try zahlung(d, "Z06", "2026-08-26", -25361, "DB Vertrieb GmbH", konto: "PayPal") // Vorauskauf ohne Reise
            try zahlung(d, "Z07", "2026-09-01", -8219, "IBIS FLUGHAFEN NORD")            // neue Reise, Tag 1
            try zahlung(d, "Z08", "2026-09-02", -1278, "Uber Payments BV", konto: "PayPal") // neue Reise, Tag 2
            try zahlung(d, "Z09", "2026-10-15", -978, "Uber Payments BV", konto: "PayPal")  // eigene Gruppe
            try zahlung(d, "Z10", "2026-05-20", -499, "Uber BV", konto: "PayPal")           // Abo: kein Vorschlag
            try zahlung(d, "Z11", "2026-05-20", -1999, "Buchhandlung Muster")               // nicht reisebezogen
            try zahlung(d, "Z12", "2026-05-20", 5000, "Erstattung Arbeitgeber", konto: "DKB") // Eingang
            try zahlung(d, "Z13", "2026-05-21", -50775, "KONFERENZ VERANSTALTER INC", kategorie: "RK Reise") // Reisekategorie
        }
        XCTAssertEqual(try Zuordnung.vorschlaegeBilden(in: db, wohnort: "Heimstadt"), 9)
        XCTAssertEqual(try Zuordnung.vorschlaegeBilden(in: db, wohnort: "Heimstadt"), 0, "zweiter Lauf schlägt nichts doppelt vor")

        func vorschlag(_ zahlungId: String) throws -> Vorschlag? {
            try db.queue.read { try Vorschlag.filter(Column("zahlungId") == zahlungId).fetchOne($0) }
        }
        XCTAssertEqual(try vorschlag("Z01")?.art, .zuReise)
        XCTAssertEqual(try vorschlag("Z01")?.zielId, "D01")
        XCTAssertNil(try vorschlag("Z02"))
        XCTAssertEqual(try vorschlag("Z03")?.art, .privat)
        XCTAssertEqual(try vorschlag("Z03")?.zielId, "P01")
        XCTAssertEqual(try vorschlag("Z04")?.art, .zuSachkosten)
        XCTAssertEqual(try vorschlag("Z04")?.zielId, "S1")
        XCTAssertEqual(try vorschlag("Z05")?.art, .privat)
        XCTAssertEqual(try vorschlag("Z05")?.begruendung, "Hotel am Wohnort")
        XCTAssertEqual(try vorschlag("Z06")?.art, .vorauskaufOffen)
        XCTAssertEqual(try vorschlag("Z07")?.art, .neueReise)
        XCTAssertEqual(try vorschlag("Z07")?.gruppe, try vorschlag("Z08")?.gruppe)
        XCTAssertNotEqual(try vorschlag("Z09")?.gruppe, try vorschlag("Z08")?.gruppe)
        XCTAssertNil(try vorschlag("Z10"))
        XCTAssertNil(try vorschlag("Z11"))
        XCTAssertNil(try vorschlag("Z12"))
        XCTAssertEqual(try vorschlag("Z13")?.zielId, "D01")

        // Annehmen: Position entsteht, nichts ohne Bestätigung.
        XCTAssertEqual(try db.queue.read { try Position.fetchCount($0) }, 1)
        XCTAssertEqual(try Zuordnung.annehmen(in: db, vorschlag: try vorschlag("Z01")!.id!), "D01")
        XCTAssertEqual(try Zuordnung.annehmen(in: db, vorschlag: try vorschlag("Z04")!.id!), "S1")
        let neueReise = try Zuordnung.annehmen(in: db, vorschlag: try vorschlag("Z08")!.id!)
        XCTAssertEqual(neueReise, "D02")
        XCTAssertEqual(try Zuordnung.annehmen(in: db, vorschlag: try vorschlag("Z06")!.id!, ziel: "D02"), "D02")
        XCTAssertThrowsError(try Zuordnung.annehmen(in: db, vorschlag: try vorschlag("Z01")!.id!), "schon entschieden")
        try Zuordnung.ablehnen(in: db, vorschlag: try vorschlag("Z09")!.id!)
        XCTAssertNil(try Zuordnung.annehmen(in: db, vorschlag: try vorschlag("Z05")!.id!, alsRegel: true))

        try db.queue.read { d in
            let bolt = try XCTUnwrap(Position.filter(Column("zahlungId") == "Z01").fetchOne(d))
            XCTAssertEqual(bolt.betragCent, 1290)
            XCTAssertEqual(bolt.kostenart, .fahrt)
            XCTAssertEqual(try Position.filter(Column("sachkostenId") == "S1").fetchCount(d), 1)
            let d02 = try XCTUnwrap(Reise.fetchOne(d, key: "D02"))
            XCTAssertEqual(d02.beginn, self.t("2026-09-01"))
            XCTAssertEqual(d02.ende, self.t("2026-09-02"))
            XCTAssertEqual(d02.beginnSicherheit, .geschaetzt)
            XCTAssertEqual(try Position.filter(Column("reiseId") == "D02").fetchCount(d), 3)
            XCTAssertTrue(try Position.filter(Column("zahlungId") == "Z06").fetchOne(d)!.vorauskauf)
            XCTAssertEqual(try OffenerPunkt.filter(Column("reiseId") == "D02").fetchCount(d), 1)
            XCTAssertEqual(try Regel.filter(Column("aktion") == "privat").fetchCount(d), 1)
        }
        XCTAssertEqual(try Summen.dienstreisen(in: db).summeCent, 27783 + 1290 + 8219 + 1278 + 25361)

        // Gelernte Regel: Derselbe Händler wird künftig sicher als privat vorgeschlagen.
        try db.queue.write { try self.zahlung($0, "Z20", "2026-11-02", -16000, "STEIGENBERGER HEIMSTADT") }
        XCTAssertEqual(try Zuordnung.vorschlaegeBilden(in: db), 1)
        XCTAssertEqual(try vorschlag("Z20")?.sicherheit, .sicher)
        XCTAssertNotNil(try vorschlag("Z20")?.regelId)
    }

    func testPlausiPrueferFindetLueckenUndFragtGesammelt() throws {
        let db = try Datenbank()
        let einstellungen = Einstellungen(
            jahr: 2026, privatadresse: .init(strasse: "Musterweg 1", plz: "00000", ort: "Heimstadt"),
            concur: .init(anmeldung: "a@b.example", instanz: "https://example.invalid", logicalSystem: "-", companyCode: "-", businessArea: "-",
                          costObjectType: "-", costObjectId: "-"), belegordner: nil, wiedervorlageTage: 30)
        try db.queue.write { d in
            try Beleg(id: "B01", dokument: "Bahnticket", art: "Rechnung", fundort: "bahn.de → Vergangene Reisen", belegt: "D02 Einsatz", status: "herunterladen").insert(d)
            try Beleg(id: "B02", dokument: "Parkschein", art: "Quittung", fundort: "Scan", belegt: "D03", status: "vorhanden").insert(d)
            var bild = Belegbild(id: nil, pfad: "B02_Parkschein.pdf", sha256: "x", groesse: 1, dubletteVonId: nil)
            try bild.insert(d)
            try BelegbildBeleg(belegbildId: bild.id!, belegId: "B02").insert(d)

            // D01 Kongress: Ticket und Hotel fehlen, eine Position in Fremdwährung ohne Euro-Betrag.
            try reise("D01", "Fachkongress Weststadt", "2026-01-25", "2026-01-28").insert(d)
            try position(d, "D01", "2026-01-25", .fahrt, "Uber Payments BV", 2845, zahlung: "Z1", quelle: "PayPal")
            try position(d, "D01", "2026-01-25", .fahrt, "Testrail", nil, quelle: "Karte", fremd: 1620)
            // D02 Bahn-Einsatz: vollständig bis auf Bilder; ein Taxi nach Reiseende und ein Hotel am Wohnort.
            try reise("D02", "Einsatz Oststadt", "2026-07-20", "2026-07-23", ort: "Oststadt").insert(d)
            try position(d, "D02", "2026-06-26", .fahrt, "DB Vertrieb", 15478, zahlung: "Z2", quelle: "Amex+PayPal")
            try position(d, "D02", "2026-07-20", .unterkunft, "MERCURE OSTSTADT", 27960, zahlung: "Z3")
            try position(d, "D02", "2026-07-25", .fahrt, "BOLT OPERATIONS", 990, zahlung: "Z4")
            try position(d, "D02", "2026-07-21", .unterkunft, "Hotel Heimstadt Mitte", 9000, zahlung: "Z5")
            try position(d, "D02", "2026-07-22", .fahrt, "Transfer Sonnenschein SL", 2000, zahlung: "Z6", ort: "Inselstadt")
            // D03 Dienstwagen: Parken mit Belegbild, sonst nichts offen außer der Übernachtung.
            try reise("D03", "Kundenbesuch Nordstadt", "2026-10-27", "2026-10-28", mittel: "Dienstwagen").insert(d)
            let parken = try position(d, "D03", "2026-10-27", .sonstiges, "Parkhaus Nordstadt", 1100, quelle: "bar")
            try PositionBeleg(positionId: parken.id!, belegId: "B02").insert(d)
            // D04 liegt in der Zukunft.
            try reise("D04", "Strategietreffen Südstadt", "2026-12-14", "2026-12-16").insert(d)
            // D05 ohne Zeitraum.
            try reise("D05", "Nebenkosten", nil, nil).insert(d)
            // Sachkosten.
            try Sachkostenabrechnung(id: "S1", titel: "Sachkosten Software", hinweis: nil, status: .erkannt, concurNr: nil, concurTitel: nil).insert(d)
            try position(d, nil, "2026-02-16", .sonstiges, "Softwareanbieter", 10144, quelle: "Amex", sachkosten: "S1")
            try Sachkostenabrechnung(id: "S2", titel: "Sachkosten Zertifikat", hinweis: "Fortbildung", status: .erkannt, concurNr: nil, concurTitel: nil).insert(d)
        }
        let heute = t("2026-11-13")
        func bericht(_ id: String) throws -> Pruefbericht {
            try XCTUnwrap(Plausi.pruefe(in: db, einstellungen: einstellungen, heute: heute).first { $0.bezug == id })
        }
        func schluessel(_ b: Pruefbericht) -> Set<String> { Set(b.befunde.map(\.schluessel).map { $0.split(separator: ":").prefix(2).joined(separator: ":") }) }

        let d01 = try bericht("D01")
        XCTAssertEqual(d01.typ, .kongress)
        XCTAssertEqual(d01.ampel, .rot)
        XCTAssertTrue(schluessel(d01).isSuperset(of: ["D01:ticket", "D01:hotel", "D01:anreise", "D01:euro", "D01:bild", "D01:wiedervorlage"]), "\(schluessel(d01))")
        XCTAssertEqual(d01.fragen.map(\.schluessel), ["D01:ticket", "D01:anreise", "D01:hotel"], "Nachfragen gesammelt je Reise")
        XCTAssertTrue(d01.fragen.allSatisfy { $0.frage.optionen.count >= 2 })
        XCTAssertTrue(d01.befunde.contains { $0.art == .belegbild && $0.ampel == .gelb }, "Zahlung bekannt, Bild fehlt")
        XCTAssertTrue(d01.befunde.contains { $0.art == .belegbild && $0.ampel == .rot && $0.text.contains("Testrail") }, "ohne Betrag und Zahlung: Position ohne Beleg")

        let d02 = try bericht("D02")
        XCTAssertEqual(d02.typ, .bahn)
        XCTAssertFalse(schluessel(d02).contains("D02:hotel"))
        XCTAssertFalse(schluessel(d02).contains("D02:anreise"))
        XCTAssertTrue(d02.befunde.contains { $0.schluessel.hasPrefix("D02:zeit:") && $0.text.contains("BOLT") }, "Taxi nach Reiseende")
        XCTAssertFalse(d02.befunde.contains { $0.schluessel.hasPrefix("D02:zeit:") && $0.text.contains("DB Vertrieb") }, "Bahnticket ist Vorauskauf")
        XCTAssertTrue(d02.befunde.contains { $0.schluessel.hasPrefix("D02:wohnort:") && $0.ampel == .rot })
        XCTAssertTrue(d02.befunde.contains { $0.schluessel.hasPrefix("D02:ort:") && $0.text.contains("Inselstadt") })
        XCTAssertTrue(d02.besorgen.contains { $0.fundort == "bahn.de → Meine Reisen → Rechnung herunterladen" })
        XCTAssertTrue(d02.besorgen.contains { $0.fundort == "ALL Accor → Rechnung" })
        XCTAssertTrue(d02.besorgen.contains { $0.text.hasPrefix("B01") && $0.fundort == "bahn.de → Vergangene Reisen" }, "Beleg aus dem Verzeichnis ohne Bild")

        let d03 = try bericht("D03")
        XCTAssertEqual(d03.typ, .pkw)
        XCTAssertFalse(d03.befunde.contains { $0.art == .belegbild }, "Parkschein hat ein Bild")
        XCTAssertEqual(schluessel(d03), ["D03:hotel"])
        XCTAssertEqual(d03.ampel, .rot)

        let d04 = try bericht("D04")
        XCTAssertEqual(d04.ampel, .gelb, "bevorstehende Reise: fehlende Belege sind noch kein Mangel")
        XCTAssertFalse(schluessel(d04).contains("D04:wiedervorlage"))
        XCTAssertEqual(try bericht("D05").befunde.first?.art, .zeitraum)

        let s1 = try bericht("S1")
        XCTAssertTrue(schluessel(s1).contains("S1:begruendung"))
        XCTAssertEqual(s1.ampel, .gelb)
        XCTAssertEqual(try bericht("S2").ampel, .rot, "Abrechnung ohne Position")

        // Antworten: erledigende Antwort räumt den Befund ab, „Beleg folgt“ setzt ihn auf die Besorgungsliste.
        XCTAssertEqual(try Plausi.beantworte(in: db, schluessel: "D03:hotel", nummer: 2, einstellungen: einstellungen), "Privat übernachtet, keine Kosten")
        XCTAssertEqual(try bericht("D03").ampel, .gruen)
        XCTAssertEqual(try Plausi.beantworte(in: db, schluessel: "D01:anreise", nummer: 2, einstellungen: einstellungen), "Flug, Beleg folgt")
        let danach = try bericht("D01")
        XCTAssertEqual(danach.fragen.map(\.schluessel), ["D01:ticket", "D01:hotel"], "beantwortete Frage kommt nicht wieder")
        XCTAssertEqual(danach.befunde.first { $0.schluessel == "D01:anreise" }?.antwort, "Flug, Beleg folgt")
        XCTAssertTrue(danach.besorgen.contains { $0.text == "Anreise und Rückreise fehlen" })
        XCTAssertThrowsError(try Plausi.beantworte(in: db, schluessel: "D01:anreise", nummer: 1, einstellungen: einstellungen))
        XCTAssertThrowsError(try Plausi.beantworte(in: db, schluessel: "D01:ticket", nummer: 9, einstellungen: einstellungen))
    }
}
