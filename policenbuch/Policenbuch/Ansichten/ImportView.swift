import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PolicenbuchKern

struct ImportView: View {
    @Environment(\.modelContext) private var kontext

    private enum Auswahl { case bestand, clark, pay, pdfOrdner }
    @State private var auswahl: Auswahl?
    @State private var dateiwahl = false
    @State private var vorschau: ImportVorschau?
    @State private var rohexport: RohexportHuelle?
    @State private var bericht: ImportBericht?
    @State private var fehler: String?
    @State private var pdfFortschritt: (fertig: Int, gesamt: Int)?

    var body: some View {
        Form {
            Section {
                importzeile(titel: "Versicherungsbestand (CSV) oder eigener Export",
                            text: "versicherungsbestand_*.csv – Semikolon, UTF-8 mit BOM, Dezimalkomma. Unbekannte Spalten wandern in die Notizen. Auch der eigene Berater-Export (vertraege.csv oder vertraege.json) lässt sich zurücklesen.",
                            symbol: "tablecells", knopf: "CSV wählen …") { starte(.bestand) }
                importzeile(titel: "DSGVO-Export von Clark",
                            text: "JSON oder CSV. Die Felder ordnest du im nächsten Schritt zu; nicht zugeordnete Felder bleiben in den Notizen erhalten.",
                            symbol: "arrow.down.doc", knopf: "Export wählen …") { starte(.clark) }
                importzeile(titel: "Zahlungen aus NWO-Pay",
                            text: "pay_id;konto;art;datum;richtung;betrag;gegenpartei;zweck;… – Zuordnung über die Vertragsnummer im Verwendungszweck. Doppelte pay_id werden übersprungen.",
                            symbol: "eurosign.circle", knopf: "CSV wählen …") { starte(.pay) }
                importzeile(titel: "PDF-Ordner",
                            text: "Liest alle PDFs (auch Unterordner), erkennt Text per PDFKit oder Vision-OCR, ordnet über die Vertragsnummer zu und bestimmt Dokumenttyp und Datum.",
                            symbol: "doc.viewfinder", knopf: "Ordner wählen …") { starte(.pdfOrdner) }
                    .disabled(pdfFortschritt != nil)
                if let p = pdfFortschritt {
                    ProgressView(value: Double(p.fertig), total: Double(max(p.gesamt, 1))) {
                        Text("Texterkennung: \(p.fertig) von \(p.gesamt) PDFs")
                    }
                }
            } footer: {
                Text("Alle Importe laufen lokal. Gespeichert wird nur unter ~/Library/Application Support/Policenbuch. Zugangsdaten (Passwort, PIN, Token) werden nie übernommen.")
            }

            if let bericht {
                Section(bericht.titel) {
                    ForEach(Array(bericht.zeilen.enumerated()), id: \.offset) { _, z in Text(z) }
                }
            }
            if let fehler {
                Section("Fehler") { Text(fehler).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Import")
        .fileImporter(isPresented: $dateiwahl, allowedContentTypes: erlaubteTypen, allowsMultipleSelection: auswahl != .pdfOrdner && auswahl != .clark) { ergebnis in
            verarbeiten(ergebnis)
        }
        .sheet(item: $vorschau) { v in
            ImportVorschauView(vorschau: v) { bestaetigt in
                do {
                    bericht = try ImportDienst.uebernehmen(bestaetigt, kontext: kontext)
                    fehler = nil
                } catch {
                    fehler = error.localizedDescription
                }
            }
        }
        .sheet(item: $rohexport) { h in
            FeldzuordnungView(roh: h.roh) { zuordnung in
                let ergebnis = h.roh.importieren(mit: zuordnung)
                // erst das Zuordnungsblatt schließen lassen, dann die Vorschau zeigen
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    vorschau = ImportDienst.vorschau(ergebnis, kontext: kontext)
                }
            }
        }
    }

    private var erlaubteTypen: [UTType] {
        switch auswahl {
        case .pdfOrdner: [.folder]
        case .clark, .bestand: [.json, .commaSeparatedText, .plainText, .data]
        default: [.commaSeparatedText, .plainText, .data]
        }
    }

    private func starte(_ a: Auswahl) {
        auswahl = a
        fehler = nil
        dateiwahl = true
    }

    private func importzeile(titel: String, text: String, symbol: String, knopf: String, aktion: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).frame(width: 28).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(titel).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(knopf, action: aktion)
        }
        .padding(.vertical, 4)
    }

