import AppKit
import ReisemanagerKern
import SwiftUI
import UniformTypeIdentifiers

extension Ampel {
    var farbe: Color {
        switch self {
        case .gruen: return .green
        case .gelb: return .yellow
        case .rot: return .red
        }
    }
}

struct Ampelpunkt: View {
    let ampel: Ampel
    var body: some View {
        Circle().fill(ampel.farbe).frame(width: 10, height: 10)
            .accessibilityLabel(Text("Ampel \(ampel.text)"))
    }
}

struct Hauptfenster: View {
    @EnvironmentObject var modell: AppModell

    var body: some View {
        NavigationSplitView {
            Seitenleiste()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            switch modell.auswahl {
            case .abrechnung:
                if let detail = modell.detail { Detailansicht(detail: detail) } else { Text("Nicht gefunden").foregroundStyle(.secondary) }
            case .vorschlaege: Vorschlagsansicht()
            case .besorgen: Besorgungsansicht()
            case .einlesen: Einleseansicht()
            case .dashboard, .none: Dashboard()
            }
        }
        .onChange(of: modell.auswahl) { modell.laden() }
        .alert("Hinweis", isPresented: Binding(get: { modell.meldung != nil }, set: { if !$0 { modell.meldung = nil } })) {
            Button("OK") { modell.meldung = nil }
        } message: {
            Text(modell.meldung ?? "")
        }
    }
}

struct Seitenleiste: View {
    @EnvironmentObject var modell: AppModell

    var body: some View {
        List(selection: $modell.auswahl) {
            Label("Dashboard", systemImage: "square.grid.2x2").tag(Bereich.dashboard)
            Label("Vorschläge", systemImage: "arrow.triangle.branch")
                .badge(modell.vorschlaege.count).tag(Bereich.vorschlaege)
            Label("Was ich noch besorgen muss", systemImage: "tray.and.arrow.down")
                .badge(modell.uebersicht?.zuBesorgen ?? 0).tag(Bereich.besorgen)
            Label("Einlesen", systemImage: "square.and.arrow.down").tag(Bereich.einlesen)

            Section("Dienstreisen") {
                ForEach(modell.uebersicht?.reisen ?? []) { zeile in Seitenzeile(zeile: zeile).tag(Bereich.abrechnung(zeile.id)) }
            }
            Section("Sachkosten") {
                ForEach(modell.uebersicht?.sachkosten ?? []) { zeile in Seitenzeile(zeile: zeile).tag(Bereich.abrechnung(zeile.id)) }
            }
            Section("Privat (in keiner Summe)") {
                ForEach(modell.uebersicht?.privat ?? []) { zeile in Seitenzeile(zeile: zeile).tag(Bereich.abrechnung(zeile.id)) }
            }
        }
        .listStyle(.sidebar)
    }
}

/// Zeile der Seitenleiste. Positionen lassen sich hierher ziehen.
struct Seitenzeile: View {
    @EnvironmentObject var modell: AppModell
    let zeile: Abrechnungszeile
    @State private var istZiel = false

