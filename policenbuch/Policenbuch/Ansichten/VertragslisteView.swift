import SwiftUI
import SwiftData
import PolicenbuchKern

struct VertragslisteView: View {
    @Environment(\.modelContext) private var kontext
    @Environment(Navigation.self) private var navigation
    @Query(sort: [SortDescriptor(\Vertrag.sparte), SortDescriptor(\Vertrag.versicherer)]) private var vertraege: [Vertrag]
    @State private var auswahl = Set<Vertrag.ID>()
    @State private var suche = ""
    @State private var statusFilter: VertragsStatus?
    @State private var neuerVertrag: VertragsDaten?
    @State private var loeschenBestaetigen = false

    private var gefiltert: [Vertrag] {
        vertraege.filter { v in
            if let statusFilter, v.status != statusFilter { return false }
            guard !suche.isEmpty else { return true }
            let s = suche.lowercased()
            return [v.versicherer, v.sparte, v.vertragsnummer, v.tarif, v.notizen].contains { $0.lowercased().contains(s) }
                || Textnorm.vertragsnummer(v.vertragsnummer).contains(Textnorm.vertragsnummer(suche))
        }
    }

    var body: some View {
        Table(gefiltert, selection: $auswahl) {
            TableColumn("Versicherer", value: \.versicherer)
            TableColumn("Sparte", value: \.sparte)
            TableColumn("Vertragsnummer", value: \.vertragsnummer)
            TableColumn("Beitrag") { v in
                Text(v.beitrag.map { Zahl.euro($0) } ?? "–").monospacedDigit()
            }
            .width(min: 80, ideal: 100)
            TableColumn("Zahlweise") { v in Text(v.zahlweise?.anzeige ?? "–") }
                .width(min: 80, ideal: 100)
            TableColumn("Jahresbeitrag") { v in Text(Zahl.euro(v.jahresbeitrag)).monospacedDigit() }
                .width(min: 90, ideal: 110)
            TableColumn("Status") { v in StatusMarke(status: v.status) }
                .width(min: 80, ideal: 100)
            TableColumn("Betreuer") { v in Text(v.betreuer?.rawValue ?? "–") }
                .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: Vertrag.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let v = vertraege.first(where: { $0.id == id }) {
                Button("Öffnen") { navigation.oeffne(v) }
                Menu("Status setzen") {
                    ForEach(VertragsStatus.allCases) { s in Button(s.anzeige) { v.status = s } }
                }
            }
            if !ids.isEmpty {
                Button("Löschen …", role: .destructive) { auswahl = ids; loeschenBestaetigen = true }
            }
        } primaryAction: { ids in
            if let id = ids.first, let v = vertraege.first(where: { $0.id == id }) { navigation.oeffne(v) }
        }
        .searchable(text: $suche, prompt: "Versicherer, Sparte, Nummer, Notiz")
        .navigationTitle("Verträge")
        .navigationSubtitle("\(gefiltert.count) von \(vertraege.count)")
        .toolbar {
            ToolbarItem {
                Picker("Status", selection: $statusFilter) {
                    Text("Alle Status").tag(VertragsStatus?.none)
                    ForEach(VertragsStatus.allCases) { s in Text(s.anzeige).tag(VertragsStatus?.some(s)) }
                }
            }
            ToolbarItem {
                Button("Neuer Vertrag", systemImage: "plus") { neuerVertrag = VertragsDaten(status: .aktiv) }
            }
        }
        .sheet(item: $neuerVertrag) { d in
            VertragEditor(titel: "Neuer Vertrag", daten: d) { ergebnis in
                kontext.insert(Vertrag(ergebnis))
                try? kontext.save()
            }
        }
        .confirmationDialog("\(auswahl.count) Vertrag/Verträge löschen?", isPresented: $loeschenBestaetigen) {
            Button("Löschen", role: .destructive) {
                for v in vertraege where auswahl.contains(v.id) { kontext.delete(v) }
                try? kontext.save()
                auswahl = []
            }
        } message: {
            Text("Zahlungen und Dokumente bleiben erhalten und erscheinen danach ohne Vertrag.")
        }
    }
}

struct StatusMarke: View {
    var status: VertragsStatus

    var farbe: Color {
        switch status {
        case .aktiv: .green
        case .beitragsfrei: .blue
        case .beendet: .secondary
        case .pruefen: .orange
        }
    }

    var body: some View {
        Text(status.anzeige)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(farbe.opacity(0.15), in: Capsule())
            .foregroundStyle(farbe)
    }
}
