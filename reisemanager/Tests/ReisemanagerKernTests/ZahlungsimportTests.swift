import XCTest
import GRDB
@testable import ReisemanagerKern

/// Alle Testdaten sind erfunden und folgen nur dem Aufbau der echten Exporte.
final class ZahlungsimportTests: XCTestCase {
    static let nwoPay = """
    \u{FEFF}pay_id;konto;art;datum;richtung;betrag;gegenpartei;zweck;iban;referenz;kategorie;einordnung;einschaetzung;zaehlt;zaehlt_grund;beleg_nr;belege;gesamt_id;quelle_datei;quelle_ref;geaendert_am;gesperrt;notiz
    NP26-00001;PayPal;Zahlung;2026-03-10;Ausgang;-250,00;Testflug Reisen GmbH;Pauschalreise;;TX111;RK Reise;;;1;;;;PP-TX111;paypal_test.csv;Tx TX111;2026-10-21 07:44;0;
    NP26-00002;Amex;Zahlung;2026-03-11;Ausgang;-250,00;PAYPAL *TESTFLUGRE 4029357733;;;;RK Reise;;;0;Finanzierung;;;AMEX-2026-001;amex_test.xlsx;Zeile 2;2026-10-21 07:44;0;
    NP26-00003;Amex;Zahlung;2026-05-19;Ausgang;-120,50;HOTEL MUSTER KOELN;Übernachtung;;;RK Reise;;;1;;;;AMEX-2026-002;amex_test.xlsx;Zeile 3;2026-10-21 07:44;0;
    NP26-00004;DKB;Zahlung;2026-05-20;Ausgang;-9,99;Streamingdienst;"Abo; monatlich";;;Privat;;;1;;;;DKB-1;dkb_test.csv;Zeile 4;2026-10-21 07:44;0;
    NP26-00005;DKB;Zahlung;kein Datum;Ausgang;-1,00;Kaputt;;;;;;;1;;;;;;;;;
    NP26-00006;DKB;Zahlung;2026-05-21;Ausgang;viel;Kaputt;;;;;;;1;;;;;;;;;
    """

    static let amex = """
    Datum,Beschreibung,Karteninhaber,Konto #,Betrag,Weitere Details,Erscheint auf Ihrer Abrechnung als,Adresse,Stadt,PLZ,Land,Betreff,Kategorie
    19/05/2026,HOTEL MUSTER KOELN,ERIKA MUSTER,-12345,"120,50",,HOTEL MUSTER KOELN,"MUSTERSTR. 1
    KOELN",,50667,GERMANY,'AT260000000000000000001',Travel-Lodging
    25/01/2026,TESTRAIL LONDON,ERIKA MUSTER,-12345,"18,68",Foreign Spend Amount: 16.20 Pound Sterling Commission Amount: 0.37 Currency Exchange Rate: 1.1302,TESTRAIL LONDON,"1 TEST ROAD
    LONDON",,,UNITED KINGDOM,'AT260000000000000000002',Travel-Rail
    02/06/2026,TANKSTELLE MUSTER,ERIKA MUSTER,-12345,"23,94",,TANKSTELLE MUSTER,,,,GERMANY,'AT260000000000000000003',Transportation-Fuel
    """

    static let paypal = """
    "Datum","Uhrzeit","Zeitzone","Name","Typ","Status","Währung","Brutto","Entgelt","Netto","Transaktionscode","Zugehöriger Transaktionscode"
    "10.03.2026","09:15:00","CET","Testflug Reisen GmbH","Zahlung im Einzugsverfahren","Abgeschlossen","EUR","-250,00","0,00","-250,00","TX111",""
    "12.03.2026","10:00:00","CET","Fahrdienst BV","Zahlung im Einzugsverfahren","Abgeschlossen","EUR","-12,78","0,00","-12,78","TX222",""
    "14.03.2026","11:00:00","CET","London Cab Ltd","Zahlung im Einzugsverfahren","Abgeschlossen","GBP","-20,00","0,00","-20,00","TX333",""
    "14.03.2026","11:00:00","CET","","Allgemeine Währungsumrechnung","Abgeschlossen","EUR","-23,45","0,00","-23,45","TX334","TX333"
    "14.03.2026","11:00:00","CET","","Allgemeine Währungsumrechnung","Abgeschlossen","GBP","20,00","0,00","20,00","TX335","TX333"
    """