    private func lesen(_ url: URL) throws -> Data {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func verarbeiten(_ ergebnis: Result<[URL], Error>) {
        let urls: [URL]
        switch ergebnis {
        case .success(let u): urls = u
        case .failure(let e): fehler = e.localizedDescription; return
        }
        guard !urls.isEmpty, let auswahl else { return }
        do {
            switch auswahl {
            case .bestand:
                var alle: [VertragsDaten] = []
                var warnungen: [(zeile: Int, text: String)] = []
                for url in urls {
                    let e = url.pathExtension.lowercased() == "json"
                        ? try BeraterExport.vertraege(ausJSON: try lesen(url), quelle: url.lastPathComponent)
                        : try BestandImport.lesen(try lesen(url), dateiname: url.lastPathComponent)
                    alle += e.vertraege
                    warnungen += e.warnungen.map { (zeile: $0.zeile, text: "\(url.lastPathComponent): \($0.text)") }
                }
                let quelle = urls.map(\.lastPathComponent).joined(separator: ", ")
                vorschau = ImportDienst.vorschau(VertragsImport(vertraege: alle, warnungen: warnungen, quelle: quelle), kontext: kontext)
            case .clark:
                let url = urls[0]
                rohexport = RohexportHuelle(roh: try ClarkImport.lesen(try lesen(url), dateiname: url.lastPathComponent))
            case .pay:
                var zeilen: [String] = []
                for url in urls {
                    let b = try ImportDienst.zahlungenImportieren(try lesen(url), dateiname: url.lastPathComponent, kontext: kontext)
                    zeilen += urls.count > 1 ? [url.lastPathComponent + ":"] + b.zeilen.map { "  " + $0 } : b.zeilen
                }
                bericht = ImportBericht(titel: "NWO-Pay", zeilen: zeilen)
            case .pdfOrdner:
                Task { await pdfOrdnerEinlesen(urls[0]) }
            }
        } catch {
            fehler = error.localizedDescription
        }
    }

    private func pdfOrdnerEinlesen(_ ordner: URL) async {
        let zugriff = ordner.startAccessingSecurityScopedResource()
        defer { if zugriff { ordner.stopAccessingSecurityScopedResource() } }
        let alle = await Task.detached { Texterkennung.pdfs(in: ordner) }.value
        let neue = alle.filter { !ImportDienst.dokumentVorhanden(pfad: $0.path, kontext: kontext) }
        pdfFortschritt = (0, neue.count)
        var zugeordnet = 0, ohneText = 0
        var ohneVertrag: [String] = []
        for (i, url) in neue.enumerated() {
            let text = await Task.detached(priority: .userInitiated) { Texterkennung.text(aus: url) }.value
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ohneText += 1 }
            let d = ImportDienst.dokumentAnlegen(pfad: url.path, text: text, kontext: kontext)
            if d.vertrag != nil { zugeordnet += 1 } else { ohneVertrag.append(url.lastPathComponent) }
            pdfFortschritt = (i + 1, neue.count)
            if i % 10 == 9 { try? kontext.save() }
        }
        try? kontext.save()
        pdfFortschritt = nil
        var zeilen = ["\(alle.count) PDFs gefunden, \(alle.count - neue.count) bereits bekannt",
                      "\(neue.count) neu eingelesen, davon \(zugeordnet) einem Vertrag zugeordnet"]
        if ohneText > 0 { zeilen.append("\(ohneText) ohne erkennbaren Text") }
        if !ohneVertrag.isEmpty {
            zeilen.append("Ohne Vertrag (Zuordnung in Prüfliste oder Dokumente): " + ohneVertrag.prefix(20).joined(separator: ", ")
                          + (ohneVertrag.count > 20 ? " …" : ""))
        }
        bericht = ImportBericht(titel: "PDF-Ordner \(ordner.lastPathComponent)", zeilen: zeilen)
    }
}

struct RohexportHuelle: Identifiable {
    let id = UUID()
    var roh: Rohexport
}

// MARK: - Feldzuordnung (Mapping-Dialog)

struct FeldzuordnungView: View {
    var roh: Rohexport
    var weiter: (Feldzuordnung) -> Void
    @State private var zuordnung: Feldzuordnung
    @Environment(\.dismiss) private var schliessen

