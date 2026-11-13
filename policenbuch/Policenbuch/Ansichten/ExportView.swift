import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PolicenbuchKern

struct ExportView: View {
    @Query(sort: \Vertrag.sparte) private var vertraege: [Vertrag]
    @Query private var dokumente: [Dokument]
    @State private var nurLaufende = true
    @State private var meldung: String?

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
            if let meldung {
                Section { Text(meldung) }
            }
            Section {
                Text("Vor dem Versand prüfen: Die Notizen werden mit exportiert. Zugangsdaten speichert das Policenbuch nicht.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export für Berater")
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