    func testNWOPayImportMeldetFehlerUndIstWiederholbar() throws {
        let db = try Datenbank()
        let erster = try NWOPayImport.importiere(text: Self.nwoPay, dateiname: "NWO_Pay_Test.csv", in: db)
        XCTAssertEqual(erster.neu, 4)
        XCTAssertEqual(erster.fehler.count, 2)
        XCTAssertTrue(erster.fehler[0].contains("NP26-00005") && erster.fehler[0].contains("Datum"))
        XCTAssertTrue(erster.fehler[1].contains("NP26-00006") && erster.fehler[1].contains("Betrag"))

        let zweiter = try NWOPayImport.importiere(text: Self.nwoPay, dateiname: "NWO_Pay_Test.csv", in: db)
        XCTAssertEqual(zweiter.neu, 0)
        XCTAssertEqual(zweiter.bekannt, 4)

        try db.queue.read { d in
            let abo = try XCTUnwrap(Zahlung.fetchOne(d, key: "NP26-00004"))
            XCTAssertEqual(abo.betragCent, -999)
            XCTAssertEqual(abo.zweck, "Abo; monatlich")
            XCTAssertEqual(abo.herkunftsdatei, "dkb_test.csv")
            XCTAssertTrue(abo.zaehlt)
            XCTAssertFalse(try XCTUnwrap(Zahlung.fetchOne(d, key: "NP26-00002")).zaehlt)
        }
    }

    func testFehlendeSpaltenBrechenAb() throws {
        let db = try Datenbank()
        XCTAssertThrowsError(try NWOPayImport.importiere(text: "a;b\n1;2\n", dateiname: "falsch.csv", in: db))
        XCTAssertThrowsError(try AmexImport.importiere(text: "Datum,Text\n", dateiname: "falsch.csv", in: db))
    }

    func testAmexErgaenztBekannteUmsaetzeStattSieZuVerdoppeln() throws {
        let db = try Datenbank()
        _ = try NWOPayImport.importiere(text: Self.nwoPay, dateiname: "NWO_Pay_Test.csv", in: db)
        let ergebnis = try AmexImport.importiere(text: Self.amex, dateiname: "activity.csv", in: db)
        XCTAssertEqual(ergebnis.zusammengefuehrt, 1, "Hotel steht schon in NWO-Pay")
        XCTAssertEqual(ergebnis.neu, 2)
        XCTAssertEqual(ergebnis.fehler, [])

        try db.queue.read { d in
            let hotel = try XCTUnwrap(Zahlung.fetchOne(d, key: "NP26-00003"))
            XCTAssertEqual(hotel.karteLetzteVier, "2345", "nur die letzten vier Ziffern")
            XCTAssertEqual(try ZahlungHerkunft.filter(Column("zahlungId") == "NP26-00003").fetchCount(d), 2)

            let bahn = try XCTUnwrap(Zahlung.fetchOne(d, key: "AMEX-AT260000000000000000002"))
            XCTAssertEqual(bahn.betragCent, -1868)
            XCTAssertEqual(bahn.fremdbetragCent, 1620)
            XCTAssertEqual(bahn.fremdwaehrung, "GBP")
            XCTAssertEqual(try Zahlung.filter(Column("konto") == "Amex").fetchCount(d), 4)
        }
        let nochmal = try AmexImport.importiere(text: Self.amex, dateiname: "activity.csv", in: db)
        XCTAssertEqual(nochmal.neu, 0)
        XCTAssertEqual(nochmal.bekannt, 3)
    }

    func testPayPalImportErkenntBekannteUndFremdwaehrung() throws {
        let db = try Datenbank()
        _ = try NWOPayImport.importiere(text: Self.nwoPay, dateiname: "NWO_Pay_Test.csv", in: db)
        let ergebnis = try PayPalImport.importiere(text: Self.paypal, dateiname: "paypal.csv", in: db)
        XCTAssertEqual(ergebnis.bekannt, 1, "TX111 steht über gesamt_id schon in NWO-Pay")
        XCTAssertEqual(ergebnis.neu, 4)

        try db.queue.read { d in
            let taxi = try XCTUnwrap(Zahlung.fetchOne(d, key: "PP-TX333"))
            XCTAssertEqual(taxi.fremdbetragCent, -2000)
            XCTAssertEqual(taxi.fremdwaehrung, "GBP")
            XCTAssertEqual(taxi.betragCent, -2345, "Euro-Betrag aus der Währungsumrechnung")
            XCTAssertTrue(taxi.zaehlt)
            XCTAssertFalse(try XCTUnwrap(Zahlung.fetchOne(d, key: "PP-TX334")).zaehlt, "Umrechnung ist Gegenbuchung")
            let ohneEuro = try XCTUnwrap(Zahlung.fetchOne(d, key: "PP-TX335"))
            XCTAssertNil(ohneEuro.betragCent, "kein Euro-Betrag bekannt: Feld bleibt leer")
        }
    }

    func testNWOPayNachPayPalLegtNichtsDoppeltAn() throws {
        let db = try Datenbank()
        _ = try PayPalImport.importiere(text: Self.paypal, dateiname: "paypal.csv", in: db)
        let ergebnis = try NWOPayImport.importiere(text: Self.nwoPay, dateiname: "NWO_Pay_Test.csv", in: db)
        XCTAssertEqual(ergebnis.zusammengefuehrt, 1)
        XCTAssertEqual(ergebnis.neu, 3)
        try db.queue.read { d in
            XCTAssertNil(try Zahlung.fetchOne(d, key: "NP26-00001"))
            XCTAssertEqual(try ZahlungHerkunft.filter(Column("zahlungId") == "PP-TX111").fetchCount(d), 2)
        }
    }

