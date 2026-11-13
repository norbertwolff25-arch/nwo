import XCTest
import GRDB
@testable import ReisemanagerKern

/// Nachgestelltes Concur für Tests. Es kennt, wie die echte Schnittstelle, kein Senden.
final class TestConcur: ConcurZugang {
    var bestand: ConcurBestand
    var ausgefuehrt: [ConcurSchritt] = []
    var fehlerBei: ConcurSchritt.Art?
    private var zaehler = 0
    struct Ausfall: Error {}

    init(_ bestand: ConcurBestand = ConcurBestand(gelesenAm: nil, abrechnungen: [], verfuegbareAusgaben: nil)) { self.bestand = bestand }

    func lesen() throws -> ConcurBestand { bestand }

    func ausfuehren(_ schritt: ConcurSchritt, concurNr: String?) throws -> String? {
        if schritt.art == fehlerBei { throw Ausfall() }
        ausgefuehrt.append(schritt)
        if schritt.art == .kopfAnlegen {
            zaehler += 1
            return "NEU\(zaehler)"
        }
        return nil
    }
}

final class ConcurTests: XCTestCase {
    func t(_ iso: String) -> Tag { Tag(iso: iso)! }

    let einstellungen = Einstellungen(
        jahr: 2026, privatadresse: .init(strasse: "Musterweg 1", plz: "00000", ort: "Heimstadt"),
        concur: .init(anmeldung: "a@b.example", instanz: "https://example.invalid", logicalSystem: "System A", companyCode: "Firma B",
                      businessArea: "Bereich C", costObjectType: "Typ D", costObjectId: "Objekt E"),
        belegordner: nil, wiedervorlageTage: 30,
        ausgabentypen: ["bahn": "Bahnfahrt", "hotel": "Hotel", "taxi": "Taxi", "sonstiges": "Sonstiges", "fahrt": "Fahrtkosten"])

    func reise(_ id: String, _ anlass: String, _ von: String, _ bis: String, nr: String? = nil, titel: String? = nil, ort: String? = nil) -> Reise {
        Reise(id: id, art: .dienstreise, typ: nil, anlass: anlass, ort: ort, istStammeinsatz: false,
              beginn: t(von), beginnZeit: nil, beginnQuelle: nil, beginnSicherheit: .wahrscheinlich,
              ende: t(bis), endeZeit: nil, endeQuelle: nil, endeSicherheit: .wahrscheinlich,
              verkehrsmittel: nil, unterkunft: nil, hinweis: nil, status: nr == nil ? .erkannt : .concurEntwurf, concurNr: nr, concurTitel: titel)
    }

    @discardableResult
    func position(_ d: Database, _ reiseId: String, _ datum: String, _ art: Kostenart, _ haendler: String, _ cent: Int?) throws -> Int64 {
        var p = Position(id: nil, reiseId: reiseId, sachkostenId: nil, datum: t(datum), quelle: "Amex", kostenart: art, kostenartText: nil,
                         haendler: haendler, ort: nil, betragCent: cent, fremdbetragCent: nil, fremdwaehrung: nil, zahlungId: nil,
                         privatVorgestreckt: true, erstattung: .offen, vorauskauf: false, belegHinweis: nil, vorschlag: nil, concurErfasstIn: nil)
        try p.insert(d)
        return p.id!
    }

