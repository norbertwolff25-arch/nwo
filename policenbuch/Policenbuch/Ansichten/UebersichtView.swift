import SwiftUI
import SwiftData
import Charts
import PolicenbuchKern

struct UebersichtView: View {
    @Query(sort: \Vertrag.sparte) private var vertraege: [Vertrag]
    @Environment(Navigation.self) private var navigation

    private var summen: [SpartenSumme] { Uebersicht.nachSparte(vertraege.map(\.daten)) }
    private var gesamt: Decimal { Uebersicht.jahresbeitragGesamt(vertraege.map(\.daten)) }

    var body: some View {
        if vertraege.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Verträge", systemImage: "tray")
            } description: {
                Text("Importiere deinen Versicherungsbestand, einen Clark-Export oder einen PDF-Ordner.")
            } actions: {
                Button("Zum Import") { navigation.bereich = .importieren }
            }
            .navigationTitle("Übersicht")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        Kennzahl(titel: "Jahresbeitrag gesamt", wert: Zahl.euro(gesamt), symbol: "eurosign")
                        Kennzahl(titel: "Je Monat", wert: Zahl.euro(Zahl.runden(gesamt / 12)), symbol: "calendar")
                        Kennzahl(titel: "Laufende Verträge",
                                 wert: "\(vertraege.filter { $0.status == .aktiv }.count) von \(vertraege.count)",
                                 symbol: "doc.text")
                    }

                    GroupBox("Jahresbeitrag nach Sparte") {
                        Chart(summen) { s in
                            BarMark(x: .value("Jahresbeitrag", s.jahresbeitrag.doubleWert),
                                    y: .value("Sparte", s.sparte))
                            .annotation(position: .trailing) {
                                Text(Zahl.euro(s.jahresbeitrag)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { wert in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let d = wert.as(Double.self) { Text("\(Int(d)) €") }
                                }
                            }
                        }
                        .frame(height: max(160, CGFloat(summen.count) * 34))
                        .padding(.vertical, 6)
                    }

                    GroupBox("Sparten") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            GridRow {
                                Text("Sparte").bold()
                                Text("Verträge").bold().gridColumnAlignment(.trailing)
                                Text("Jahresbeitrag").bold().gridColumnAlignment(.trailing)
                                Text("Je Monat").bold().gridColumnAlignment(.trailing)
                            }
                            Divider()
                            ForEach(summen) { s in
                                GridRow {
                                    Text(s.sparte)
                                    Text("\(s.anzahl)").monospacedDigit()
                                    Text(Zahl.euro(s.jahresbeitrag)).monospacedDigit()
                                    Text(Zahl.euro(s.monatsbeitrag)).monospacedDigit()
                                }
                            }
                            Divider()
                            GridRow {
                                Text("Gesamt").bold()
                                Text("\(summen.reduce(0) { $0 + $1.anzahl })").bold().monospacedDigit()
                                Text(Zahl.euro(gesamt)).bold().monospacedDigit()
                                Text(Zahl.euro(Zahl.runden(gesamt / 12))).bold().monospacedDigit()
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Beiträge zählen nur für aktive und zu prüfende Verträge. Beendete Verträge sind ausgeblendet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Übersicht")
        }
    }
}

struct Kennzahl: View {
    var titel: String
    var wert: String
    var symbol: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label(titel, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(wert).font(.title2.weight(.semibold)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

extension Decimal {
    var doubleWert: Double { NSDecimalNumber(decimal: self).doubleValue }
}
