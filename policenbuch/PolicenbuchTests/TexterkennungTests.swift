import Foundation
import Testing
import AppKit
import CoreText
import SwiftData
@testable import Policenbuch

/// Erzeugt erfundene Test-PDFs zur Laufzeit (keine echten Dokumente im Repository).
enum TestPDF {
    static let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)

    struct Fehler: Error {}

    /// PDF mit Textebene (wie ein vom Versicherer erzeugtes Dokument).
    static func mitText(_ zeilen: [String], nach url: URL) throws {
        var box = a4
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Fehler() }
        ctx.beginPDFPage(nil)
        zeichnen(zeilen, in: ctx, hoehe: a4.height, schrift: 14, rand: 50)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// PDF nur mit Bild, ohne Textebene (wie ein Scan) – zwingt die Vision-OCR.
    static func alsScan(_ zeilen: [String], nach url: URL) throws {
        let faktor: CGFloat = 200.0 / 72.0
        let breite = Int(a4.width * faktor), hoehe = Int(a4.height * faktor)
        guard let bitmap = CGContext(data: nil, width: breite, height: hoehe, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Fehler() }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: breite, height: hoehe))
        zeichnen(zeilen, in: bitmap, hoehe: CGFloat(hoehe), schrift: 14 * faktor, rand: 50 * faktor)
        guard let bild = bitmap.makeImage() else { throw Fehler() }

        var box = a4
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Fehler() }
        ctx.beginPDFPage(nil)
        ctx.draw(bild, in: a4)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    private static func zeichnen(_ zeilen: [String], in ctx: CGContext, hoehe: CGFloat, schrift: CGFloat, rand: CGFloat) {
        let font = NSFont(name: "Helvetica", size: schrift) ?? NSFont.systemFont(ofSize: schrift)
        for (i, zeile) in zeilen.enumerated() {
            let text = NSAttributedString(string: zeile, attributes: [.font: font, .foregroundColor: NSColor.black])
            let line = CTLineCreateWithAttributedString(text)
            ctx.textPosition = CGPoint(x: rand, y: hoehe - rand * 1.6 - CGFloat(i) * schrift * 1.8)
            CTLineDraw(line, ctx)
        }
    }
}

@MainActor
@Suite("Texterkennung (PDFKit und Vision)")
struct TexterkennungTests {
    let container: ModelContainer
    let ordner: URL

    init() throws {
        container = try Speicher.imSpeicher()
        ordner = FileManager.default.temporaryDirectory.appendingPathComponent("policenbuch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner.appendingPathComponent("Unterordner"), withIntermediateDirectories: true)
    }

    func bestand(_ k: ModelContext) throws {
        let csv = """
        Versicherer;Sparte;Vertragsnummer;Beitrag;Zahlweise
        Beispiel Leben AG;Rente;LV-123.456.78;150,00;monatlich
        Muster Sach SE;Hausrat;HR 998877;1.234,56;jährlich
        """
        let e = try BestandImport.lesen(Data(csv.utf8))
        try ImportDienst.uebernehmen(ImportDienst.vorschau(e, kontext: k), kontext: k)
    }

    @Test func textebeneWirdGelesen() throws {
        let url = ordner.appendingPathComponent("police.pdf")
        try TestPDF.mitText(["Beispiel Leben AG", "Versicherungsschein", "Versicherungsschein-Nr.: LV 123 456 78",
                             "Musterstadt, den 20.05.2008"], nach: url)
        let text = Texterkennung.text(aus: url)
        #expect(text.contains("Versicherungsschein-Nr.: LV 123 456 78"))

        let k = ModelContext(container)
        try bestand(k)
        let d = ImportDienst.dokumentAnlegen(pfad: url.path, text: text, kontext: k)
        #expect(d.vertrag?.sparte == "Rente")
        #expect(d.typ == .police)
        #expect(d.datum == Datum.tag(2008, 5, 20))
    }

    @Test func scanWirdPerOCRErkanntUndZugeordnet() throws {
        let url = ordner.appendingPathComponent("Unterordner/scan.pdf")
        try TestPDF.alsScan(["Muster Sach SE", "Beitragsrechnung 2026", "Versicherungsschein-Nr.: HR 998877",
                             "Datum: 05.01.2026", "Zu zahlen: 1.234,56 EUR"], nach: url)
        let text = Texterkennung.text(aus: url)
        #expect(text.localizedCaseInsensitiveContains("Beitragsrechnung"), "OCR-Text: \(text)")

        let k = ModelContext(container)
        try bestand(k)
        let d = ImportDienst.dokumentAnlegen(pfad: url.path, text: text, kontext: k)
        #expect(d.vertrag?.sparte == "Hausrat", "OCR-Text: \(text)")
        #expect(d.typ == .beitragsrechnung)
        #expect(d.datum == Datum.tag(2026, 1, 5))
    }

    @Test func ordnerWirdRekursivDurchsucht() throws {
        try TestPDF.mitText(["eins"], nach: ordner.appendingPathComponent("a.pdf"))
        try TestPDF.mitText(["zwei"], nach: ordner.appendingPathComponent("Unterordner/b.PDF"))
        try Data("kein pdf".utf8).write(to: ordner.appendingPathComponent("notiz.txt"))
        let gefunden = Texterkennung.pdfs(in: ordner).map(\.lastPathComponent)
        #expect(gefunden.contains("a.pdf"))
        #expect(gefunden.contains("b.PDF"))
        #expect(!gefunden.contains("notiz.txt"))
    }

    @Test func kaputteDateiLiefertLeerenText() throws {
        let url = ordner.appendingPathComponent("kaputt.pdf")
        try Data("kein pdf".utf8).write(to: url)
        #expect(Texterkennung.text(aus: url).isEmpty)
    }
}

@MainActor
@Suite("Sicherung und Vorschläge in SwiftData")
struct SicherungAppTests {
    let container: ModelContainer
    init() throws { container = try Speicher.imSpeicher() }

