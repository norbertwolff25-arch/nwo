import SwiftUI
import SwiftData
import PolicenbuchKern

// MARK: - Prüfliste

struct PrueflisteView: View {
    @Query(sort: \Vertrag.versicherer) private var vertraege: [Vertrag]
    @Query(sort: \Zahlung.datum, order: .reverse) private var zahlungen: [Zahlung]
    @Query(filter: #Predicate<Dokument> { $0.vertrag == nil }) private var dokumenteOhneVertrag: [Dokument]
    @Environment(Navigation.self) private var navigation
    @Environment(\.modelContext) private var kontext

    private var liste: Pruefliste {
        Pruefliste.erstellen(vertraege: vertraege.map(\.daten), zahlungen: zahlungen.map(\.daten),
                             jahr: Datum.jahr(.now), stichtag: .now)
    }

    var body: some View {
        let p = liste
        let nachID = Dictionary(vertraege.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let offeneIDs = Set(p.zahlungenOhneVertrag.map(\.id))
        let kernVertraege = vertraege.map(\.daten)
        let kernZahlungen = zahlungen.map(\.daten)
        let vorschlaege = Dictionary(uniqueKeysWithValues: p.zahlungenOhneVertrag.map {
            ($0.id, ZahlungsZuordnung.vorschlaege(fuer: $0, vertraege: kernVertraege, zugeordnet: kernZahlungen))
        })
        let sichere = vorschlaege.values.filter { $0.first?.sicher == true }.count
        List {
            Section {
                if p.zuPruefen.isEmpty { Text("Keine.").foregroundStyle(.secondary) }
                ForEach(p.zuPruefen) { d in
                    if let v = nachID[d.id] { VertragKurzzeile(vertrag: v) { navigation.oeffne(v) } }
                }
            } header: {
                Label("Verträge mit Status „Prüfen“ (\(p.zuPruefen.count))", systemImage: "flag")
            }

            Section {
                if p.ohneZahlungImJahr.isEmpty { Text("Keine.").foregroundStyle(.secondary) }
                ForEach(p.ohneZahlungImJahr) { d in
                    if let v = nachID[d.id] { VertragKurzzeile(vertrag: v) { navigation.oeffne(v) } }
                }
            } header: {
                Label("Aktive Verträge ohne Zahlung in \(String(Datum.jahr(.now))) (\(p.ohneZahlungImJahr.count))",
                      systemImage: "eurosign.circle")
            } footer: {
                Text("Jährliche Zahler erscheinen erst, wenn ihre Fälligkeit in diesem Jahr verstrichen ist.")
            }

            Section {
                if offeneIDs.isEmpty { Text("Keine.").foregroundStyle(.secondary) }
                ForEach(zahlungen.filter { offeneIDs.contains($0.id) }) { z in
                    ZahlungZuordnenZeile(zahlung: z, vertraege: vertraege, vorschlaege: vorschlaege[z.id] ?? [])
                }
            } header: {
                HStack {
                    Label("Zahlungen ohne Vertrag (\(offeneIDs.count))", systemImage: "questionmark.circle")
                    Spacer()
                    if sichere > 0 {
                        Button("\(sichere) eindeutige Vorschläge übernehmen") {
                            _ = try? ImportDienst.sichereVorschlaegeUebernehmen(kontext: kontext)
                        }
                        .help("Nur Vorschläge mit mindestens 80 Punkten und klarem Abstand zum nächsten Vertrag")
                    }
                }
            } footer: {
                Text("Vorschläge beruhen auf Versicherer im Buchungstext, Betrag passend zum Beitrag und früheren Zahlungen. Nichts wird ohne Klick zugeordnet.")
            }

            if !dokumenteOhneVertrag.isEmpty {
                Section {
                    ForEach(dokumenteOhneVertrag) { d in DokumentZeile(dokument: d, zeigeVertrag: true) }
                } header: {
                    Label("Dokumente ohne Vertrag (\(dokumenteOhneVertrag.count))", systemImage: "doc.questionmark")
                }
            }
        }
        .navigationTitle("Prüfliste")
    }
}

struct VertragKurzzeile: View {
    var vertrag: Vertrag
    var oeffnen: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(vertrag.titel)
                Text(vertrag.vertragsnummer.isEmpty ? "ohne Vertragsnummer" : vertrag.vertragsnummer)
                    .font(.caption).foregroundStyle(.secondary).monospaced()
            }
            Spacer()
            Text(Zahl.euro(vertrag.jahresbeitrag) + " / Jahr").monospacedDigit().foregroundStyle(.secondary)
            Button("Öffnen", action: oeffnen)
        }
    }
}