    init(roh: Rohexport, weiter: @escaping (Feldzuordnung) -> Void) {
        self.roh = roh
        self.weiter = weiter
        _zuordnung = State(initialValue: Feldzuordnung.automatisch(fuer: roh.felder))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Felder zuordnen").font(.title2.bold())
                Text("\(roh.datensaetze.count) Datensätze in „\(roh.quelle)“. Felder ohne Zuordnung werden als „Feldname: Wert“ in den Notizen gesichert.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            Table(roh.felder.map(FeldZeile.init)) {
                TableColumn("Feld im Export") { z in Text(z.feld).monospaced() }
                TableColumn("Beispielwert") { z in Text(roh.beispiel(fuer: z.feld)).lineLimit(1).foregroundStyle(.secondary) }
                TableColumn("Übernehmen als") { z in
                    if Zielfeld.istGeheim(z.feld) {
                        Text("Zugangsdaten – wird nie gespeichert").foregroundStyle(.orange)
                    } else {
                        Picker("Ziel", selection: binding(z.feld)) {
                            ForEach(Zielfeld.allCases) { Text($0.anzeige).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                .width(min: 200, ideal: 220)
            }
            HStack {
                Button("Automatisch zuordnen") { zuordnung = .automatisch(fuer: roh.felder) }
                Spacer()
                Button("Abbrechen", role: .cancel) { schliessen() }.keyboardShortcut(.cancelAction)
                Button("Weiter zum Abgleich") {
                    weiter(zuordnung)
                    schliessen()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private struct FeldZeile: Identifiable {
        var feld: String
        var id: String { feld }
    }

    private func binding(_ feld: String) -> Binding<Zielfeld> {
        Binding(get: { zuordnung.ziel(fuer: feld) }, set: { zuordnung.zuordnung[feld] = $0 })
    }
}

// MARK: - Vorschau und Konflikte

struct ImportVorschauView: View {
    @State var vorschau: ImportVorschau
    var uebernehmen: (ImportVorschau) -> Void
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Import prüfen").font(.title2.bold())
                Text(vorschau.quelle).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    Label("\(vorschau.abgleich.neu.count) neu", systemImage: "plus.circle")
                    Label("\(vorschau.abgleich.konflikte.count) Dubletten mit Unterschieden", systemImage: "arrow.left.arrow.right")
                    Label("\(vorschau.abgleich.unveraendert.count) unverändert", systemImage: "equal.circle")
                    if !vorschau.warnungen.isEmpty {
                        Label("\(vorschau.warnungen.count) Hinweise", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !vorschau.abgleich.konflikte.isEmpty {
                        Text("Dubletten (gleiche Vertragsnummer und Versicherer)").font(.headline)
                        ForEach(vorschau.abgleich.konflikte) { k in
                            KonfliktKarte(konflikt: k, loesung: Binding(
                                get: { vorschau.loesungen[k.id] ?? .zusammenfuehren },
                                set: { vorschau.loesungen[k.id] = $0 }))
                        }
                    }
                    if !vorschau.abgleich.neu.isEmpty {
                        Text("Neue Verträge").font(.headline)
                        ForEach(vorschau.abgleich.neu) { v in
                            HStack {
                                Text(v.versicherer.isEmpty ? "?" : v.versicherer).bold()
                                Text(v.sparte)
                                Text(v.vertragsnummer).monospaced().foregroundStyle(.secondary)
                                Spacer()
                                if v.status == .pruefen { StatusMarke(status: .pruefen) }
                                Text(Zahl.euro(v.jahresbeitrag) + " / Jahr").monospacedDigit()
                            }
                        }
                    }
                    if !vorschau.warnungen.isEmpty {
                        Text("Hinweise").font(.headline)
                        ForEach(Array(vorschau.warnungen.enumerated()), id: \.offset) { _, w in
                            Text("Zeile \(w.zeile): \(w.text)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { schliessen() }.keyboardShortcut(.cancelAction)
                Button("Übernehmen") {
                    uebernehmen(vorschau)
                    schliessen()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vorschau.abgleich.neu.isEmpty && vorschau.abgleich.konflikte.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

/// Bestand und Import nebeneinander, nur die abweichenden Felder.
struct KonfliktKarte: View {
    var konflikt: Dublettenkonflikt
    @Binding var loesung: Konfliktloesung

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(konflikt.bestand.versicherer).bold()
                    Text(konflikt.bestand.vertragsnummer).monospaced()
                    Spacer()
                    Picker("Lösung", selection: $loesung) {
                        ForEach(Konfliktloesung.allCases) { Text($0.anzeige).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Feld").foregroundStyle(.secondary)
                        Text("Im Bestand").foregroundStyle(.secondary)
                        Text("Im Import").foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach(konflikt.unterschiede) { u in
                        GridRow {
                            Text(u.feld.anzeige)
                            Text(u.bestand.isEmpty ? "–" : u.bestand)
                                .foregroundStyle(loesung == .importUebernehmen ? .secondary : .primary)
                                .lineLimit(4)
                            Text(u.importiert)
                                .foregroundStyle(loesung == .bestandBehalten ? .secondary : .primary)
                                .lineLimit(4)
                        }
                    }
                }
                Text(erklaerung).font(.caption).foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var erklaerung: String {
        switch loesung {
        case .bestandBehalten: "Der Bestand bleibt unverändert, der Import wird verworfen."
        case .importUebernehmen: "Die Importwerte ersetzen den Bestand. Bisherige Notizen bleiben erhalten."
        case .zusammenfuehren: "Leere Felder werden aus dem Import gefüllt, abweichende Importwerte als Notiz festgehalten."
        }
    }
}
