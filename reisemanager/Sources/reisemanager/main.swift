import Foundation
import GRDB
import ReisemanagerKern

// Kommandozeile für Import und Stand. Die SwiftUI-Oberfläche folgt in Etappe 4.

let hilfe = """
reisemanager [--db <Pfad>] <Befehl>

  import nwopay <NWO_Pay_Zahlungen.csv>     Zahlungen aus NWO-Pay
  import amex <activity.csv>                Amex-Umsätze
  import paypal <Export.csv>                PayPal-Aktivitäten
  import startbestand <Datei.json> [...]    Startbestand (Mappe, Concur-Entwürfe, offene Punkte)
  import belege <Ordner>                    Belegbilder aus dem Belegordner
  import ereignisse <Datei.json>            Reiseverläufe, Hotelaufenthalte, Termine
  paaren                                    PayPal mit Amex-Finanzierung paaren
  erkennen                                  Beginn und Ende vorbelegen, Zahlungen zuordnen (nur Vorschläge)
  vorschlaege                               offene Zuordnungsvorschläge
  annehmen <Nr> [Ziel] [--regel]            Vorschlag übernehmen, Ziel = Reise oder Sachkostenabrechnung
  ablehnen <Nr>                             Vorschlag verwerfen
  pruefen [Reise]                           Plausi-Prüfer: Ampel, Befunde, Nachfragen
  antwort <Schlüssel> <Nr>                  Nachfrage beantworten
  besorgen                                  Liste „Was ich noch besorgen muss“ nach Fundort
  status                                    Reisen, Sachkosten, Summen, offene Punkte

Datenbank: --db, sonst $REISEMANAGER_DB, sonst ~/Library/Application Support/Reisemanager/reisemanager.sqlite
Einstellungen: --einstellungen, sonst $REISEMANAGER_EINSTELLUNGEN (Wohnort, Frist der Wiedervorlage)
"""

func beenden(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
}

var argumente = Array(CommandLine.arguments.dropFirst())
var datenbankPfad = ProcessInfo.processInfo.environment["REISEMANAGER_DB"]
if let index = argumente.firstIndex(of: "--db") {
    guard index + 1 < argumente.count else { beenden("--db braucht einen Pfad") }
    datenbankPfad = argumente[index + 1]
    argumente.removeSubrange(index...index + 1)
}
var einstellungenPfad = ProcessInfo.processInfo.environment["REISEMANAGER_EINSTELLUNGEN"]
if let index = argumente.firstIndex(of: "--einstellungen") {
    guard index + 1 < argumente.count else { beenden("--einstellungen braucht einen Pfad") }
    einstellungenPfad = argumente[index + 1]
    argumente.removeSubrange(index...index + 1)
}
let alsRegel = argumente.contains("--regel")
argumente.removeAll { $0 == "--regel" }
guard let befehl = argumente.first, befehl != "--help", befehl != "hilfe" else { print(hilfe); exit(0) }

let pfad = datenbankPfad ?? (NSHomeDirectory() + "/Library/Application Support/Reisemanager/reisemanager.sqlite")

func rechts(_ text: String, _ breite: Int) -> String {
    String(repeating: " ", count: max(0, breite - text.count)) + text
}
func links(_ text: String, _ breite: Int) -> String {
    let gekuerzt = text.count > breite ? String(text.prefix(breite - 1)) + "…" : text
    return gekuerzt + String(repeating: " ", count: max(0, breite - gekuerzt.count))
}

let heute: Tag = {
    let teile = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
    return Tag(jahr: teile.year!, monat: teile.month!, tag: teile.day!)!
}()

