import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PolicenbuchKern

struct ExportView: View {
    @Query(sort: \Vertrag.sparte) private var vertraege: [Vertrag]
    @Query private var dokumente: [Dokument]
    @Environment(\.modelContext) private var kontext
    @State private var nurLaufende = true
    @State private var meldung: String?
    @State private var wiederherstellung: Sicherung?

    private var auswahl: [Vertrag] {
        nurLaufende ? vertraege.filter { $0.status != .beendet } : vertraege
    }

    private var auswahlDokumente: [DokumentDaten] {
        let ids = Set(auswahl.map(\.id))
        return dokumente.filter { d in d.vertrag.map { ids.contains($0.id) } ?? false }.map(\.daten)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Beendete Verträge weglassen", isOn: $nurLaufende)
                LabeledContent("Verträge", value: "\(auswahl.count)")
                LabeledContent("Dokumente", value: "\(auswahlDokumente.count)")
            } footer: {
                Text("Feldnamen angelehnt an GDV-Datensatz und BiPRO: Versicherungsscheinnummer, Versicherer, Sparte, Beitrag, Zahlungsweise, Jahresbeitrag, Vertragsbeginn, Vertragsablauf u. a.")
            }
            Section("Dateien für den neuen Berater") {
                HStack {
                    Label("CSV (Excel, Semikolon, Dezimalkomma)", systemImage: "tablecells")
                    Spacer()
                    Button("CSV sichern …") { sichern(name: "Vertraege_\(datum).csv", typ: .commaSeparatedText) { BeraterExport.csv(daten, dokumente: auswahlDokumente) } }
                }
                HStack {
                    Label("JSON (maschinenlesbar, mit Dokumentliste)", systemImage: "curlybraces")
                    Spacer()
                    Button("JSON sichern …") { sichern(name: "Vertraege_\(datum).json", typ: .json) { try BeraterExport.json(daten, dokumente: auswahlDokumente, erstellt: .now) } }
                }
                HStack {
                    Label("ZIP mit CSV, JSON und allen Dokumenten", systemImage: "doc.zipper")
                    Spacer()
                    Button("ZIP sichern …") { zipSichern() }
                }
            }
            Section {
                HStack {
                    Label("Komplettsicherung (Verträge, Zahlungen, Dokumentliste mit Text, Aufgaben)", systemImage: "externaldrive")
                    Spacer()
                    Button("Sicherung erstellen …") {
                        sichern(name: "Policenbuch_Sicherung_\(datum).json", typ: .json) {
                            try ImportDienst.sicherung(kontext: kontext).json()
                        }
                    }
                }
                HStack {
                    Label("Aus Sicherung wiederherstellen", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Button("Sicherung wählen …") { sicherungWaehlen() }
                }
            } header: {
                Text("Sicherung")
            } footer: {
                Text("Die Sicherung ist eine lokale JSON-Datei. PDFs sind nicht enthalten, nur ihre Pfade. Wiederherstellen ersetzt alle Daten im Policenbuch.")
            }
            if let meldung {
                Section { Text(meldung).textSelection(.enabled) }
            }
            Section {
                Text("Vor dem Versand prüfen: Die Notizen werden mit exportiert. Zugangsdaten speichert das Policenbuch nicht.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export & Sicherung")
        .confirmationDialog("Alle Daten durch die Sicherung ersetzen?", isPresented: Binding(
            get: { wiederherstellung != nil }, set: { if !$0 { wiederherstellung = nil } })) {
            Button("Ersetzen", role: .destructive) {
                guard let s = wiederherstellung else { return }
                do {
                    try ImportDienst.wiederherstellen(s, kontext: kontext)
                    meldung = "Wiederhergestellt: \(s.zusammenfassung) (Stand \(Datum.deutsch(s.erstellt)))"
                } catch {
                    meldung = "Fehler: \(error.localizedDescription)"
                }
                wiederherstellung = nil
            }
        } message: {
            Text(wiederherstellung.map { "Die Sicherung vom \(Datum.deutsch($0.erstellt)) enthält \($0.zusammenfassung). Der aktuelle Bestand wird gelöscht." } ?? "")
        }
    }

    private func sicherungWaehlen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            wiederherstellung = try Sicherung.lesen(try Data(contentsOf: url))
        } catch {
            meldung = "Fehler: \(error.localizedDescription)"
        }
    }

    private var daten: [VertragsDaten] { auswahl.map(\.daten) }
    private var datum: String { Datum.iso(.now) }

    private func ziel(name: String, typ: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [typ]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func sichern(name: String, typ: UTType, erzeugen: () throws -> Data) {
        guard let url = ziel(name: name, typ: typ) else { return }
        do {
            try erzeugen().write(to: url, options: .atomic)
            meldung = "Gesichert: \(url.path)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            meldung = "Fehler: \(error.localizedDescription)"
        }
    }

    private func zipSichern() {
        guard let url = ziel(name: "Policenbuch_Export_\(datum).zip", typ: .zip) else { return }
        do {
            let (zip, fehlend) = try BeraterExport.zip(vertraege: daten, dokumente: auswahlDokumente, erstellt: .now) { pfad in
                try? Data(contentsOf: URL(fileURLWithPath: pfad))
            }
            try zip.write(to: url, options: .atomic)
            meldung = "Gesichert: \(url.path)" + (fehlend.isEmpty ? "" : "\n\(fehlend.count) Dokumente nicht gefunden: " + fehlend.joined(separator: ", "))
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            meldung = "Fehler: \(error.localizedDescription)"
        }
    }
}
