import SwiftUI
import SwiftData

enum Bereich: String, CaseIterable, Identifiable, Hashable {
    case uebersicht, vertraege, pruefliste, fristen, zahlungen, dokumente, importieren, exportieren

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .uebersicht: "Übersicht"
        case .vertraege: "Verträge"
        case .pruefliste: "Prüfliste"
        case .fristen: "Fristen & Aufgaben"
        case .zahlungen: "Zahlungen"
        case .dokumente: "Dokumente"
        case .importieren: "Import"
        case .exportieren: "Export & Sicherung"
        }
    }

    var symbol: String {
        switch self {
        case .uebersicht: "chart.pie"
        case .vertraege: "doc.text"
        case .pruefliste: "checklist"
        case .fristen: "calendar.badge.clock"
        case .zahlungen: "eurosign.circle"
        case .dokumente: "doc.richtext"
        case .importieren: "square.and.arrow.down"
        case .exportieren: "square.and.arrow.up"
        }
    }
}

/// Navigationszustand: gewählter Bereich und geöffneter Vertrag.
@MainActor
@Observable
final class Navigation {
    var bereich: Bereich? = .uebersicht {
        didSet { if bereich != oldValue { pfad = [] } }
    }
    var pfad: [UUID] = []

    func oeffne(_ vertrag: Vertrag) {
        bereich = .vertraege
        pfad = [vertrag.id]
    }
}

struct InhaltView: View {
    @State private var navigation = Navigation()
    @Environment(\.modelContext) private var kontext
    @Query private var vertraege: [Vertrag]
    @Query(filter: #Predicate<Zahlung> { $0.vertrag == nil }) private var offeneZahlungen: [Zahlung]

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.bereich) {
                Section("Bestand") {
                    eintrag(.uebersicht)
                    eintrag(.vertraege, zahl: vertraege.count)
                    eintrag(.pruefliste, zahl: vertraege.filter { $0.status == .pruefen }.count + offeneZahlungen.count)
                    eintrag(.fristen)
                    eintrag(.zahlungen)
                    eintrag(.dokumente)
                }
                Section("Daten") {
                    eintrag(.importieren)
                    eintrag(.exportieren)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            NavigationStack(path: $navigation.pfad) {
                bereichsansicht
                    .navigationDestination(for: UUID.self) { id in
                        if let v = vertraege.first(where: { $0.id == id }) {
                            VertragDetailView(vertrag: v)
                        } else {
                            ContentUnavailableView("Vertrag nicht gefunden", systemImage: "questionmark.folder")
                        }
                    }
            }
        }
        .environment(navigation)
        .task {
            if Demo.aktiv { await Demo.ablauf(navigation: navigation, kontext: kontext) }
        }
    }

    @ViewBuilder
    private func eintrag(_ b: Bereich, zahl: Int? = nil) -> some View {
        Label(b.titel, systemImage: b.symbol)
            .badge(zahl ?? 0)
            .tag(b)
    }

    @ViewBuilder
    private var bereichsansicht: some View {
        switch navigation.bereich ?? .uebersicht {
        case .uebersicht: UebersichtView()
        case .vertraege: VertragslisteView()
        case .pruefliste: PrueflisteView()
        case .fristen: FristenView()
        case .zahlungen: ZahlungenView()
        case .dokumente: DokumenteView()
        case .importieren: ImportView()
        case .exportieren: ExportView()
        }
    }
}
