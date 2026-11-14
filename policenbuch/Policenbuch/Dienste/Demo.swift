import SwiftUI
import SwiftData
import AppKit
import CoreText

/// Demo- und Screenshot-Modus: `Policenbuch -PolicenbuchDemo <Ausgabeordner>`.
/// Arbeitet ausschließlich mit einem Speicher im Arbeitsspeicher und erfundenen Daten,
/// fasst den echten Bestand nie an, nimmt jede Ansicht als PNG auf und beendet sich danach.
enum Demo {
    static let argument = "-PolicenbuchDemo"

    static var ausgabeordner: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static var aktiv: Bool { ausgabeordner != nil }

    // MARK: Erfundene Daten

    static let bestand = """
    Versicherer;Sparte;Vertragsnummer;Tarif;Beginn;Ablauf;Kündigungsfrist;Beitrag;Zahlweise;Dynamik %;Status;Steuerliche Einordnung;Betreuer;Bemerkung
    Beispiel Leben AG;Rentenversicherung;LV-123.456.78;Basisrente Klassik;01.06.2008;01.06.2028;3 Monate;150,00;monatlich;5,0;aktiv;Schicht 1 (Basisrente);Clark;Kapitalauszahlung 06/2028
    Muster Sach SE;Hausrat;HR 998877;Komfort;15.03.2019;;3 Monate zum Ablauf;98,40;jährlich;;aktiv;;direkt;Wohnung inkl. Fahrrad
    Muster Sach SE;Haftpflicht;PH-4711-22;Single;01.10.2015;;3 Monate;69,50;jährlich;;aktiv;;Clark;
    Fiktiv Kranken VVaG;Krankenzusatz;KZ-55501;Zahn 90;01.01.2021;;1 Monat;23,90;monatlich;;aktiv;Vorsorgeaufwand;Clark;
    Erfunden Rechtsschutz AG;Rechtsschutz;RS-2020-777;Privat Plus;01.02.2020;;3 Monate;312,40;jährlich;;prüfen;;Clark;Beitrag nach Anpassung prüfen
    Beispiel Leben AG;Berufsunfähigkeit;BU-555-01;BU Premium;01.04.2012;01.04.2047;3 Monate;61,20;monatlich;3,0;aktiv;Vorsorgeaufwand;neu;
    Musterkasse Auto;Kfz;KFZ-2026/0815;Kasko;01.01.2024;;1 Monat;412,00;halbjährlich;;aktiv;;direkt;
    Alte Leben AG;Kapitallebensversicherung;KL-1999-42;Klassik;01.12.1999;01.12.2024;;45,00;monatlich;;beendet;Altvertrag;direkt;ausgezahlt
    """

    static let clark = """
    {"contracts": [
      {"id": 9001, "contract_number": "LV12345678", "insurer": {"name": "Beispiel Leben AG", "bafin_id": "1234"},
       "category": {"name": "Rentenversicherung"}, "premium": {"amount": 155.0, "currency": "EUR"},
       "payment_interval": "monthly", "state": "active", "start_date": "2008-06-01", "advisor_comment": "Dynamik 5 %"},
      {"id": 9003, "contract_number": "TI-31415", "insurer": {"name": "Erfunden Tier AG"},
       "category": {"name": "Tierhalterhaftpflicht"}, "premium": {"amount": 59.0, "currency": "EUR"},
       "payment_interval": "yearly", "state": "active"}
    ]}
    """

    static var zahlungen: String {
        var zeilen = ["pay_id;konto;art;datum;richtung;betrag;gegenpartei;zweck"]
        var n = 0
        func z(_ datum: String, _ betrag: String, _ gegen: String, _ zweck: String, richtung: String = "aus") {
            n += 1
            zeilen.append("D-\(n);DKB Giro;Lastschrift;\(datum);\(richtung);\(betrag);\(gegen);\(zweck)")
        }
        for jahr in 2023...2026 {
            let lv = ["2023": "136,08", "2024": "142,88", "2025": "150,00", "2026": "150,00"]["\(jahr)"]!
            for monat in 1...(jahr == 2026 ? 10 : 12) {
                z(String(format: "01.%02d.%d", monat, jahr), lv, "Beispiel Leben AG", "Beitrag LV 123 456 78")
                z(String(format: "02.%02d.%d", monat, jahr), "61,20", "Beispiel Leben AG", "BU-555-01 Beitrag")
                z(String(format: "03.%02d.%d", monat, jahr), "23,90", "Fiktiv Kranken", "Beitrag \(monat)/\(jahr)")
            }
            z("15.03.\(jahr)", "98,40", "Muster Sach SE", "Vers.-Nr. HR-998877 Jahresbeitrag")
            z("01.01.\(jahr)", "412,00", "Musterkasse Auto", "KFZ-2026/0815 1. Halbjahr")
            z("01.07.\(jahr)", "412,00", "Musterkasse Auto", "KFZ-2026/0815 2. Halbjahr")
        }
        z("10.04.2026", "80,00", "Fiktiv Kranken", "Erstattung KZ-55501 Zahnreinigung", richtung: "ein")
        z("12.04.2026", "9,99", "Streamingdienst", "Abo 1998877123")
        z("20.05.2026", "59,00", "Erfunden Tier AG", "Jahresbeitrag Hund")
        return zeilen.joined(separator: "\n")
    }