    func testPaarungPayPalMitAmex() throws {
        let db = try Datenbank()
        _ = try NWOPayImport.importiere(text: Self.nwoPay, dateiname: "NWO_Pay_Test.csv", in: db)
        XCTAssertEqual(try Paarung.paareBilden(in: db), 1)
        try db.queue.read { d in
            let paypal = try XCTUnwrap(Zahlung.fetchOne(d, key: "NP26-00001"))
            let amex = try XCTUnwrap(Zahlung.fetchOne(d, key: "NP26-00002"))
            XCTAssertEqual(paypal.gepaartMitId, "NP26-00002")
            XCTAssertEqual(amex.gepaartMitId, "NP26-00001")
            XCTAssertEqual(paypal.paarSicherheit, .sicher)
            XCTAssertTrue(paypal.zaehlt)
            XCTAssertFalse(amex.zaehlt)
        }
        XCTAssertEqual(try Paarung.paareBilden(in: db), 0, "zweiter Lauf paart nichts neu")
    }

    func testPaarungRaetNicht() throws {
        let db = try Datenbank()
        func zahlung(_ id: String, _ konto: String, _ datum: String, _ cent: Int, _ haendler: String) -> Zahlung {
            Zahlung(id: id, quelle: .manuell, konto: konto, datum: Tag(iso: datum)!, betragCent: cent, haendler: haendler, zweck: nil,
                    fremdbetragCent: nil, fremdwaehrung: nil, karteLetzteVier: konto == "Amex" ? "2345" : nil, externId: nil,
                    kategorie: nil, zaehlt: true, gepaartMitId: nil, paarSicherheit: nil, herkunftsdatei: "test", herkunftsRef: nil)
        }
        try db.queue.write { d in
            // A: außerhalb des Fensters von 3 Tagen
            try zahlung("A1", "Amex", "2026-04-10", -5000, "PAYPAL *BAHNTEST").insert(d)
            try zahlung("P1", "PayPal", "2026-04-05", -5000, "Bahntest Vertrieb").insert(d)
            // B: zwei gleich hohe Zahlungen ohne Händlertreffer
            try zahlung("A2", "Amex", "2026-06-01", -200, "PAYPAL *UNBEKANNT").insert(d)
            try zahlung("P2", "PayPal", "2026-06-01", -200, "Fahrdienst BV").insert(d)
            try zahlung("P3", "PayPal", "2026-06-02", -200, "Parkhaus AG").insert(d)
            // C: ein einziger Kandidat ohne Händlertreffer → wahrscheinlich
            try zahlung("A3", "Amex", "2026-07-01", -1590, "PAYPAL *APPSTORETEST").insert(d)
            try zahlung("P4", "PayPal", "2026-07-02", -1590, "Apfel Dienste").insert(d)
            // D: zwei Händlertreffer → der zeitlich nächste, wahrscheinlich
            try zahlung("A4", "Amex", "2026-08-10", -1000, "PAYPAL *FAHRDIENST").insert(d)
            try zahlung("P5", "PayPal", "2026-08-08", -1000, "Fahrdienst BV").insert(d)
            try zahlung("P6", "PayPal", "2026-08-10", -1000, "Fahrdienst BV").insert(d)
        }
        XCTAssertEqual(try Paarung.paareBilden(in: db), 2)
        try db.queue.read { d in
            XCTAssertNil(try Zahlung.fetchOne(d, key: "A1")!.gepaartMitId)
            XCTAssertNil(try Zahlung.fetchOne(d, key: "A2")!.gepaartMitId)
            XCTAssertTrue(try Zahlung.fetchOne(d, key: "A2")!.zaehlt)
            let c = try Zahlung.fetchOne(d, key: "P4")!
            XCTAssertEqual(c.gepaartMitId, "A3")
            XCTAssertEqual(c.paarSicherheit, .wahrscheinlich)
            XCTAssertEqual(c.karteLetzteVier, "2345")
            XCTAssertEqual(try Zahlung.fetchOne(d, key: "A4")!.gepaartMitId, "P6")
            XCTAssertEqual(try Zahlung.fetchOne(d, key: "P6")!.paarSicherheit, .wahrscheinlich)
            XCTAssertNil(try Zahlung.fetchOne(d, key: "P5")!.gepaartMitId)
        }
    }

    func testHaendlermarke() {
        XCTAssertEqual(Paarung.haendlermarke("PAYPAL *TESTFLUGRE 4029357733"), "TESTFLUGRE")
        XCTAssertEqual(Paarung.haendlermarke("PAYPAL *MUSTER AG"), "MUSTERAG")
        XCTAssertTrue(Paarung.passt(marke: "TESTFLUGRE", name: "Testflug Reisen GmbH"))
        XCTAssertTrue(Paarung.passt(marke: "MUSTERAG", name: "Muster AG"))
        XCTAssertFalse(Paarung.passt(marke: "APPSTORETEST", name: "Apfel Dienste"))
    }
}
