import Foundation
import Testing
import SwiftData
@testable import Policenbuch

@MainActor
@Suite("Import in SwiftData")
struct ImportDienstTests {
    let bestand = """
    \u{FEFF}Versicherer;Sparte;Vertragsnummer;Beitrag;Zahlweise;Ablauf;Kündigungsfrist;Status;Extra
    Beispiel Leben AG;Rente;LV-123.456.78;150,00;monatlich;01.06.2028;3 Monate;aktiv;Wert A
    Muster Sach SE;Hausrat;HR 998877;1.234,56;jährlich;;3 Monate;aktiv;
    """

    let pay = """
    pay_id;konto;art;datum;richtung;betrag;gegenpartei;zweck
    P1;DKB;Lastschrift;02.01.2026;aus;150,00;Beispiel Leben;LV 123 456 78
    P2;DKB;Lastschrift;03.01.2026;aus;9,99;Shop;Bestellung
    """

    /// Container festhalten, damit der Kontext ihn nicht verliert.
    let container: ModelContainer

    init() throws {
        container = try Speicher.imSpeicher()
    }

    func kontext() throws -> ModelContext {
        ModelContext(container)
    }

    func bestandImportieren(_ k: ModelContext, text: String? = nil) throws {
        let e = try BestandImport.lesen(Data((text ?? bestand).utf8), dateiname: "versicherungsbestand_test.csv")
        try ImportDienst.uebernehmen(ImportDienst.vorschau(e, kontext: k), kontext: k)
    }

    @Test func bestandUndKeineDublettenBeimZweitenImport() throws {
        let k = try kontext()
        try bestandImportieren(k)
        try bestandImportieren(k)
        let vertraege = try k.fetch(FetchDescriptor<Vertrag>())
        #expect(vertraege.count == 2)
        let lv = try #require(vertraege.first { $0.sparte == "Rente" })
        #expect(lv.beitrag == 150)
        #expect(lv.zahlweise == .monatlich)
        #expect(lv.notizen.contains("Extra: Wert A"))
    }

    @Test func konfliktWirdZusammengefuehrt() throws {
        let k = try kontext()
        try bestandImportieren(k)
        let geaendert = bestand.replacingOccurrences(of: "150,00", with: "155,00")
        let e = try BestandImport.lesen(Data(geaendert.utf8))
        let v = ImportDienst.vorschau(e, kontext: k)
        #expect(v.abgleich.konflikte.count == 1)
        #expect(v.loesungen.values.allSatisfy { $0 == .zusammenfuehren })
        try ImportDienst.uebernehmen(v, kontext: k)
        let lv = try #require(try k.fetch(FetchDescriptor<Vertrag>()).first { $0.sparte == "Rente" })
        #expect(lv.beitrag == 150)
        #expect(lv.notizen.contains("Import abweichend – Beitrag: 155,00 €"))
    }

    @Test func zahlungenWerdenZugeordnetUndNichtDoppeltImportiert() throws {
        let k = try kontext()
        try bestandImportieren(k)
        _ = try ImportDienst.zahlungenImportieren(Data(pay.utf8), dateiname: "pay.csv", kontext: k)
        let zweiter = try ImportDienst.zahlungenImportieren(Data(pay.utf8), dateiname: "pay.csv", kontext: k)
        let zahlungen = try k.fetch(FetchDescriptor<Zahlung>())
        #expect(zahlungen.count == 2)
        #expect(zweiter.zeilen.contains("2 bereits vorhanden, übersprungen"))
        let p1 = try #require(zahlungen.first { $0.externeID == "nwo-pay:P1" })
        #expect(p1.vertrag?.vertragsnummer == "LV-123.456.78")
        #expect(p1.betrag == -150)
        #expect(zahlungen.first { $0.externeID == "nwo-pay:P2" }?.vertrag == nil)
    }

    @Test func zahlungenVorVertraegenWerdenNachtraeglichZugeordnet() throws {
        let k = try kontext()
        _ = try ImportDienst.zahlungenImportieren(Data(pay.utf8), dateiname: "pay.csv", kontext: k)
        #expect(try k.fetch(FetchDescriptor<Zahlung>()).allSatisfy { $0.vertrag == nil })
        try bestandImportieren(k)
        let p1 = try #require(try k.fetch(FetchDescriptor<Zahlung>()).first { $0.externeID == "nwo-pay:P1" })
        #expect(p1.vertrag != nil)
    }

    @Test func dokumentWirdPerTextZugeordnet() throws {
        let k = try kontext()
        try bestandImportieren(k)
        let d = ImportDienst.dokumentAnlegen(pfad: "/tmp/hausrat.pdf",
                                            text: "Beitragsrechnung\nVersicherungsschein-Nr. HR-998877\nDatum: 05.01.2026",
                                            kontext: k)
        #expect(d.vertrag?.sparte == "Hausrat")
        #expect(d.typ == .beitragsrechnung)
        #expect(d.datum == Datum.tag(2026, 1, 5))
        #expect(ImportDienst.dokumentVorhanden(pfad: "/tmp/hausrat.pdf", kontext: k))
    }

    @Test func speicherortIstLokal() {
        #expect(Speicher.ordner.path.hasSuffix("Library/Application Support/Policenbuch"))
    }
}
