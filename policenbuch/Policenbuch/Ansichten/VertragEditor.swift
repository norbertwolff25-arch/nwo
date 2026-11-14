import SwiftUI
import PolicenbuchKern

/// Bearbeitet eine Kopie der Vertragsdaten; gespeichert wird erst mit „Sichern“.
struct VertragEditor: View {
    var titel: String
    @State var daten: VertragsDaten
    var sichern: (VertragsDaten) -> Void
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Vertrag") {
                    TextField("Versicherer", text: $daten.versicherer)
                    TextField("Sparte", text: $daten.sparte)
                    TextField("Vertragsnummer", text: $daten.vertragsnummer)
                    TextField("Tarif", text: $daten.tarif)
                    Picker("Status", selection: $daten.status) {
                        ForEach(VertragsStatus.allCases) { Text($0.anzeige).tag($0) }
                    }
                    Picker("Betreuer", selection: $daten.betreuer) {
                        Text("–").tag(Betreuer?.none)
                        ForEach(Betreuer.allCases) { Text($0.anzeige).tag(Betreuer?.some($0)) }
                    }
                }
                Section("Laufzeit") {
                    OptionalesDatum(titel: "Beginn", datum: $daten.beginn)
                    OptionalesDatum(titel: "Ablauf", datum: $daten.ablauf)
                    TextField("Kündigungsfrist", text: $daten.kuendigungsfrist, prompt: Text("z. B. 3 Monate zum Ablauf"))
                }
                Section("Beitrag") {
                    TextField("Beitrag je Zahlung (€)", value: $daten.beitrag, format: .number.locale(Locale(identifier: "de_DE")))
                    Picker("Zahlweise", selection: $daten.zahlweise) {
                        Text("–").tag(Zahlweise?.none)
                        ForEach(Zahlweise.allCases) { Text($0.anzeige).tag(Zahlweise?.some($0)) }
                    }
                    TextField("Dynamik (%)", value: $daten.dynamikProzent, format: .number.locale(Locale(identifier: "de_DE")))
                    LabeledContent("Jahresbeitrag", value: Zahl.euro(daten.jahresbeitrag))
                    TextField("Steuerliche Einordnung", text: $daten.steuerlicheEinordnung)
                }
                Section("Notizen") {
                    TextEditor(text: $daten.notizen)
                        .frame(minHeight: 90)
                        .font(.body)
                    Text("Bitte keine Passwörter oder Portalzugänge eintragen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { schliessen() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    sichern(daten)
                    schliessen()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 640)
        .navigationTitle(titel)
    }
}

struct OptionalesDatum: View {
    var titel: String
    @Binding var datum: Date?

    var body: some View {
        HStack {
            Toggle(titel, isOn: Binding(
                get: { datum != nil },
                set: { an in datum = an ? (datum ?? Datum.tag(Datum.jahr(.now), 1, 1)) : nil }
            ))
            if let wert = datum {
                Spacer()
                DatePicker(titel, selection: Binding(get: { wert }, set: { datum = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "de_DE"))
            }
        }
    }
}
