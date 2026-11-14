import SwiftUI
import SwiftData

@main
struct PolicenbuchApp: App {
    let container: ModelContainer?
    let fehler: String?

    init() {
        do {
            if let ordner = Demo.ausgabeordner {
                // Demo: nur im Arbeitsspeicher, echter Bestand bleibt unberührt
                let c = try Speicher.imSpeicher()
                try Demo.befuellen(c.mainContext, dokumentordner: ordner.appendingPathComponent("Dokumente"))
                container = c
            } else {
                container = try Speicher.container()
            }
            fehler = nil
        } catch {
            container = nil
            fehler = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup("Policenbuch") {
            if let container {
                InhaltView()
                    .modelContainer(container)
                    .frame(minWidth: 980, minHeight: 620)
            } else {
                ContentUnavailableView("Datenbank nicht verfügbar",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(fehler ?? "Unbekannter Fehler"))
                    .frame(minWidth: 500, minHeight: 300)
            }
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Datenordner im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([Speicher.ordner])
                }
            }
        }
    }
}
