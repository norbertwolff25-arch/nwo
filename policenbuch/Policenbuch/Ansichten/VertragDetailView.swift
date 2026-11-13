import SwiftUI
import SwiftData
import Charts
import PolicenbuchKern

struct VertragDetailView: View {
    @Bindable var vertrag: Vertrag
    @Environment(\.modelContext) private var kontext
    @State private var bearbeiten = false
    @State private var neueAufgabe = ""
    @State private var neueAufgabeDatum: Date? = nil

    private var zahlungen: [Zahlung] { vertrag.zahlungen.sorted { $0.datum > $1.datum } }
    private var dokumente: [Dokument] { vertrag.dokumente.sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) } }
    private var fristen: [Frist] {
        Fristen.berechnen(vertraege: [vertrag.daten], aufgaben: vertrag.aufgaben.map(\.daten), stichtag: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                kopf
                HStack(alignment: .top, spacing: 18) {
                    stammdaten
                    beitragsblock
                }
                if !fristen.isEmpty { fristenblock }
                verlauf
                dokumentblock
                zahlungsblock
                aufgabenblock
                notizblock
            }
            .padding(20)
        }
        .navigationTitle(vertrag.titel)
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(VertragsStatus.allCases) { s in Button(s.anzeige) { vertrag.status = s } }
                } label: { Label("Status", systemImage: "flag") }
            }
            ToolbarItem {
                Button("Bearbeiten", systemImage: "pencil") { bearbeiten = true }
            }
        }
        .sheet(isPresented: $bearbeiten) {
            VertragEditor(titel: "Vertrag bearbeiten", daten: vertrag.daten) { d in
                vertrag.uebernehmen(d)
                try? kontext.save()
                try? ImportDienst.zahlungenZuordnen(kontext: kontext)
            }
        }
    }

    private var kopf: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vertrag.versicherer.isEmpty ? "Unbekannter Versicherer" : vertrag.versicherer).font(.title.bold())
                Text([vertrag.sparte, vertrag.tarif].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusMarke(status: vertrag.status)
        }
    }

    private var stammdaten: some View {
        GroupBox("Vertrag") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                zeile("Vertragsnummer", vertrag.vertragsnummer.isEmpty ? "–" : vertrag.vertragsnummer, auswaehlbar: true)
                zeile("Beginn", Datum.deutsch(vertrag.beginn))
                zeile("Ablauf", Datum.deutsch(vertrag.ablauf))
                zeile("Kündigungsfrist", vertrag.kuendigungsfrist)
                zeile("Betreuer", vertrag.betreuer?.anzeige ?? "")
                zeile("Steuerlich", vertrag.steuerlicheEinordnung)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var beitragsblock: some View {
        GroupBox("Beitrag") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                zeile("Beitrag", vertrag.beitrag.map { Zahl.euro($0) } ?? "")
                zeile("Zahlweise", vertrag.zahlweise?.anzeige ?? "")
                zeile("Jahresbeitrag", Zahl.euro(vertrag.jahresbeitrag))
                zeile("Je Monat", Zahl.euro(vertrag.daten.monatsbeitrag))
                zeile("Dynamik", vertrag.dynamikProzent.map { Zahl.deutsch($0, stellen: 1) + " %" } ?? "")
                zeile("Gezahlt \(Datum.jahr(.now))", Zahl.euro(-zahlungen.filter { Datum.jahr($0.datum) == Datum.jahr(.now) && $0.betrag < 0 }
                    .reduce(Decimal(0)) { $0 + $1.betrag }))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func zeile(_ titel: String, _ wert: String, auswaehlbar: Bool = false) -> some View {
        GridRow {
            Text(titel).foregroundStyle(.secondary)
            if auswaehlbar {
                Text(wert.isEmpty ? "–" : wert).textSelection(.enabled).monospaced()
            } else {
                Text(wert.isEmpty ? "–" : wert)
            }
        }
    }

    private var fristenblock: some View {
        GroupBox("Fristen") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(fristen) { f in
                    FristZeile(frist: f)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    @ViewBuilder
    private var verlauf: some View {
        let jahre = Beitragsverlauf.jeJahr(zahlungen.map(\.daten))
        let einzeln = Beitragsverlauf.einzeln(zahlungen.map(\.daten))
        GroupBox("Beitragsverlauf") {
            if einzeln.isEmpty {
                Text("Noch keine Zahlungen zugeordnet. Importiere NWO-Pay, um den Verlauf zu sehen.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Je Jahr").font(.caption).foregroundStyle(.secondary)
                        Chart(jahre) { p in
                            BarMark(x: .value("Jahr", p.datum, unit: .year), y: .value("Betrag", p.betrag.doubleWert))
                                .foregroundStyle(.tint)
                        }
                        .chartYAxis { AxisMarks { w in AxisGridLine(); AxisValueLabel { if let d = w.as(Double.self) { Text("\(Int(d)) €") } } } }
                    }
                    VStack(alignment: .leading) {
                        Text("Einzelzahlungen").font(.caption).foregroundStyle(.secondary)
                        Chart(einzeln) { p in
                            LineMark(x: .value("Datum", p.datum), y: .value("Betrag", p.betrag.doubleWert))
                                .interpolationMethod(.stepEnd)
                            PointMark(x: .value("Datum", p.datum), y: .value("Betrag", p.betrag.doubleWert))
                                .symbolSize(18)
                        }
                        .chartYAxis { AxisMarks { w in AxisGridLine(); AxisValueLabel { if let d = w.as(Double.self) { Text("\(Int(d)) €") } } } }
                    }
                }
                .frame(height: 200)
                .padding(6)
            }
        }
    }

    private var dokumentblock: some View {
        GroupBox("Dokumente (\(dokumente.count))") {
            if dokumente.isEmpty {
                Text("Keine Dokumente. Lies einen PDF-Ordner unter „Import“ ein.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } else {
                VStack(spacing: 4) {
                    ForEach(dokumente) { d in DokumentZeile(dokument: d, zeigeVertrag: false) }
                }
                .padding(6)
            }
        }
    }

    private var zahlungsblock: some View {
        GroupBox("Zahlungshistorie (\(zahlungen.count))") {
            if zahlungen.isEmpty {
                Text("Keine Zahlungen zugeordnet.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(zahlungen.prefix(60)) { z in
                        GridRow {
                            Text(Datum.deutsch(z.datum)).monospacedDigit()
                            Text(Zahl.euro(z.betrag)).monospacedDigit()
                                .foregroundStyle(z.betrag < 0 ? Color.primary : Color.green)
                                .gridColumnAlignment(.trailing)
                            Text(z.buchungstext).lineLimit(1).truncationMode(.tail)
                            Button("Zuordnung lösen", systemImage: "xmark.circle") { z.vertrag = nil }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .help("Zuordnung zu diesem Vertrag aufheben")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                if zahlungen.count > 60 {
                    Text("… und \(zahlungen.count - 60) ältere Zahlungen").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aufgabenblock: some View {
        GroupBox("Aufgaben") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(vertrag.aufgaben.sorted { ($0.faelligkeit ?? .distantFuture) < ($1.faelligkeit ?? .distantFuture) }) { a in
                    AufgabeZeile(aufgabe: a, zeigeVertrag: false)
                }
                HStack {
                    TextField("Neue Aufgabe", text: $neueAufgabe)
                    OptionalesDatum(titel: "fällig", datum: $neueAufgabeDatum).fixedSize()
                    Button("Hinzufügen") {
                        let a = Aufgabe(titel: neueAufgabe, faelligkeit: neueAufgabeDatum, vertrag: vertrag)
                        kontext.insert(a)
                        neueAufgabe = ""
                        neueAufgabeDatum = nil
                    }
                    .disabled(neueAufgabe.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var notizblock: some View {
        GroupBox("Notizen") {
            TextEditor(text: $vertrag.notizen)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(2)
        }
    }
}

struct FristZeile: View {
    var frist: Frist

    var body: some View {
        let tage = Datum.tageZwischen(.now, frist.datum)
        HStack {
            Image(systemName: frist.art == .kuendigung ? "scissors" : frist.art == .ablauf ? "flag.checkered" : "checkmark.circle")
                .foregroundStyle(tage < 30 ? .orange : .secondary)
                .frame(width: 18)
            Text(Datum.deutsch(frist.datum)).monospacedDigit()
            Text(frist.titel)
            Spacer()
            Text(tage < 0 ? "überfällig" : tage == 0 ? "heute" : "in \(tage) Tagen")
                .foregroundStyle(tage < 30 ? .orange : .secondary)
                .monospacedDigit()
        }
    }
}