struct ZahlungZuordnenZeile: View {
    @Bindable var zahlung: Zahlung
    var vertraege: [Vertrag]
    var vorschlaege: [Zuordnungsvorschlag] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Datum.deutsch(zahlung.datum)).monospacedDigit().frame(width: 84, alignment: .leading)
                Text(Zahl.euro(zahlung.betrag)).monospacedDigit().frame(width: 100, alignment: .trailing)
                Text(zahlung.buchungstext).lineLimit(2).help(zahlung.buchungstext)
                Spacer()
                Picker("Vertrag", selection: $zahlung.vertrag) {
                    Text("– kein Vertrag –").tag(Vertrag?.none)
                    ForEach(vertraege) { v in
                        Text("\(v.titel) (\(v.vertragsnummer))").tag(Vertrag?.some(v))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)
            }
            ForEach(vorschlaege.prefix(2)) { vorschlag in
                if let v = vertraege.first(where: { $0.id == vorschlag.vertragID }) {
                    HStack(spacing: 8) {
                        Image(systemName: vorschlag.sicher ? "lightbulb.fill" : "lightbulb")
                            .foregroundStyle(vorschlag.sicher ? Color.yellow : Color.secondary)
                        Text("Vorschlag: \(v.titel) (\(vorschlag.punkte) Punkte)")
                        Text(vorschlag.gruende.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Übernehmen") { zahlung.vertrag = v }.controlSize(.small)
                    }
                    .font(.callout)
                    .padding(.leading, 92)
                }
            }
        }
    }
}

// MARK: - Fristen & Aufgaben

struct FristenView: View {
    @Query private var vertraege: [Vertrag]
    @Query(sort: \Aufgabe.faelligkeit) private var aufgaben: [Aufgabe]
    @Environment(\.modelContext) private var kontext
    @Environment(Navigation.self) private var navigation
    @AppStorage("vorlaufTage") private var vorlaufTage = 30
    @State private var meldung: String?
    @State private var neueAufgabe = ""
    @State private var neuesDatum: Date? = Datum.plus(tage: 14, zu: .now)
    @State private var zeigeErledigte = false

    private var fristen: [Frist] {
        Fristen.berechnen(vertraege: vertraege.map(\.daten), aufgaben: aufgaben.map(\.daten),
                          stichtag: Datum.kalender.startOfDay(for: .now), vorlaufTage: vorlaufTage)
    }