    /// D01 hat schon einen Entwurf. Eine Position steht dort, eine in der Monatsabrechnung, eine liegt als verfügbare Ausgabe vor.
    func bestand() throws -> (Datenbank, TestConcur) {
        let db = try Datenbank()
        try db.queue.write { d in
            try reise("D01", "Einsatz Oststadt", "2026-07-20", "2026-07-23", nr: "ABC123", titel: "Einsatz Oststadt 20.-23.07.26", ort: "Oststadt").insert(d)
            try position(d, "D01", "2026-06-26", .fahrt, "DB Vertrieb", 15478)        // schon im Entwurf
            try position(d, "D01", "2026-07-20", .unterkunft, "MERCURE OSTSTADT", 27960) // in „Ausgaben im Juli“
            try position(d, "D01", "2026-07-20", .fahrt, "BOLT OPERATIONS", 1290)      // verfügbare Ausgabe
            try position(d, "D01", "2026-07-23", .fahrt, "BOLT OPERATIONS", 990)       // neu
            try position(d, "D01", "2026-07-21", .sonstiges, "Tagungsgebühr", nil)     // ohne Betrag
            try Beleg(id: "B01", dokument: "Bolt-Quittung", art: nil, fundort: nil, belegt: nil, status: nil).insert(d)
            var bild = Belegbild(id: nil, pfad: "B01_Bolt.pdf", sha256: "x", groesse: 1, dubletteVonId: nil)
            try bild.insert(d)
            try BelegbildBeleg(belegbildId: bild.id!, belegId: "B01").insert(d)
            let neu = try XCTUnwrap(Position.filter(Column("betragCent") == 990).fetchOne(d))
            try PositionBeleg(positionId: neu.id!, belegId: "B01").insert(d)
        }
        let concur = TestConcur(ConcurBestand(gelesenAm: "2026-11-13", abrechnungen: [
            .init(nr: "ABC123", titel: "Einsatz Oststadt 20.-23.07.26", status: "Entwurf", betragCent: 15478,
                  positionen: [.init(datum: t("2026-06-26"), ausgabentyp: "Bahnfahrt", lieferant: "DB", betragCent: 15478, hatBeleg: true)]),
            .init(nr: "JULI01", titel: "Ausgaben im Juli", status: "Entwurf", betragCent: 27960,
                  positionen: [.init(datum: t("2026-07-21"), ausgabentyp: "Hotel", lieferant: "Mercure", betragCent: 27960)]),
        ], verfuegbareAusgaben: [.init(datum: t("2026-07-20"), ausgabentyp: nil, lieferant: "Bolt", betragCent: 1290)]))
        try concur.lesen().uebernehmen(in: db)
        return (db, concur)
    }

    func testAbgleichMitMonatsabrechnungUndVerfuegbarenAusgaben() throws {
        let (db, _) = try bestand()
        let abgleich = try ConcurAbgleich.abgleichen(in: db)
        XCTAssertEqual(abgleich.map(\.art), [.schonErfasst, .inAndererAbrechnung, .verfuegbareAusgabe, .neu, .ohneBetrag])
        XCTAssertEqual(abgleich[1].concurNr, "JULI01")
        XCTAssertTrue(abgleich[1].text.contains("Ausgaben im Juli") && abgleich[1].text.contains("nicht doppelt"))
        XCTAssertEqual(try db.queue.read { try ConcurPosition.fetchCount($0) }, 3)

        // Ein Concur-Eintrag deckt nur eine eigene Position: Zwei gleiche Fahrten brauchen zwei Einträge.
        try db.queue.write { try self.position($0, "D01", "2026-07-20", .fahrt, "BOLT OPERATIONS", 1290) }
        XCTAssertEqual(try ConcurAbgleich.abgleichen(in: db).last?.art, .neu)
    }