    let bestand = """
    Versicherer;Sparte;Vertragsnummer;Beitrag;Zahlweise
    Fiktiv Kranken VVaG;Krankenzusatz;KZ-55501;23,90;monatlich
    Muster Sach SE;Hausrat;HR 998877;1.234,56;jährlich
    """

    let pay = """
    pay_id;konto;art;datum;richtung;betrag;gegenpartei;zweck
    P1;DKB;Lastschrift;01.02.2026;aus;23,90;Fiktiv Kranken;Beitrag 02/2026
    P2;DKB;Lastschrift;03.02.2026;aus;9,99;Shop;Bestellung
    """

    func befuellen(_ k: ModelContext) throws {
        let e = try BestandImport.lesen(Data(bestand.utf8))
        try ImportDienst.uebernehmen(ImportDienst.vorschau(e, kontext: k), kontext: k)
        _ = try ImportDienst.zahlungenImportieren(Data(pay.utf8), dateiname: "pay.csv", kontext: k)
    }

    @Test func sichereVorschlaegeWerdenNurAufKlickUebernommen() throws {
        let k = ModelContext(container)
        try befuellen(k)
        #expect(try k.fetch(FetchDescriptor<Zahlung>()).allSatisfy { $0.vertrag == nil })
        let v = ImportDienst.vorschlaege(kontext: k)
        #expect(v.count == 1)
        #expect(try ImportDienst.sichereVorschlaegeUebernehmen(kontext: k) == 1)
        let p1 = try #require(try k.fetch(FetchDescriptor<Zahlung>()).first { $0.externeID == "nwo-pay:P1" })
        #expect(p1.vertrag?.sparte == "Krankenzusatz")
    }

    @Test func sicherungUndWiederherstellung() throws {
        let k = ModelContext(container)
        try befuellen(k)
        let hausrat = try #require(ImportDienst.alleVertraege(k).first { $0.sparte == "Hausrat" })
        let hausratID = hausrat.id
        k.insert(Aufgabe(titel: "Angebote vergleichen", faelligkeit: Datum.tag(2026, 12, 1), vertrag: hausrat))
        k.insert(Dokument(pfad: "/tmp/x.pdf", typ: .police, datum: nil, vertrag: hausrat, erkannterText: "Text", kandidaten: ["HR 998877"]))
        try k.save()
        let sicherung = try ImportDienst.sicherung(kontext: k)
        let json = try sicherung.json()

        // Bestand verändern, dann wiederherstellen
        hausrat.notizen = "geändert"
        k.insert(Vertrag(VertragsDaten(versicherer: "Neu", vertragsnummer: "77777")))
        try k.save()
        try ImportDienst.wiederherstellen(try Sicherung.lesen(json), kontext: k)

        let vertraege = ImportDienst.alleVertraege(k)
        #expect(vertraege.count == 2)
        let wieder = try #require(vertraege.first { $0.sparte == "Hausrat" })
        #expect(wieder.id == hausratID)
        #expect(wieder.notizen.isEmpty)
        #expect(wieder.aufgaben.map(\.titel) == ["Angebote vergleichen"])
        #expect(wieder.dokumente.first?.kandidaten == "HR 998877")
        #expect(try k.fetch(FetchDescriptor<Zahlung>()).count == 2)
    }
}
