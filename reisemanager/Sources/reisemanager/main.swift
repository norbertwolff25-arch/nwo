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
  paaren                                    PayPal mit Amex-Finanzierung paaren
  status                                    Reisen, Sachkosten, Summen, offene Punkte

Datenbank: --db, sonst $REISEMANAGER_DB, sonst ~/Library/Application Support/Reisemanager/reisemanager.sqlite
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
guard let befehl = argumente.first, befehl != "--help", befehl != "hilfe" else { print(hilfe); exit(0) }

let pfad = datenbankPfad ?? (NSHomeDirectory() + "/Library/Application Support/Reisemanager/reisemanager.sqlite")

func rechts(_ text: String, _ breite: Int) -> String {
    String(repeating: " ", count: max(0, breite - text.count)) + text
}
func links(_ text: String, _ breite: Int) -> String {
    let gekuerzt = text.count > breite ? String(text.prefix(breite - 1)) + "…" : text
    return gekuerzt + String(repeating: " ", count: max(0, breite - gekuerzt.count))
}

do {
    let datenbank = try Datenbank(pfad: pfad)
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