do {
    let datenbank = try Datenbank(pfad: pfad)
    let einstellungen = try einstellungenPfad.map { try Einstellungen.laden(pfad: $0) }
    switch befehl {
    case "import":
        guard argumente.count >= 3 else { beenden(hilfe) }
        let art = argumente[1]
        for quelle in argumente.dropFirst(2) {
            let ergebnis: Importergebnis
            switch art {
            case "nwopay": ergebnis = try NWOPayImport.importiere(datei: quelle, in: datenbank)
            case "amex": ergebnis = try AmexImport.importiere(datei: quelle, in: datenbank)
            case "paypal": ergebnis = try PayPalImport.importiere(datei: quelle, in: datenbank)
            case "startbestand": ergebnis = try StartbestandImport.importiere(datei: quelle, in: datenbank)
            case "belege": ergebnis = try BelegordnerImport.importiere(ordner: quelle, in: datenbank)
            case "ereignisse": ergebnis = try EreignisImport.importiere(datei: quelle, in: datenbank)
            default: beenden("Unbekannte Importart: \(art)\n\n\(hilfe)")
            }
            print("\(URL(fileURLWithPath: quelle).lastPathComponent): \(ergebnis.zusammenfassung)")
            for fehler in ergebnis.fehler { print("  ! \(fehler)") }
        }
        if ["nwopay", "amex", "paypal"].contains(art) {
            let paare = try Paarung.paareBilden(in: datenbank)
            if paare > 0 { print("\(paare) PayPal-Zahlungen mit Amex gepaart") }
        }
    case "paaren":
        print("\(try Paarung.paareBilden(in: datenbank)) PayPal-Zahlungen mit Amex gepaart")
    case "erkennen":
        let reisen = try Vorbelegung.anwenden(in: datenbank)
        let neue = try Zuordnung.vorschlaegeBilden(in: datenbank, wohnort: einstellungen?.privatadresse.ort)
        print("Beginn oder Ende bei \(reisen) Reisen neu vorbelegt, \(neue) neue Zuordnungsvorschläge")
        if einstellungen == nil { print("Hinweis: ohne Einstellungen wird „Hotel am Wohnort“ nicht erkannt") }
    case "vorschlaege":
        try datenbank.queue.read { db in
            let offene = try Vorschlag.filter(Column("status") == Vorschlagsstatus.offen.rawValue).order(Column("gruppe"), Column("id")).fetchAll(db)
            print("Offene Vorschläge: \(offene.count)")
            for v in offene {
                guard let z = try Zahlung.fetchOne(db, key: v.zahlungId) else { continue }
                let ziel: String
                switch v.art {
                case .zuReise, .zuSachkosten: ziel = "→ \(v.zielId ?? "Ziel fehlt")"
                case .neueReise: ziel = "→ neue Reise \(v.gruppe ?? "")"
                case .privat: ziel = "→ privat"
                case .vorauskaufOffen: ziel = "→ Reise offen"
                }
                print("  \(rechts(String(v.id!), 4))  \(z.datum)  \(links(z.haendler, 30)) \(rechts(z.betragCent.map { Geld.text(cent: -$0) } ?? "?", 9))  \(links(ziel, 24)) \(v.sicherheit.rawValue): \(v.begruendung)")
            }
        }
    case "annehmen":
        guard argumente.count >= 2, let nummer = Int64(argumente[1]) else { beenden(hilfe) }
        let ziel = try Zuordnung.annehmen(in: datenbank, vorschlag: nummer, ziel: argumente.count > 2 ? argumente[2] : nil, alsRegel: alsRegel)
        print("Vorschlag \(nummer) übernommen\(ziel.map { ": \($0)" } ?? " (privat)")")
    case "ablehnen":
        guard argumente.count >= 2, let nummer = Int64(argumente[1]) else { beenden(hilfe) }
        try Zuordnung.ablehnen(in: datenbank, vorschlag: nummer)
        print("Vorschlag \(nummer) verworfen")
    case "pruefen":
        let berichte = try Plausi.pruefe(in: datenbank, einstellungen: einstellungen, heute: heute)
            .filter { argumente.count < 2 || $0.bezug == argumente[1] }
        for bericht in berichte {
            let typ = bericht.typ.map { "  [\($0.text)]" } ?? ""
            print("\(links(bericht.bezug, 4)) \(links(bericht.ampel.text.uppercased(), 5)) \(bericht.titel)\(typ)")
            if argumente.count < 2 && bericht.ampel == .gruen { continue }
            for befund in bericht.befunde where befund.art != .belegbild || argumente.count >= 2 {
                print("       \(befund.ampel.text): \(befund.text)\(befund.antwort.map { " (Antwort: \($0))" } ?? "")")
            }
            let bilder = bericht.befunde.filter { $0.art == .belegbild }
            if argumente.count < 2, !bilder.isEmpty {
                let rot = bilder.filter { $0.ampel == .rot }.count
                print("       Belegbilder: \(bilder.count - rot) fehlen bei bekanntem Beleg, \(rot) Positionen ohne Beleg")
            }
            for (schluessel, frage) in bericht.fragen {
                let optionen = frage.optionen.enumerated().map { "\($0.offset + 1) \($0.element.text)" }.joined(separator: " | ")
                print("       ? \(frage.text)  [\(schluessel)]  \(optionen)")
            }
        }
        let zaehlung = Dictionary(grouping: berichte, by: \.ampel).mapValues(\.count)
        print("\nAmpel: \(zaehlung[.gruen] ?? 0) grün, \(zaehlung[.gelb] ?? 0) gelb, \(zaehlung[.rot] ?? 0) rot. Antworten mit: reisemanager antwort <Schlüssel> <Nr>")
    case "antwort":
        guard argumente.count >= 3, let nummer = Int(argumente[2]) else { beenden(hilfe) }
        let antwort = try Plausi.beantworte(in: datenbank, schluessel: argumente[1], nummer: nummer, einstellungen: einstellungen)
        print("\(argumente[1]): \(antwort)")
    case "besorgen":
        let alle = try Plausi.pruefe(in: datenbank, einstellungen: einstellungen, heute: heute).flatMap(\.besorgen)
        print("Was ich noch besorgen muss: \(alle.count)")
        let jeFundort = Dictionary(grouping: alle, by: \.fundort)
        for fundort in jeFundort.keys.sorted() {
            print("\n\(fundort)")
            for eintrag in jeFundort[fundort]! { print("  \(links(eintrag.bezug, 4)) \(eintrag.text)") }
        }
    case "status":
        let jeReise = try Summen.jeReise(in: datenbank)
        let jeSachkosten = try Summen.jeSachkostenabrechnung(in: datenbank)
        let gesamt = try Summen.dienstreisen(in: datenbank)
        try datenbank.queue.read { db in
            print("Dienstreisen")
            for reise in try Reise.filter(Column("art") == Reiseart.dienstreise.rawValue).order(Column("id")).fetchAll(db) {
                let summe = jeReise[reise.id] ?? Reisesumme()
                let zeitraum = "\(reise.beginn?.iso ?? "          ") – \(reise.ende?.iso ?? "          ")"
                let fehlt = summe.ohneBetrag > 0 ? "  (\(summe.ohneBetrag) ohne Betrag)" : ""
                print("  \(links(reise.id, 4)) \(zeitraum)  \(links(reise.concurTitel ?? reise.anlass, 34)) \(rechts(Geld.text(cent: summe.summeCent), 10))  \(links(reise.concurNr ?? "–", 7)) \(reise.status.rawValue)\(fehlt)")
            }
            print("  Summe: Fahrt \(Geld.text(cent: gesamt.fahrtCent)), Unterkunft \(Geld.text(cent: gesamt.unterkunftCent)), Sonstiges \(Geld.text(cent: gesamt.sonstigesCent)), gesamt \(Geld.text(cent: gesamt.summeCent)) €")
            print("\nSachkosten")
            for sachkosten in try Sachkostenabrechnung.order(Column("id")).fetchAll(db) {
                let summe = jeSachkosten[sachkosten.id] ?? Reisesumme()
                print("  \(links(sachkosten.id, 4)) \(links(sachkosten.concurTitel ?? sachkosten.titel, 34)) \(rechts(Geld.text(cent: summe.summeCent), 10))  \(links(sachkosten.concurNr ?? "–", 7)) \(sachkosten.status.rawValue)")
            }
            let privat = try Reise.filter(Column("art") == Reiseart.privat.rawValue).fetchCount(db)
            let zahlungen = try Zahlung.fetchCount(db)
            let paare = try Zahlung.filter(Column("konto") == "PayPal" && Column("gepaartMitId") != nil).fetchCount(db)
            let ohneEuro = try Zahlung.filter(Column("betragCent") == nil).fetchCount(db)
            let bilder = try Belegbild.filter(Column("dubletteVonId") == nil).fetchCount(db)
            let dubletten = try Belegbild.filter(Column("dubletteVonId") != nil).fetchCount(db)
            let unzugeordnet = try Position.filter(Column("reiseId") == nil && Column("sachkostenId") == nil).fetchCount(db)
            print("\nPrivatreisen: \(privat) (in keiner Summe)")
            print("Zahlungen: \(zahlungen), davon \(paare) PayPal/Amex-Paare, \(ohneEuro) ohne Euro-Betrag")
            print("Belege: \(try Beleg.fetchCount(db)) im Verzeichnis, \(bilder) Belegbilder, \(dubletten) Dubletten")
            print("Posten ohne Zuordnung: \(unzugeordnet)")
            let punkte = try OffenerPunkt.filter(Column("erledigt") == false).order(Column("reiseId"), Column("sachkostenId"), Column("id")).fetchAll(db)
            print("\nOffene Punkte: \(punkte.count)")
            for punkt in punkte {
                print("  \(links(punkt.reiseId ?? punkt.sachkostenId ?? "–", 4)) \(punkt.text)")
            }
        }
    default:
        beenden("Unbekannter Befehl: \(befehl)\n\n\(hilfe)")
    }
} catch {
    beenden("Fehler: \(error)")
}