    @MainActor
    static func befuellen(_ k: ModelContext, dokumentordner: URL) throws {
        let bestandImport = try BestandImport.lesen(Data(bestand.utf8), dateiname: "versicherungsbestand_demo.csv")
        try ImportDienst.uebernehmen(ImportDienst.vorschau(bestandImport, kontext: k), kontext: k)
        _ = try ImportDienst.zahlungenImportieren(Data(zahlungen.utf8), dateiname: "nwo_pay_demo.csv", kontext: k)

        try FileManager.default.createDirectory(at: dokumentordner, withIntermediateDirectories: true)
        let pdfs: [(String, [String])] = [
            ("Police_Rente.pdf", ["Beispiel Leben AG", "Versicherungsschein", "Versicherungsschein-Nr.: LV 123 456 78", "Musterstadt, den 20.05.2008"]),
            ("Jahresbescheinigung_2025.pdf", ["Beispiel Leben AG", "Jahresbescheinigung 2025 zur Vorlage beim Finanzamt",
                                              "Vertragsnummer: LV-123.456.78", "Datum: 15.01.2026"]),
            ("Beitragsrechnung_Hausrat.pdf", ["Muster Sach SE", "Beitragsrechnung 2026", "Versicherungsschein-Nr.: HR 998877", "Datum: 05.01.2026"]),
            ("Nachtrag_Kfz.pdf", ["Musterkasse Auto", "Nachtrag zum Versicherungsschein", "Vertragsnummer: KFZ-2026/0815", "vom 01.02.2026"]),
            ("Unbekannt.pdf", ["Erfunden Tier AG", "Versicherungsschein", "Policennummer: TI-31415", "Datum: 01.05.2026"])
        ]
        for (name, zeilen) in pdfs {
            let url = dokumentordner.appendingPathComponent(name)
            try textPDF(zeilen, nach: url)
            ImportDienst.dokumentAnlegen(pfad: url.path, text: Texterkennung.text(aus: url), kontext: k)
        }
        let rs = ImportDienst.alleVertraege(k).first { $0.sparte == "Rechtsschutz" }
        k.insert(Aufgabe(titel: "Angebot für Rechtsschutz vergleichen", faelligkeit: Datum.tag(2026, 11, 30), vertrag: rs))
        k.insert(Aufgabe(titel: "Unterlagen an neuen Berater schicken", faelligkeit: Datum.tag(2026, 12, 10), vertrag: nil))
        try k.save()
    }

    static func textPDF(_ zeilen: [String], nach url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil)
        let font = NSFont(name: "Helvetica", size: 14) ?? NSFont.systemFont(ofSize: 14)
        for (i, zeile) in zeilen.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: zeile, attributes: [.font: font]))
            ctx.textPosition = CGPoint(x: 50, y: 760 - CGFloat(i) * 26)
            CTLineDraw(line, ctx)
        }
        ctx.endPDFPage()
        ctx.closePDF()
    }

    // MARK: Aufnahmen

    @MainActor
    static func ablauf(navigation: Navigation, kontext: ModelContext) async {
        guard let ordner = ausgabeordner else { return }
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))
        guard let fenster = hauptfenster() else { NSApp.terminate(nil); return }
        fenster.setContentSize(NSSize(width: 1280, height: 820))
        fenster.center()

        var nr = 1
        func aufnahme(_ name: String, _ f: NSWindow) async {
            try? await Task.sleep(for: .seconds(1.5))
            aufnehmen(f, nach: ordner.appendingPathComponent(String(format: "%02d-%@.png", nr, name)))
            nr += 1
        }

        for b in Bereich.allCases {
            navigation.bereich = b
            await aufnahme(b.rawValue, fenster)
        }
        if let lv = ImportDienst.alleVertraege(kontext).first(where: { $0.sparte == "Rentenversicherung" }) {
            navigation.oeffne(lv)
            await aufnahme("vertragsdetail", fenster)
        }

        // Import-Dialoge in eigenen Fenstern
        if let roh = try? ClarkImport.lesen(Data(clark.utf8), dateiname: "clark_export_demo.json") {
            let zuordnung = NSWindow(contentViewController: NSHostingController(rootView: FeldzuordnungView(roh: roh) { _ in }))
            zuordnung.setContentSize(NSSize(width: 900, height: 560))
            zuordnung.makeKeyAndOrderFront(nil)
            await aufnahme("clark-zuordnung", zuordnung)
            zuordnung.close()

            let vorschau = ImportDienst.vorschau(roh.importieren(mit: .automatisch(fuer: roh.felder)), kontext: kontext)
            let konflikt = NSWindow(contentViewController: NSHostingController(rootView: ImportVorschauView(vorschau: vorschau) { _ in }))
            konflikt.setContentSize(NSSize(width: 900, height: 620))
            konflikt.makeKeyAndOrderFront(nil)
            await aufnahme("import-konflikte", konflikt)
            konflikt.close()
        }
        NSApp.terminate(nil)
    }

    @MainActor
    static func hauptfenster() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil }
    }

    /// Nimmt nur das eigene Fenster auf (keine Bildschirmaufnahme-Berechtigung nötig).
    @MainActor
    static func aufnehmen(_ fenster: NSWindow, nach url: URL) {
        guard let view = fenster.contentView?.superview ?? fenster.contentView else { return }
        let rahmen = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rahmen) else { return }
        view.cacheDisplay(in: rahmen, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