    var body: some View {
        let nachID = Dictionary(vertraege.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        List {
            Section {
                HStack {
                    Stepper("Erinnerung \(vorlaufTage) Tage vor Kündigungsfrist", value: $vorlaufTage, in: 7...120, step: 7)
                    Spacer()
                    Button("Erinnerungen planen", systemImage: "bell.badge") {
                        Task { await planen(nachID) }
                    }
                }
                if let meldung { Text(meldung).font(.callout).foregroundStyle(.secondary) }
            } footer: {
                Text("Ablauftermine (z. B. Kapitalauszahlung) melden sich mindestens 90 Tage vorher. Mitteilungen bleiben lokal auf diesem Mac.")
            }

            Section("Anstehende Termine") {
                if fristen.isEmpty { Text("Keine Fristen. Pflege Ablauf oder Kündigungsfrist in den Verträgen.").foregroundStyle(.secondary) }
                ForEach(fristen) { f in
                    HStack {
                        FristZeile(frist: f)
                        if let id = f.vertragID, let v = nachID[id] {
                            Button("Öffnen") { navigation.oeffne(v) }.buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Aufgaben") {
                HStack {
                    TextField("Neue Aufgabe", text: $neueAufgabe)
                    OptionalesDatum(titel: "fällig", datum: $neuesDatum).fixedSize()
                    Button("Hinzufügen") {
                        kontext.insert(Aufgabe(titel: neueAufgabe, faelligkeit: neuesDatum, vertrag: nil))
                        neueAufgabe = ""
                    }
                    .disabled(neueAufgabe.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(aufgaben.filter { zeigeErledigte || !$0.erledigt }) { a in
                    AufgabeZeile(aufgabe: a, zeigeVertrag: true)
                }
                Toggle("Erledigte zeigen", isOn: $zeigeErledigte)
            }
        }
        .navigationTitle("Fristen & Aufgaben")
        .task { if !Demo.aktiv { await planen(nachID, still: true) } }
    }

    private func planen(_ nachID: [UUID: Vertrag], still: Bool = false) async {
        let namen = nachID.mapValues { "\($0.titel) · \($0.vertragsnummer)" }
        let anzahl = await Erinnerungen.planen(fristen, vertragsnamen: namen)
        if !still || anzahl > 0 {
            meldung = anzahl > 0
                ? "\(anzahl) Erinnerungen geplant."
                : "Keine Erinnerungen geplant. Bitte Mitteilungen in den Systemeinstellungen erlauben."
        }
    }
}

struct AufgabeZeile: View {
    @Bindable var aufgabe: Aufgabe
    var zeigeVertrag: Bool
    @Environment(\.modelContext) private var kontext

    var body: some View {
        HStack {
            Toggle(isOn: $aufgabe.erledigt) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading) {
                TextField("Titel", text: $aufgabe.titel).textFieldStyle(.plain)
                    .strikethrough(aufgabe.erledigt)
                if zeigeVertrag, let v = aufgabe.vertrag {
                    Text(v.titel).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            OptionalesDatum(titel: "fällig", datum: $aufgabe.faelligkeit).fixedSize()
            Button("Löschen", systemImage: "trash") { kontext.delete(aufgabe) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
        }
    }
}

// MARK: - Zahlungen

struct ZahlungenView: View {
    @Query(sort: \Zahlung.datum, order: .reverse) private var zahlungen: [Zahlung]
    @Query(sort: \Vertrag.versicherer) private var vertraege: [Vertrag]
    @State private var suche = ""
    @State private var nurOffene = false

    private var gefiltert: [Zahlung] {
        zahlungen.filter { z in
            if nurOffene && z.vertrag != nil { return false }
            return suche.isEmpty || z.buchungstext.localizedCaseInsensitiveContains(suche)
                || (z.vertrag?.versicherer.localizedCaseInsensitiveContains(suche) ?? false)
        }
    }

    var body: some View {
        Table(gefiltert) {
            TableColumn("Datum") { z in Text(Datum.deutsch(z.datum)).monospacedDigit() }.width(90)
            TableColumn("Betrag") { z in
                Text(Zahl.euro(z.betrag)).monospacedDigit().foregroundStyle(z.betrag < 0 ? Color.primary : Color.green)
            }.width(100)
            TableColumn("Buchungstext", value: \.buchungstext)
            TableColumn("Quelle", value: \.quelle).width(min: 80, ideal: 140)
            TableColumn("Vertrag") { z in ZahlungVertragPicker(zahlung: z, vertraege: vertraege) }.width(min: 160, ideal: 240)
        }
        .searchable(text: $suche, prompt: "Buchungstext oder Versicherer")
        .navigationTitle("Zahlungen")
        .navigationSubtitle("\(gefiltert.count) Zahlungen")
        .toolbar { Toggle("Nur ohne Vertrag", isOn: $nurOffene) }
    }
}

struct ZahlungVertragPicker: View {
    @Bindable var zahlung: Zahlung
    var vertraege: [Vertrag]

    var body: some View {
        Picker("Vertrag", selection: $zahlung.vertrag) {
            Text("–").tag(Vertrag?.none)
            ForEach(vertraege) { v in Text("\(v.titel) (\(v.vertragsnummer))").tag(Vertrag?.some(v)) }
        }
        .labelsHidden()
    }
}

// MARK: - Dokumente

struct DokumenteView: View {
    @Query(sort: \Dokument.datum, order: .reverse) private var dokumente: [Dokument]
    @State private var suche = ""

    private var gefiltert: [Dokument] {
        guard !suche.isEmpty else { return dokumente }
        return dokumente.filter {
            $0.dateiname.localizedCaseInsensitiveContains(suche) || $0.erkannterText.localizedCaseInsensitiveContains(suche)
                || ($0.vertrag?.versicherer.localizedCaseInsensitiveContains(suche) ?? false)
        }
    }

    var body: some View {
        List {
            if dokumente.isEmpty {
                Text("Noch keine Dokumente. Unter „Import“ einen PDF-Ordner einlesen.").foregroundStyle(.secondary)
            }
            ForEach(gefiltert) { d in DokumentZeile(dokument: d, zeigeVertrag: true) }
        }
        .searchable(text: $suche, prompt: "Dateiname, Versicherer oder Text im Dokument")
        .navigationTitle("Dokumente")
        .navigationSubtitle("\(gefiltert.count) Dokumente")
    }
}

struct DokumentZeile: View {
    @Bindable var dokument: Dokument
    var zeigeVertrag: Bool
    @Query(sort: \Vertrag.versicherer) private var vertraege: [Vertrag]

    var body: some View {
        HStack {
            Image(systemName: dokument.existiert ? "doc.richtext" : "exclamationmark.triangle")
                .foregroundStyle(dokument.existiert ? Color.accentColor : Color.orange)
                .help(dokument.existiert ? dokument.pfad : "Datei nicht gefunden: \(dokument.pfad)")
            VStack(alignment: .leading) {
                Text(dokument.dateiname).lineLimit(1)
                HStack(spacing: 8) {
                    Text(Datum.deutsch(dokument.datum))
                    if !dokument.kandidaten.isEmpty && dokument.vertrag == nil {
                        Text("Nummer im Dokument: \(dokument.kandidaten)").textSelection(.enabled)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Typ", selection: Binding(get: { dokument.typ }, set: { dokument.typ = $0 })) {
                ForEach(DokumentTyp.allCases) { Text($0.anzeige).tag($0) }
            }
            .labelsHidden().frame(width: 160)
            if zeigeVertrag {
                Picker("Vertrag", selection: $dokument.vertrag) {
                    Text("– kein Vertrag –").tag(Vertrag?.none)
                    ForEach(vertraege) { v in Text("\(v.titel) (\(v.vertragsnummer))").tag(Vertrag?.some(v)) }
                }
                .labelsHidden().frame(maxWidth: 260)
            }
            Button("Öffnen", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(dokument.url) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .disabled(!dokument.existiert)
            Button("Im Finder zeigen", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([dokument.url])
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .disabled(!dokument.existiert)
        }
    }
}