    func testPlanIstVorschauUndSchreibtNichtsDoppelt() throws {
        let (db, _) = try bestand()
        let plan = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        XCTAssertEqual(plan.concurNr, "ABC123")
        XCTAssertEqual(plan.schritte.map(\.art), [.verfuegbareAusgabeZuordnen, .positionErfassen, .belegHochladen])
        XCTAssertFalse(plan.schritte.contains { $0.art == .kopfAnlegen }, "Entwurf besteht schon")
        let erfassen = try XCTUnwrap(plan.schritte.first { $0.art == .positionErfassen })
        XCTAssertEqual(erfassen.wert("Ausgabentyp"), "Taxi")
        XCTAssertEqual(erfassen.wert("Betrag"), "9,90")
        XCTAssertEqual(erfassen.wert("Datum"), "2026-07-23")
        XCTAssertEqual(erfassen.wert("Zahlungsart"), "privat vorgestreckt")
        XCTAssertEqual(plan.schritte.last?.wert("Datei"), "B01_Bolt.pdf")
        XCTAssertTrue(plan.hinweise.contains { $0.contains("Ausgaben im Juli") })
        XCTAssertTrue(plan.hinweise.contains { $0.contains("Tagungsgebühr") && $0.contains("ohne Betrag") })
        XCTAssertTrue(plan.hinweise.contains { $0.contains("Uhrzeiten") }, "Reiseverlauf erst mit Uhrzeiten")
        XCTAssertEqual(plan.blocker, [])
        XCTAssertTrue(plan.istAusfuehrbar)
        XCTAssertEqual(plan.hash, try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen).hash, "gleicher Plan, gleiche Prüfsumme")
    }

    func testOhneVorschauWirdNichtGeschrieben() throws {
        let (db, concur) = try bestand()
        let plan = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        XCTAssertThrowsError(try ConcurLauf.ausfuehren(in: db, plan: plan, zugang: concur, einstellungen: einstellungen)) {
            XCTAssertEqual($0 as? ConcurLauf.Fehler, .vorschauFehlt("D01"))
        }
        XCTAssertEqual(concur.ausgefuehrt.count, 0)

        try ConcurLauf.freigeben(in: db, plan: plan, stapel: false)
        XCTAssertEqual(try ConcurLauf.ausfuehren(in: db, plan: plan, zugang: concur, einstellungen: einstellungen), 3)
        XCTAssertEqual(concur.ausgefuehrt.map(\.art), [.verfuegbareAusgabeZuordnen, .positionErfassen, .belegHochladen])
        try db.queue.read { d in
            XCTAssertEqual(try Position.filter(Column("concurErfasstIn") == "ABC123").fetchCount(d), 2)
            XCTAssertEqual(try Reise.fetchOne(d, key: "D01")!.status, .concurPositionen)
            XCTAssertEqual(try ConcurProtokolleintrag.filter(Column("bezug") == "D01" && Column("ergebnis") == "ok").fetchCount(d), 3)
        }

        // Zweiter Lauf: Der alte Plan ist veraltet, der neue hat nichts mehr zu tun.
        XCTAssertThrowsError(try ConcurLauf.ausfuehren(in: db, plan: plan, zugang: concur, einstellungen: einstellungen)) {
            XCTAssertEqual($0 as? ConcurLauf.Fehler, .planVeraltet("D01"))
        }
        let danach = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        XCTAssertEqual(danach.schritte, [])
        XCTAssertFalse(danach.istAusfuehrbar)
        XCTAssertEqual(concur.ausgefuehrt.count, 3)
    }

    func testFreigabeGiltNurFuerDiesenPlanAusserImStapel() throws {
        let (db, concur) = try bestand()
        let plan = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        try ConcurLauf.freigeben(in: db, plan: plan, stapel: false)

        // Neue Position: Der Plan ändert sich, die alte Freigabe trägt nicht mehr.
        try db.queue.write { try self.position($0, "D01", "2026-07-22", .fahrt, "Taxi Ost", 1500) }
        let geaendert = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        XCTAssertNotEqual(geaendert.hash, plan.hash)
        XCTAssertFalse(try ConcurLauf.darfSchreiben(in: db, plan: geaendert))
        XCTAssertThrowsError(try ConcurLauf.ausfuehren(in: db, plan: geaendert, zugang: concur, einstellungen: einstellungen))

        // Modus „Stapel“: Nach der ersten Vorschau laufen weitere Schreibvorgänge ohne Rückfrage.
        try ConcurLauf.freigeben(in: db, plan: geaendert, stapel: true)
        try db.queue.write { try self.position($0, "D01", "2026-07-22", .fahrt, "Taxi West", 1700) }
        let spaeter = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        XCTAssertTrue(try ConcurLauf.darfSchreiben(in: db, plan: spaeter))
        XCTAssertEqual(try ConcurLauf.ausfuehren(in: db, plan: spaeter, zugang: concur, einstellungen: einstellungen), 5)
    }

    func testNeueAbrechnungMitKopfUndReiseverlauf() throws {
        let db = try Datenbank()
        try db.queue.write { d in
            var r = self.reise("D02", "Messe", "2026-10-27", "2026-10-28", ort: "Nordstadt")
            r.beginnZeit = "07:10"; r.endeZeit = "18:45"
            try r.insert(d)
            try self.position(d, "D02", "2026-10-27", .unterkunft, "Hotel Nord", 9900)
            var a = Reiseabschnitt(id: nil, reiseId: "D02", reihenfolge: 1, art: "vorlauf", von: "Privatadresse", nach: "Hbf",
                                   abfahrt: "2026-10-27 07:10", ankunft: "2026-10-27 07:35", verkehrsmittel: "Taxi", quelle: nil, sicherheit: .sicher)
            try a.insert(d)
            try Sachkostenabrechnung(id: "S1", titel: "Sachkosten Software", hinweis: "Abo", status: .erkannt, concurNr: nil, concurTitel: nil).insert(d)
        }
        let concur = TestConcur()
        // Ohne gelesenen Concur-Stand wird nichts geschrieben: Es könnte dort schon ein Entwurf liegen.
        let ungelesen = try ConcurPlanung.plan(in: db, bezug: "D02", einstellungen: einstellungen)
        XCTAssertTrue(ungelesen.blocker.contains { $0.hasPrefix("Concur-Stand noch nicht gelesen") })
        XCTAssertNil(try ConcurBestand.zuletztGelesen(in: db))
        try concur.lesen().uebernehmen(in: db)
        XCTAssertNotNil(try ConcurBestand.zuletztGelesen(in: db))
        let plan = try ConcurPlanung.plan(in: db, bezug: "D02", einstellungen: einstellungen)
        XCTAssertEqual(plan.titel, "Messe Nordstadt 27.-28.10.26")
        XCTAssertEqual(plan.schritte.map(\.art), [.kopfAnlegen, .reiseverlaufSetzen, .positionErfassen])
        let kopf = plan.schritte[0]
        XCTAssertEqual(kopf.wert("Titel"), "Messe Nordstadt 27.-28.10.26")
        XCTAssertEqual(kopf.wert("Company Code"), "Firma B")
        XCTAssertEqual(kopf.wert("Cost Object ID"), "Objekt E")
        XCTAssertEqual(kopf.wert("Tagespauschalen"), "ja")
        let verlauf = plan.schritte[1]
        XCTAssertEqual(verlauf.wert("Abreise"), "Musterweg 1, 00000 Heimstadt")
        XCTAssertEqual(verlauf.wert("Ankunft"), "Musterweg 1, 00000 Heimstadt")
        XCTAssertEqual(verlauf.wert("Beginn"), "2026-10-27 07:10")
        XCTAssertTrue(verlauf.wert("Abschnitt 1")!.hasPrefix("vorlauf: Privatadresse"))
        XCTAssertTrue(plan.hinweise.contains { $0.contains("ohne Belegbild") })

        try ConcurLauf.freigeben(in: db, plan: plan, stapel: false)
        XCTAssertEqual(try ConcurLauf.ausfuehren(in: db, plan: plan, zugang: concur, einstellungen: einstellungen), 3)
        try db.queue.read { d in
            let r = try Reise.fetchOne(d, key: "D02")!
            XCTAssertEqual(r.concurNr, "NEU1")
            XCTAssertEqual(r.concurTitel, "Messe Nordstadt 27.-28.10.26")
            XCTAssertEqual(r.status, .concurPositionen)
            XCTAssertEqual(try Position.fetchOne(d)!.concurErfasstIn, "NEU1")
        }
        XCTAssertEqual(try ConcurPlanung.plan(in: db, bezug: "D02", einstellungen: einstellungen).schritte, [], "Kopf und Reiseverlauf entstehen nicht doppelt")

        // Sachkosten: ohne Tagespauschalen und ohne Reiseverlauf.
        let sach = try ConcurPlanung.plan(in: db, bezug: "S1", einstellungen: einstellungen)
        XCTAssertEqual(sach.schritte.map(\.art), [.kopfAnlegen])
        XCTAssertEqual(sach.schritte[0].wert("Tagespauschalen"), "nein")
        XCTAssertThrowsError(try ConcurPlanung.plan(in: db, bezug: "D99", einstellungen: einstellungen))
    }

    func testBlockerVerhindernDasSchreiben() throws {
        let db = try Datenbank()
        try db.queue.write { d in
            try self.reise("D03", "Fachkonferenz Agenten Europa", "2026-09-16", "2026-09-19", ort: "Rotterdam").insert(d)
            try self.position(d, "D03", "2026-09-16", .verpflegung, "Bistro", 1200)
            var privat = self.reise("P01", "Urlaub", "2026-07-01", "2026-07-10")
            privat.art = .privat
            try privat.insert(d)
        }
        try TestConcur().lesen().uebernehmen(in: db)
        let plan = try ConcurPlanung.plan(in: db, bezug: "D03", einstellungen: einstellungen)
        XCTAssertTrue(plan.blocker.contains { $0.hasPrefix("Titel hat") && $0.contains("kürzeren Anlass") }, "\(plan.blocker)")
        XCTAssertTrue(plan.blocker.contains { $0.contains("Ausgabentyp für „verpflegung“") }, "Ausgabentypen werden nicht geraten: \(plan.blocker)")
        XCTAssertFalse(plan.istAusfuehrbar)
        XCTAssertThrowsError(try ConcurLauf.freigeben(in: db, plan: plan, stapel: true))
        XCTAssertThrowsError(try ConcurLauf.ausfuehren(in: db, plan: plan, zugang: TestConcur(), einstellungen: einstellungen))

        let ohne = try ConcurPlanung.plan(in: db, bezug: "D03", einstellungen: nil)
        XCTAssertTrue(ohne.blocker.contains("Einstellungen fehlen: Concur-Kopfdaten"))
        XCTAssertTrue(try ConcurPlanung.plan(in: db, bezug: "P01", einstellungen: einstellungen).blocker.contains { $0.contains("Privatreise") })
    }

    func testVorhandenerEntwurfWirdNichtDoppeltAngelegt() throws {
        let db = try Datenbank()
        try db.queue.write { d in
            // Entwurf liegt in Concur, die Nummer ist lokal noch unbekannt.
            try self.reise("D05", "Einsatz Weststadt", "2026-07-20", "2026-07-23", nr: nil, titel: "Einsatz Weststadt 20.-23.07.26").insert(d)
            try self.position(d, "D05", "2026-07-20", .fahrt, "BOLT OPERATIONS", 1290)
            var punkt = OffenerPunkt(id: nil, reiseId: "D05", sachkostenId: nil, text: "Concur-Nummer prüfen", fundort: "Concur", erledigt: false, herkunft: nil)
            try punkt.insert(d)
            // Zweite Reise: gleicher Titel wie ein Concur-Entwurf, aber lokal ohne gespeicherten Concur-Titel.
            try self.reise("D06", "Messe", "2026-10-27", "2026-10-28", ort: "Nordstadt").insert(d)
        }
        let concur = TestConcur(ConcurBestand(gelesenAm: "2026-11-13", abrechnungen: [
            .init(nr: "XYZ789", titel: "Einsatz Weststadt 20.-23.07.26", status: "Entwurf", betragCent: 0, positionen: []),
            .init(nr: "MES001", titel: "Messe Nordstadt 27.-28.10.26", status: "Entwurf", betragCent: 0, positionen: []),
        ], verfuegbareAusgaben: nil))
        let ergebnis = try concur.lesen().uebernehmen(in: db)
        XCTAssertEqual(ergebnis.zusammengefuehrt, 1)
        try db.queue.read { d in
            XCTAssertEqual(try Reise.fetchOne(d, key: "D05")!.concurNr, "XYZ789", "Nummer über den Titel übernommen")
            XCTAssertEqual(try OffenerPunkt.filter(Column("erledigt") == false).fetchCount(d), 0)
            XCTAssertEqual(try Entscheidung.filter(Column("feld") == "concurNr").fetchCount(d), 1)
        }
        let plan = try ConcurPlanung.plan(in: db, bezug: "D05", einstellungen: einstellungen)
        XCTAssertEqual(plan.concurNr, "XYZ789")
        XCTAssertEqual(plan.schritte.map(\.art), [.positionErfassen], "kein zweiter Entwurf")
        XCTAssertEqual(plan.blocker, [])

        let messe = try ConcurPlanung.plan(in: db, bezug: "D06", einstellungen: einstellungen)
        XCTAssertTrue(messe.blocker.contains { $0.contains("MES001") && $0.contains("Nummer zuordnen") }, "\(messe.blocker)")
        XCTAssertFalse(messe.istAusfuehrbar)
    }

    func testFehlerBrichtAbUndWirdProtokolliert() throws {
        let (db, concur) = try bestand()
        concur.fehlerBei = .positionErfassen
        let plan = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        try ConcurLauf.freigeben(in: db, plan: plan, stapel: false)
        XCTAssertThrowsError(try ConcurLauf.ausfuehren(in: db, plan: plan, zugang: concur, einstellungen: einstellungen))
        XCTAssertEqual(concur.ausgefuehrt.map(\.art), [.verfuegbareAusgabeZuordnen], "nach dem Fehler läuft nichts weiter")
        try db.queue.read { d in
            XCTAssertEqual(try ConcurProtokolleintrag.filter(Column("ergebnis").like("Fehler%")).fetchCount(d), 1)
            XCTAssertEqual(try Reise.fetchOne(d, key: "D01")!.status, .concurEntwurf)
        }
    }

    func testSendenGibtEsNichtUndLoeschenNurMitBestaetigung() throws {
        let (db, concur) = try bestand()
        XCTAssertNil(ConcurSchritt.Art(rawValue: "senden"))
        XCTAssertNil(ConcurSchritt.Art(rawValue: "einreichen"))
        XCTAssertTrue(ConcurRegeln.verboteneBeschriftungen.contains("Abrechnung senden"))

        // Der Browserzugang liest dieselbe Liste: Kern und Skript dürfen nicht auseinanderlaufen.
        struct Regeldatei: Decodable { var verboteneBeschriftungen: [String] }
        let datei = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("concur/regeln.json")
        let regeln = try JSONDecoder().decode(Regeldatei.self, from: Data(contentsOf: datei))
        XCTAssertEqual(regeln.verboteneBeschriftungen, ConcurRegeln.verboteneBeschriftungen)

        let felder = [ConcurSchritt.Feld(name: "Position", wert: "Bolt 12,90")]
        XCTAssertThrowsError(try ConcurLauf.loeschen(in: db, zugang: concur, bezug: "D01", concurNr: "ABC123", beschreibung: "Position löschen",
                                                     felder: felder, ausdruecklichBestaetigt: false)) {
            XCTAssertEqual($0 as? ConcurLauf.Fehler, .loeschenNichtBestaetigt)
        }
        XCTAssertEqual(concur.ausgefuehrt.count, 0)
        try ConcurLauf.loeschen(in: db, zugang: concur, bezug: "D01", concurNr: "ABC123", beschreibung: "Position löschen", felder: felder,
                                ausdruecklichBestaetigt: true)
        XCTAssertEqual(concur.ausgefuehrt.map(\.art), [.loeschen])

        // Ein Plan mit Löschschritt wird nie ausgeführt, auch nicht mit Freigabe.
        var plan = try ConcurPlanung.plan(in: db, bezug: "D01", einstellungen: einstellungen)
        try ConcurLauf.freigeben(in: db, plan: plan, stapel: true)
        plan.schritte.append(ConcurSchritt(art: .loeschen, bezug: "D01", positionId: nil, felder: [], beschreibung: "eingeschleust"))
        XCTAssertThrowsError(try ConcurLauf.ausfuehren(in: db, plan: plan, zugang: concur, einstellungen: einstellungen)) {
            XCTAssertEqual($0 as? ConcurLauf.Fehler, .loeschenImPlan)
        }
    }
}