    var body: some View {
        HStack(spacing: 8) {
            Ampelpunkt(ampel: zeile.ampel)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(zeile.id)  \(zeile.titel)").lineLimit(1)
                if !zeile.zeitraum.isEmpty {
                    Text(zeile.zeitraum).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
        .background(istZiel ? Color.accentColor.opacity(0.2) : Color.clear)
        .dropDestination(for: String.self) { elemente, _ in
            let nummern = elemente.compactMap { $0.hasPrefix("position:") ? Int64($0.dropFirst("position:".count)) : nil }
            for nummer in nummern { modell.verschiebe(position: nummer, nach: zeile.id) }
            return !nummern.isEmpty
        } isTargeted: { istZiel = $0 }
    }
}

struct Dashboard: View {
    @EnvironmentObject var modell: AppModell

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard").font(.largeTitle.bold())
                    Spacer()
                    Button("Erkennen") { modell.erkennen() }
                        .help("Beginn und Ende vorbelegen, Zahlungen zuordnen. Es entstehen nur Vorschläge.")
                }
                if let u = modell.uebersicht {
                    Text("Dienstreisen gesamt: \(Geld.text(cent: u.summeDienstreisenCent)) €  ·  \(u.offeneVorschlaege) offene Vorschläge  ·  \(u.zuBesorgen) zu besorgen")
                        .foregroundStyle(.secondary)
                    Tabelle(titel: "Dienstreisen", zeilen: u.reisen)
                    Tabelle(titel: "Sachkosten", zeilen: u.sachkosten)
                } else {
                    Text("Noch keine Daten. Unter „Einlesen“ den Startbestand laden.").foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Tabelle: View {
    @EnvironmentObject var modell: AppModell
    let titel: String
    let zeilen: [Abrechnungszeile]

    var body: some View {
        GroupBox(titel) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(zeilen) { zeile in
                    GridRow {
                        Ampelpunkt(ampel: zeile.ampel)
                        Text(zeile.id).monospaced()
                        VStack(alignment: .leading) {
                            Text(zeile.titel).lineLimit(1)
                            if !zeile.zeitraum.isEmpty { Text(zeile.zeitraum).font(.caption).foregroundStyle(.secondary) }
                        }
                        Text(Geld.text(cent: zeile.summeCent) + " €").monospacedDigit().gridColumnAlignment(.trailing)
                        Text(zeile.status.text).foregroundStyle(.secondary)
                        Text(zeile.concurNr ?? "–").monospaced().foregroundStyle(.secondary)
                        Text(zeile.offeneFragen > 0 ? "\(zeile.offeneFragen) Fragen" : "").foregroundStyle(.orange)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { modell.auswahl = .abrechnung(zeile.id) }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Detailansicht: View {
    @EnvironmentObject var modell: AppModell
    let detail: Abrechnungsdetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Ampelpunkt(ampel: detail.zeile.ampel)
                    Text("\(detail.zeile.id)  \(detail.zeile.titel)").font(.title.bold())
                    Spacer()
                    Button("Bericht speichern …") { berichtSpeichern() }
                }
                Kopfdaten(detail: detail)
                if !detail.bericht.fragen.isEmpty { Nachfragen(detail: detail) }
                let befunde = detail.bericht.befunde.filter { $0.art != .belegbild }
                if !befunde.isEmpty {
                    GroupBox("Befunde") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(befunde, id: \.schluessel) { befund in
                                HStack(alignment: .firstTextBaseline) {
                                    Ampelpunkt(ampel: befund.ampel)
                                    Text(befund.text + (befund.antwort.map { "  (Antwort: \($0))" } ?? ""))
                                }
                            }
                        }
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Positionsliste(detail: detail)
                if !detail.bericht.besorgen.isEmpty {
                    GroupBox("Was ich noch besorgen muss") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(detail.bericht.besorgen.enumerated()), id: \.offset) { _, eintrag in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(eintrag.text)
                                    Spacer()
                                    Text(eintrag.fundort).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(6)
                    }
                }
                if !detail.offenePunkte.isEmpty {
                    GroupBox("Offene Punkte") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(detail.offenePunkte, id: \.id) { punkt in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(punkt.text + (punkt.fundort.map { "  –  \($0)" } ?? ""))
                                    Spacer()
                                    Button("Erledigt") { if let id = punkt.id { modell.erledige(punkt: id) } }
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func berichtSpeichern() {
        let dialog = NSSavePanel()
        dialog.nameFieldStringValue = "\(detail.zeile.id)_Bericht.md"
        if dialog.runModal() == .OK, let url = dialog.url {
            modell.berichtSpeichern(detail.zeile.id, nach: url)
        }
    }
}

struct Kopfdaten: View {
    @EnvironmentObject var modell: AppModell
    let detail: Abrechnungsdetail

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow { Text("Anlass").foregroundStyle(.secondary); Text(detail.anlass) }
                if let typ = detail.zeile.typ {
                    GridRow { Text("Reisetyp").foregroundStyle(.secondary); Text(typ + (detail.bericht.typGrund.map { "  (\($0))" } ?? "")) }
                }
                if let beginn = detail.beginn { zeitzeile("Beginn", beginn) }
                if let ende = detail.ende { zeitzeile("Ende", ende) }
                GridRow {
                    Text("Summe").foregroundStyle(.secondary)
                    Text(Geld.text(cent: detail.zeile.summeCent) + " €" + (detail.zeile.ohneBetrag > 0 ? "  (\(detail.zeile.ohneBetrag) Positionen ohne Betrag)" : ""))
                }
                GridRow {
                    Text("Concur").foregroundStyle(.secondary)
                    HStack {
                        Text(detail.zeile.concurNr ?? "noch kein Entwurf")
                        if let titel = detail.concurTitel, !detail.titelGueltig {
                            Text("Titel hat \(titel.count) Zeichen, erlaubt sind \(Abrechnungstitel.maxLaenge)").foregroundStyle(.red)
                        }
                    }
                }
                GridRow {
                    Text("Status").foregroundStyle(.secondary)
                    Picker("Status", selection: Binding(get: { detail.zeile.status }, set: { modell.setzeStatus(detail.zeile.id, $0) })) {
                        ForEach(Reisestatus.allCases, id: \.self) { status in Text(status.text).tag(status) }
                    }
                    .labelsHidden().frame(maxWidth: 260)
                }
            }
            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Jede Vorbelegung zeigt Quelle und Sicherheitsstufe.
    private func zeitzeile(_ name: String, _ angabe: Zeitangabe) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(angabe.wert)
                if let sicherheit = angabe.sicherheit {
                    Text(sicherheit.text).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                if let quelle = angabe.quelle { Text("Quelle: \(quelle)").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Nachfragen gesammelt je Reise, als Auswahl mit kurzen Antworten.
struct Nachfragen: View {
    @EnvironmentObject var modell: AppModell
    let detail: Abrechnungsdetail

    var body: some View {
        GroupBox("Nachfragen") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(detail.bericht.fragen, id: \.schluessel) { eintrag in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(eintrag.frage.text).bold()
                        HStack {
                            ForEach(Array(eintrag.frage.optionen.enumerated()), id: \.offset) { index, option in
                                Button(option.text) { modell.antworte(eintrag.schluessel, nummer: index + 1) }
                            }
                        }
                    }
                }
            }
            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Positionen der Abrechnung. Jede Zeile lässt sich auf eine andere Reise in der Seitenleiste ziehen.
struct Positionsliste: View {
    let detail: Abrechnungsdetail

    var body: some View {
        GroupBox("Positionen (zum Umordnen auf eine Reise in der Seitenleiste ziehen)") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(detail.positionen) { position in
                    HStack(spacing: 10) {
                        Ampelpunkt(ampel: position.belegAmpel)
                        Text(position.datum).monospaced().frame(width: 92, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(position.haendler).lineLimit(1)
                            Text([position.kostenart, position.quelle, position.vorauskauf ? "Vorauskauf" : "", position.belege.joined(separator: ", ")]
                                .filter { !$0.isEmpty }.joined(separator: "  ·  "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(position.betrag).monospacedDigit()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .draggable("position:\(position.id)")
                    Divider()
                }
                if detail.positionen.isEmpty { Text("Keine Positionen").foregroundStyle(.secondary).padding(6) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Vorschlagsansicht: View {
    @EnvironmentObject var modell: AppModell

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Vorschläge").font(.largeTitle.bold())
                    Spacer()
                    Button("Erkennen") { modell.erkennen() }
                }
                Text("Nichts wird ohne deine Bestätigung übernommen.").foregroundStyle(.secondary)
                ForEach(modell.vorschlaege) { v in
                    GroupBox {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(v.datum)  \(v.haendler)  ·  \(v.betrag)").bold()
                                Text("→ \(v.ziel)  ·  \(v.sicherheit.text)")
                                Text(v.begruendung).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if v.art == .privat {
                                Button("Privat") { modell.annehmen(v.id) }
                                Button("Privat, als Regel merken") { modell.annehmen(v.id, alsRegel: true) }
                            } else if v.art != .vorauskaufOffen && v.ziel != "Ziel fehlt" {
                                Button("Übernehmen") { modell.annehmen(v.id) }
                            }
                            Menu("Andere Reise") {
                                ForEach((modell.uebersicht?.reisen ?? []) + (modell.uebersicht?.sachkosten ?? [])) { zeile in
                                    Button("\(zeile.id)  \(zeile.titel)") { modell.annehmen(v.id, ziel: zeile.id) }
                                }
                            }
                            .frame(width: 130)
                            Button("Verwerfen") { modell.ablehnen(v.id) }
                        }
                        .padding(4)
                    }
                }
                if modell.vorschlaege.isEmpty { Text("Keine offenen Vorschläge.").foregroundStyle(.secondary) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Besorgungsansicht: View {
    @EnvironmentObject var modell: AppModell

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Was ich noch besorgen muss").font(.largeTitle.bold())
                ForEach(modell.besorgen) { gruppe in
                    GroupBox(gruppe.fundort) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(gruppe.eintraege.enumerated()), id: \.offset) { _, eintrag in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(eintrag.bezug).monospaced().frame(width: 40, alignment: .leading)
                                    Text(eintrag.text)
                                }
                            }
                        }
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if modell.besorgen.isEmpty { Text("Nichts offen.").foregroundStyle(.secondary) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Einleseansicht: View {
    @EnvironmentObject var modell: AppModell
    @State private var art: Importart = .startbestand
    @State private var dialogOffen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Einlesen").font(.largeTitle.bold())
            Text("Alle Quellen werden nur gelesen. Zugangsdaten speichert die App nie.").foregroundStyle(.secondary)
            HStack {
                Picker("Quelle", selection: $art) {
                    ForEach(Importart.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(maxWidth: 380)
                Button(art == .belege ? "Ordner wählen …" : "Datei wählen …") { dialogOffen = true }
            }
            Text("Datenordner: \(modell.ordner.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            GroupBox("Protokoll") {
                ScrollView {
                    Text(modell.protokoll.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 220)
            }
            Spacer()
        }
        .padding(20)
        .fileImporter(isPresented: $dialogOffen,
                      allowedContentTypes: art == .belege ? [.folder] : [.commaSeparatedText, .json, .plainText],
                      allowsMultipleSelection: art != .belege) { ergebnis in
            switch ergebnis {
            case .success(let urls): modell.importiere(art, urls: urls)
            case .failure(let fehler): modell.meldung = "\(fehler.localizedDescription)"
            }
        }
    }
}
