import Foundation
import Testing
@testable import PolicenbuchKern

func testdatei(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Testdaten/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

func tag(_ j: Int, _ m: Int, _ t: Int) -> Date { Datum.tag(j, m, t)! }

@Suite("Werte")
struct WerteTests {
    @Test("Deutsche und englische Beträge", arguments: [
        ("1.234,56", Decimal(string: "1234.56")!),
        ("1234,56 €", Decimal(string: "1234.56")!),
        ("-12,30", Decimal(string: "-12.3")!),
        ("12,30-", Decimal(string: "-12.3")!),
        ("150", Decimal(150)),
        ("1.234", Decimal(1234)),
        ("12.50", Decimal(string: "12.5")!),
        ("1,234.50", Decimal(string: "1234.5")!),
        ("EUR 89,50", Decimal(string: "89.5")!),
        ("5,0 %", Decimal(5))
    ])
    func betraege(eingabe: String, erwartet: Decimal) {
        #expect(Zahl.lesen(eingabe) == erwartet)
    }

    @Test func englischerPunktBeiJSON() {
        #expect(Zahl.lesen("1.234", deutsch: false) == Decimal(string: "1.234"))
        #expect(Zahl.lesen("") == nil)
        #expect(Zahl.lesen("abc") == nil)
    }

    @Test("Datumsformate", arguments: [
        ("31.12.2026", 2026, 12, 31),
        ("1.6.28", 2028, 6, 1),
        ("2026-12-31", 2026, 12, 31),
        ("2008-06-01T00:00:00Z", 2008, 6, 1),
        ("06/2028", 2028, 6, 1),
        ("20280601", 2028, 6, 1)
    ])
    func daten(eingabe: String, j: Int, m: Int, t: Int) {
        #expect(Datum.lesen(eingabe) == tag(j, m, t))
    }

    @Test func ungueltigeDaten() {
        #expect(Datum.lesen("31.02.2026") == nil)
        #expect(Datum.lesen("irgendwann") == nil)
    }

    @Test func formatierung() {
        #expect(Zahl.deutsch(Decimal(string: "1234.5")!) == "1234,50")
        #expect(Zahl.euro(Decimal(string: "1234567.891")!) == "1.234.567,89 €")
        #expect(Zahl.euro(Decimal(-5)) == "-5,00 €")
        #expect(Datum.deutsch(tag(2028, 6, 1)) == "01.06.2028")
    }

    @Test func normalisierung() {
        #expect(Textnorm.vertragsnummer("LV-123.456 78") == "LV12345678")
        #expect(Textnorm.versichererSchluessel("Muster Sach SE") == Textnorm.versichererSchluessel("Muster-Sach"))
        #expect(Textnorm.schluessel("Kündigungsfrist") == "kuendigungsfrist")
    }

    @Test func aufzaehlungen() {
        #expect(Zahlweise.erkennen("monthly") == .monatlich)
        #expect(Zahlweise.erkennen("monatl.") == .monatlich)
        #expect(Zahlweise.erkennen("Vierteljährlich") == .vierteljaehrlich)
        #expect(Zahlweise.erkennen("yearly") == .jaehrlich)
        #expect(VertragsStatus.erkennen("prüfen") == .pruefen)
        #expect(VertragsStatus.erkennen("terminated") == .beendet)
        #expect(VertragsStatus.erkennen("beitragsfrei gestellt") == .beitragsfrei)
        #expect(Betreuer.erkennen("Clark GmbH") == .clark)
    }
}

@Suite("CSV")
struct CSVTests {
    @Test func anfuehrungszeichenUndZeilenumbrueche() {
        let text = "a;b;c\r\n1;\"x;y\";\"mit \"\"Zitat\"\"\nzweite Zeile\"\r\n\r\n2;;\n"
        let z = CSV.zerlegen(text)
        #expect(z.count == 3)
        #expect(z[1] == ["1", "x;y", "mit \"Zitat\"\nzweite Zeile"])
        #expect(z[2] == ["2", "", ""])
    }

    @Test func bomUndWindows1252() throws {
        let utf8 = Data([0xEF, 0xBB, 0xBF]) + Data("Größe;Wert\n".utf8)
        #expect(try CSV.tabelle(aus: utf8).kopf == ["Größe", "Wert"])
        let ansi = Data([0x47, 0x72, 0xF6, 0xDF, 0x65, 0x3B, 0x57, 0x0A]) // "Größe;W" in Windows-1252
        #expect(try CSV.tabelle(aus: ansi).kopf == ["Größe", "W"])
    }

    @Test func schreibenUndLesen() throws {
        let daten = CSV.schreiben(kopf: ["A", "B"], zeilen: [["x;y", "Ä \"ö\""]])
        #expect(daten.starts(with: [0xEF, 0xBB, 0xBF]))
        let t = try CSV.tabelle(aus: daten)
        #expect(t.zeilen == [["x;y", "Ä \"ö\""]])
    }
}

@Suite("Bestandsimport")
struct BestandImportTests {
    @Test func dateiname() {
        #expect(BestandImport.passt(dateiname: "versicherungsbestand_2026-11.csv"))
        #expect(!BestandImport.passt(dateiname: "bestand.csv"))
    }

    @Test func liestAlleFelder() throws {
        let ergebnis = try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv"))
        #expect(ergebnis.vertraege.count == 5)
        let lv = ergebnis.vertraege[0]
        #expect(lv.versicherer == "Beispiel Leben AG")
        #expect(lv.sparte == "Rentenversicherung")
        #expect(lv.vertragsnummer == "LV-123.456.78")
        #expect(lv.tarif == "Basisrente Klassik")
        #expect(lv.beginn == tag(2008, 6, 1))
        #expect(lv.ablauf == tag(2028, 6, 1))
        #expect(lv.kuendigungsfrist == "3 Monate")
        #expect(lv.beitrag == 150)
        #expect(lv.zahlweise == .monatlich)
        #expect(lv.dynamikProzent == 5)
        #expect(lv.status == .aktiv)
        #expect(lv.steuerlicheEinordnung == "Schicht 1 (Basisrente)")
        #expect(lv.betreuer == .clark)
        #expect(lv.jahresbeitrag == 1800)
        #expect(lv.notizen.contains("Kapitalauszahlung 06/2028"))
        // unbekannte Spalte nicht verwerfen
        #expect(lv.notizen.contains("Kundenbetreuer Telefon: 0201 123456"))
    }

    @Test func dezimalkommaUndTausenderpunkt() throws {
        let ergebnis = try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv"))
        let hausrat = ergebnis.vertraege[1]
        #expect(hausrat.beitrag == Decimal(string: "1234.56"))
        #expect(hausrat.zahlweise == .jaehrlich)
        #expect(hausrat.notizen == "Wohnung; inkl. Fahrrad")
        #expect(hausrat.betreuer == .direkt)
        #expect(ergebnis.vertraege[2].status == .pruefen)
        #expect(ergebnis.vertraege[3].status == .beitragsfrei)
        #expect(ergebnis.vertraege[3].jahresbeitrag == 0)
    }

    @Test func fehlerhafteZeileWirdMarkiert() throws {
        let ergebnis = try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv"))
        let unfall = ergebnis.vertraege[4]
        #expect(unfall.status == .pruefen)
        #expect(unfall.notizen.contains("Beginn: irgendwann"))
        #expect(unfall.zahlweise == .monatlich)
        #expect(ergebnis.warnungen.contains { $0.zeile == 5 && $0.text.contains("Keine Vertragsnummer") })
        #expect(ergebnis.warnungen.contains { $0.zeile == 5 && $0.text.contains("Datum") })
    }

    @Test func zugangsdatenWerdenNieGespeichert() {
        let t = CSVTabelle(kopf: ["Versicherer", "Vertragsnummer", "Passwort", "Portal-PIN", "Login"],
                           zeilen: [["X AG", "12345", "geheim", "0000", "max"]])
        let v = BestandImport.lesen(t, quelle: "test").vertraege[0]
        #expect(!v.notizen.contains("geheim"))
        #expect(!v.notizen.contains("0000"))
        #expect(!v.notizen.contains("max"))
    }
}

@Suite("Clark-Import")
struct ClarkImportTests {
    @Test func jsonWirdAbgeflacht() throws {
        let roh = try ClarkImport.lesen(try testdatei("clark_export.json"), dateiname: "clark_export.json")
        #expect(roh.datensaetze.count == 2)
        #expect(roh.felder.contains("insurer.name"))
        #expect(roh.felder.contains("premium.amount"))
        #expect(!roh.deutscheZahlen)
    }

    @Test func automatischeZuordnung() throws {
        let roh = try ClarkImport.lesen(try testdatei("clark_export.json"), dateiname: "clark_export.json")
        let z = Feldzuordnung.automatisch(fuer: roh.felder)
        #expect(z.ziel(fuer: "contract_number") == .vertragsnummer)
        #expect(z.ziel(fuer: "insurer.name") == .versicherer)
        #expect(z.ziel(fuer: "category.name") == .sparte)
        #expect(z.ziel(fuer: "premium.amount") == .beitrag)
        #expect(z.ziel(fuer: "payment_interval") == .zahlweise)
        #expect(z.ziel(fuer: "start_date") == .beginn)
        #expect(z.ziel(fuer: "end_date") == .ablauf)
        #expect(z.ziel(fuer: "state") == .status)
        #expect(z.ziel(fuer: "id") == .notizen)
    }

    @Test func unbekannteFelderInNotizen() throws {
        let roh = try ClarkImport.lesen(try testdatei("clark_export.json"), dateiname: "clark_export.json")
        let ergebnis = roh.importieren(mit: .automatisch(fuer: roh.felder))
        let lv = ergebnis.vertraege[0]
        #expect(lv.vertragsnummer == "LV12345678")
        #expect(lv.versicherer == "Beispiel Leben AG")
        #expect(lv.beitrag == 155)
        #expect(lv.zahlweise == .monatlich)
        #expect(lv.betreuer == .clark)
        #expect(lv.notizen.contains("insurer.bafin_id: 1234"))
        #expect(lv.notizen.contains("premium.currency: EUR"))
        #expect(lv.notizen.contains("advisor_comment: Dynamik 5 % jährlich"))
        let rs = ergebnis.vertraege[1]
        #expect(rs.status == .beendet)
        #expect(rs.beitrag == Decimal(string: "312.4"))
        #expect(rs.notizen.contains("tags: privat, beruf"))
    }

    @Test func handzuordnungUeberschreibt() throws {
        let roh = try ClarkImport.lesen(try testdatei("clark_export.json"), dateiname: "clark_export.json")
        var z = Feldzuordnung.automatisch(fuer: roh.felder)
        z.zuordnung["advisor_comment"] = .steuerlicheEinordnung
        z.zuordnung["insurer.bafin_id"] = .ignorieren
        let v = roh.importieren(mit: z).vertraege[0]
        #expect(v.steuerlicheEinordnung == "Dynamik 5 % jährlich")
        #expect(!v.notizen.contains("bafin"))
    }

    @Test func clarkCSV() throws {
        let csv = "Vertragsnummer;Versicherer;Beitrag;Zahlweise;Sonderfeld\nAB-12345;X AG;12,50;monatlich;Wert\n"
        let roh = try ClarkImport.lesen(Data(csv.utf8), dateiname: "clark.csv")
        let v = roh.importieren(mit: .automatisch(fuer: roh.felder)).vertraege[0]
        #expect(v.beitrag == Decimal(string: "12.5"))
        #expect(v.notizen == "Sonderfeld: Wert")
    }

    @Test func keineListe() {
        #expect(throws: ClarkImportFehler.self) {
            _ = try ClarkImport.json(Data("[1,2,3]".utf8), quelle: "x.json")
        }
    }
}

@Suite("NWO-Pay und Zuordnung")
struct PayTests {
    func bestand() throws -> [VertragsDaten] {
        try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv")).vertraege
    }

    @Test func liestZahlungen() throws {
        let (zahlungen, warnungen) = try PayImport.lesen(try testdatei("nwo_pay_2026.csv"))
        #expect(warnungen.isEmpty)
        #expect(zahlungen.count == 5)
        #expect(zahlungen[0].betrag == -150)
        #expect(zahlungen[0].externeID == "nwo-pay:P-0001")
        #expect(zahlungen[0].quelle == "NWO-Pay (DKB Giro, Lastschrift)")
        #expect(zahlungen[0].buchungstext == "Beispiel Leben AG – Beitrag LV 123 456 78 Jan 2026")
        #expect(zahlungen[3].betrag == 80)
        #expect(zahlungen[1].betrag == Decimal(string: "-1234.56"))
    }

    @Test func ordnetPerVertragsnummerZu() throws {
        let vertraege = try bestand()
        var (zahlungen, _) = try PayImport.lesen(try testdatei("nwo_pay_2026.csv"))
        let anzahl = ZahlungsZuordnung.zuordnen(&zahlungen, vertraege: vertraege)
        #expect(anzahl == 3)
        #expect(zahlungen[0].vertragID == vertraege[0].id) // "LV 123 456 78" ↔ "LV-123.456.78"
        #expect(zahlungen[1].vertragID == vertraege[1].id) // "HR-998877" ↔ "HR 998877"
        #expect(zahlungen[2].vertragID == nil)             // keine Nummer im Zweck
        #expect(zahlungen[3].vertragID == vertraege[2].id)
        #expect(zahlungen[4].vertragID == nil)             // „1998877123“ ist nicht HR 998877
    }

    @Test func keineTeiltreffer() {
        let v = VertragsDaten(versicherer: "X", vertragsnummer: "12345")
        #expect(ZahlungsZuordnung.vertrag(fuer: "Ref 9123456", in: [v]) == nil)
        #expect(ZahlungsZuordnung.vertrag(fuer: "VSNR 12345 Beitrag", in: [v]) == v.id)
        #expect(ZahlungsZuordnung.vertrag(fuer: "VSNR:12345/2026", in: [v]) == v.id)
        let kurz = VertragsDaten(versicherer: "Y", vertragsnummer: "123")
        #expect(ZahlungsZuordnung.vertrag(fuer: "123", in: [kurz]) == nil)
    }

    @Test func laengsteNummerGewinnt() {
        let a = VertragsDaten(versicherer: "A", vertragsnummer: "12345")
        let b = VertragsDaten(versicherer: "B", vertragsnummer: "12345-01")
        #expect(ZahlungsZuordnung.vertrag(fuer: "Beitrag 12345-01", in: [a, b]) == b.id)
    }
}

@Suite("Dubletten")
struct DublettenTests {
    @Test func erkenntGleicheVertraege() throws {
        let bestand = try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv")).vertraege
        let roh = try ClarkImport.lesen(try testdatei("clark_export.json"), dateiname: "clark_export.json")
        let neu = roh.importieren(mit: .automatisch(fuer: roh.felder)).vertraege
        let abgleich = Dubletten.abgleichen(bestand: bestand, importiert: neu)
        #expect(abgleich.konflikte.count == 1)
        #expect(abgleich.neu.count == 1)
        let k = try #require(abgleich.konflikte.first)
        #expect(k.bestand.id == bestand[0].id)
        let beitrag = try #require(k.unterschiede.first { $0.feld == .beitrag })
        #expect(beitrag.bestand == "150,00 €")
        #expect(beitrag.importiert == "155,00 €")
        #expect(!k.unterschiede.contains { $0.feld == .vertragsnummer })
    }

    @Test func gleicherImportIstUnveraendert() throws {
        let bestand = try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv")).vertraege
        let nochmal = try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv")).vertraege
        let abgleich = Dubletten.abgleichen(bestand: bestand, importiert: nochmal)
        #expect(abgleich.konflikte.isEmpty)
        #expect(abgleich.unveraendert.count == 4)
        #expect(abgleich.neu.count == 1) // Zeile ohne Nummer ist nie Dublette
    }

    @Test func versichererVarianten() {
        let a = VertragsDaten(versicherer: "Allianz Lebensversicherungs-AG", vertragsnummer: "AB 123")
        let b = VertragsDaten(versicherer: "Allianz", vertragsnummer: "ab-123")
        let c = VertragsDaten(versicherer: "Ergo", vertragsnummer: "AB123")
        #expect(Dubletten.gleich(a, b))
        #expect(!Dubletten.gleich(a, c))
    }

    @Test func dublettenInnerhalbDerDatei() {
        let a = VertragsDaten(versicherer: "X AG", vertragsnummer: "11111", beitrag: 10)
        let b = VertragsDaten(versicherer: "X", vertragsnummer: "11-111", beitrag: 12)
        let abgleich = Dubletten.abgleichen(bestand: [], importiert: [a, b])
        #expect(abgleich.neu.count == 1)
        #expect(abgleich.konflikte.count == 1)
    }

    @Test func loesungen() {
        let alt = VertragsDaten(versicherer: "X", vertragsnummer: "11111", tarif: "", beitrag: 10, notizen: "alt")
        let neu = VertragsDaten(versicherer: "X", vertragsnummer: "11111", tarif: "Komfort", beitrag: 12, notizen: "neu")
        let k = Dubletten.abgleichen(bestand: [alt], importiert: [neu]).konflikte[0]
        #expect(Dubletten.loesen(k, mit: .bestandBehalten) == alt)
        let uebernommen = Dubletten.loesen(k, mit: .importUebernehmen)
        #expect(uebernommen.id == alt.id)
        #expect(uebernommen.beitrag == 12)
        #expect(uebernommen.notizen.contains("alt"))
        let zusammen = Dubletten.loesen(k, mit: .zusammenfuehren)
        #expect(zusammen.beitrag == 10)
        #expect(zusammen.tarif == "Komfort")
        #expect(zusammen.notizen.contains("Import abweichend – Beitrag: 12,00 €"))
    }
}

@Suite("Auswertung")
struct AuswertungTests {
    let vertraege: [VertragsDaten] = [
        VertragsDaten(versicherer: "A", sparte: "Haftpflicht", vertragsnummer: "11111", beitrag: 60, zahlweise: .jaehrlich),
        VertragsDaten(versicherer: "B", sparte: "Haftpflicht", vertragsnummer: "22222", beitrag: 5, zahlweise: .monatlich),
        VertragsDaten(versicherer: "C", sparte: "Leben", vertragsnummer: "33333", beitrag: 100, zahlweise: .vierteljaehrlich),
        VertragsDaten(versicherer: "D", sparte: "Leben", vertragsnummer: "44444", beitrag: 999, zahlweise: .monatlich, status: .beendet),
        VertragsDaten(versicherer: "E", sparte: "", vertragsnummer: "55555", beitrag: 1, zahlweise: .halbjaehrlich, status: .pruefen)
    ]

    @Test func summenJeSparte() {
        let s = Uebersicht.nachSparte(vertraege)
        #expect(s.map(\.sparte) == ["Leben", "Haftpflicht", "Ohne Sparte"])
        #expect(s[0].jahresbeitrag == 400)
        #expect(s[0].anzahl == 1)
        #expect(s[1].jahresbeitrag == 120)
        #expect(s[1].monatsbeitrag == 10)
        #expect(Uebersicht.jahresbeitragGesamt(vertraege) == 522)
    }

    @Test func pruefliste() {
        var zahlungen = [
            ZahlungsDaten(datum: tag(2026, 2, 1), betrag: -5, buchungstext: "22222", quelle: "t", vertragID: vertraege[1].id),
            ZahlungsDaten(datum: tag(2025, 2, 1), betrag: -100, buchungstext: "33333", quelle: "t", vertragID: vertraege[2].id),
            ZahlungsDaten(datum: tag(2026, 3, 1), betrag: -7, buchungstext: "unbekannt", quelle: "t")
        ]
        zahlungen.sort { $0.datum < $1.datum }
        let p = Pruefliste.erstellen(vertraege: vertraege, zahlungen: zahlungen, jahr: 2026, stichtag: tag(2026, 11, 13))
        #expect(p.zuPruefen.map(\.vertragsnummer) == ["55555"])
        #expect(p.zahlungenOhneVertrag.count == 1)
        #expect(Set(p.ohneZahlungImJahr.map(\.vertragsnummer)) == ["11111", "33333"])
    }

    @Test func jaehrlicheFaelligkeitNochNichtErreicht() {
        let v = VertragsDaten(versicherer: "A", vertragsnummer: "11111", beginn: tag(2019, 12, 1), beitrag: 60, zahlweise: .jaehrlich)
        let p = Pruefliste.erstellen(vertraege: [v], zahlungen: [], jahr: 2026, stichtag: tag(2026, 11, 13))
        #expect(p.ohneZahlungImJahr.isEmpty)
    }

    @Test func beitragsverlauf() {
        let z = [
            ZahlungsDaten(datum: tag(2025, 1, 1), betrag: -10, buchungstext: "", quelle: ""),
            ZahlungsDaten(datum: tag(2025, 2, 1), betrag: -10, buchungstext: "", quelle: ""),
            ZahlungsDaten(datum: tag(2026, 1, 1), betrag: -11, buchungstext: "", quelle: ""),
            ZahlungsDaten(datum: tag(2026, 4, 1), betrag: 50, buchungstext: "Erstattung", quelle: "")
        ]
        let j = Beitragsverlauf.jeJahr(z)
        #expect(j.map(\.betrag) == [20, 11])
        #expect(Beitragsverlauf.einzeln(z).count == 3)
    }
}

@Suite("Fristen")
struct FristenTests {
    @Test func dauerLesen() {
        #expect(Fristen.dauer("3 Monate")! == (3, 0))
        #expect(Fristen.dauer("3 Monate zum Ablauf")! == (3, 0))
        #expect(Fristen.dauer("6 Wochen")! == (0, 42))
        #expect(Fristen.dauer("einen Monat")! == (1, 0))
        #expect(Fristen.dauer("") == nil)
    }

    @Test func kapitalauszahlungUndKuendigung() {
        let lv = VertragsDaten(versicherer: "Beispiel Leben", sparte: "Rente", vertragsnummer: "LV1",
                               beginn: tag(2008, 6, 1), ablauf: tag(2028, 6, 1), kuendigungsfrist: "3 Monate")
        let f = Fristen.berechnen(vertraege: [lv], stichtag: tag(2026, 11, 13))
        #expect(f.count == 2)
        #expect(f[0].art == .kuendigung)
        #expect(f[0].datum == tag(2028, 3, 1))
        #expect(f[0].erinnerung == tag(2028, 1, 31))
        #expect(f[1].art == .ablauf)
        #expect(f[1].datum == tag(2028, 6, 1))
        #expect(f[1].erinnerung == tag(2028, 3, 3))
    }

    @Test func hauptfaelligkeitOhneAblauf() {
        let hr = VertragsDaten(versicherer: "Muster", sparte: "Hausrat", vertragsnummer: "HR1",
                               beginn: tag(2019, 3, 15), kuendigungsfrist: "3 Monate")
        let f = Fristen.berechnen(vertraege: [hr], stichtag: tag(2026, 11, 13))
        #expect(f.count == 1)
        #expect(f[0].datum == tag(2026, 12, 15)) // Hauptfälligkeit 15.03.2027 minus 3 Monate
        // Kurz nach dem Termin rutscht die Frist ins Folgejahr
        let spaeter = Fristen.berechnen(vertraege: [hr], stichtag: tag(2026, 12, 20))
        #expect(spaeter[0].datum == tag(2027, 12, 15))
    }

    @Test func beendeteVertraegeOhneFristen() {
        let v = VertragsDaten(vertragsnummer: "X1", ablauf: tag(2030, 1, 1), kuendigungsfrist: "3 Monate", status: .beendet)
        #expect(Fristen.berechnen(vertraege: [v], stichtag: tag(2026, 1, 1)).isEmpty)
    }

    @Test func aufgabenAlsFrist() {
        let a = AufgabeDaten(titel: "Angebot vergleichen", faelligkeit: tag(2026, 12, 1), vertragID: nil)
        let erledigt = AufgabeDaten(titel: "alt", faelligkeit: tag(2026, 12, 1), vertragID: nil, erledigt: true)
        let f = Fristen.berechnen(vertraege: [], aufgaben: [a, erledigt], stichtag: tag(2026, 11, 13))
        #expect(f.map(\.titel) == ["Angebot vergleichen"])
    }
}

@Suite("Dokumenterkennung")
struct DokumenterkennungTests {
    let vertraege = [
        VertragsDaten(versicherer: "Beispiel Leben AG", vertragsnummer: "LV-123.456.78"),
        VertragsDaten(versicherer: "Muster Sach SE", vertragsnummer: "HR 998877")
    ]

    @Test func bekannteNummerImText() {
        let text = """
        Beispiel Leben AG · Postfach 1 · 12345 Musterstadt
        Musterstadt, den 15.01.2026
        Jahresbescheinigung 2025 zur Vorlage beim Finanzamt
        Versicherungsschein-Nr.: LV 123 456 78
        """
        let b = Dokumenterkennung.auswerten(text: text, vertraege: vertraege)
        #expect(b.vertragID == vertraege[0].id)
        #expect(b.typ == .jahresbescheinigung)
        #expect(b.datum == tag(2026, 1, 15))
        #expect(b.kandidaten == ["LV 123 456 78"])
    }

    @Test func unbekannteNummerAlsKandidat() {
        let text = "Nachtrag zum Versicherungsschein\nVertragsnummer: KFZ-2026/0815 vom 01.02.2026"
        let b = Dokumenterkennung.auswerten(text: text, vertraege: vertraege)
        #expect(b.vertragID == nil)
        #expect(b.kandidaten == ["KFZ-2026/0815"])
        #expect(b.typ == .nachtrag)
        #expect(b.datum == tag(2026, 2, 1))
    }

    @Test func dokumenttypen() {
        #expect(Dokumenterkennung.typ(in: "Ihre Beitragsrechnung 2026") == .beitragsrechnung)
        #expect(Dokumenterkennung.typ(in: "Versicherungsschein Hausrat") == .police)
        #expect(Dokumenterkennung.typ(in: "Hallo") == .sonstiges)
    }
}

@Suite("Export")
struct ExportTests {
    let lv = VertragsDaten(versicherer: "Beispiel Leben AG", sparte: "Rentenversicherung", vertragsnummer: "LV-123.456.78",
                           tarif: "Basisrente", beginn: tag(2008, 6, 1), ablauf: tag(2028, 6, 1), kuendigungsfrist: "3 Monate",
                           beitrag: 150, zahlweise: .monatlich, dynamikProzent: 5, steuerlicheEinordnung: "Schicht 1",
                           betreuer: .clark, notizen: "Kapitalauszahlung")

    @Test func csvMitGDVBegriffen() throws {
        let daten = BeraterExport.csv([lv])
        let t = try CSV.tabelle(aus: daten)
        #expect(t.kopf.first == "Versicherungsscheinnummer")
        #expect(t.kopf.contains("Zahlungsweise"))
        let d = t.datensaetze[0]
        #expect(d["Versicherungsscheinnummer"] == "LV-123.456.78")
        #expect(d["Beitrag"] == "150,00")
        #expect(d["Jahresbeitrag"] == "1800,00")
        #expect(d["Zahlungsweise"] == "monatlich")
        #expect(d["Vertragsablauf"] == "01.06.2028")
    }

    @Test func jsonRundreise() throws {
        let doc = DokumentDaten(pfad: "/tmp/Police LV.pdf", typ: .police, datum: tag(2008, 5, 20), vertragID: lv.id)
        let daten = try BeraterExport.json([lv], dokumente: [doc], erstellt: tag(2026, 11, 13))
        let h = try JSONDecoder().decode(BeraterExport.JSONHuelle.self, from: daten)
        #expect(h.Anzahl == 1)
        #expect(h.Vertraege[0].Versicherungsscheinnummer == "LV-123.456.78")
        #expect(h.Vertraege[0].Jahresbeitrag == 1800)
        #expect(h.Vertraege[0].Vertragsablauf == "2028-06-01")
        #expect(h.Vertraege[0].Dokumente[0].Datei == "Dokumente/Beispiel_Leben_AG_LV-123_456_78/2008-05-20_Police_Police_LV.pdf")
        #expect(String(decoding: daten, as: UTF8.self).contains("\"Zahlungsweise\" : \"monatlich\""))
    }

    @Test func zipStruktur() throws {
        let doc = DokumentDaten(pfad: "/x/Police.pdf", typ: .police, datum: nil, vertragID: lv.id)
        let fehlt = DokumentDaten(pfad: "/x/weg.pdf", typ: .nachtrag, datum: nil, vertragID: lv.id)
        let (zip, fehlend) = try BeraterExport.zip(vertraege: [lv], dokumente: [doc, fehlt], erstellt: tag(2026, 11, 13)) { pfad in
            pfad == "/x/Police.pdf" ? Data("%PDF-1.4 Test".utf8) : nil
        }
        #expect(fehlend == ["/x/weg.pdf"])
        #expect(zip.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        // Endsatz: 3 Einträge
        let ende = zip.suffix(22)
        #expect(Array(ende.prefix(4)) == [0x50, 0x4B, 0x05, 0x06])
        #expect(ende[ende.startIndex + 10] == 3)
        let text = String(decoding: zip, as: UTF8.self)
        #expect(text.contains("vertraege.csv"))
        #expect(text.contains("%PDF-1.4 Test"))
    }

    @Test func crc32() {
        #expect(CRC32.pruefsumme(Data("123456789".utf8)) == 0xCBF43926)
    }

    @Test func eindeutigeZipNamen() {
        let a = DokumentDaten(pfad: "/a/Brief.pdf", typ: .nachtrag, datum: nil, vertragID: nil)
        let b = DokumentDaten(pfad: "/b/Brief.pdf", typ: .nachtrag, datum: nil, vertragID: nil)
        let namen = BeraterExport.zipNamen(vertraege: [], dokumente: [a, b])
        #expect(Set(namen.values).count == 2)
    }
}

@Suite("Zuordnungsvorschläge")
struct VorschlagTests {
    func daten() throws -> ([VertragsDaten], [ZahlungsDaten]) {
        let v = try BestandImport.lesen(try testdatei("versicherungsbestand_2026-11.csv")).vertraege
        var (z, _) = try PayImport.lesen(try testdatei("nwo_pay_2026.csv"))
        ZahlungsZuordnung.zuordnen(&z, vertraege: v)
        return (v, z)
    }

    @Test func versichererUndBetrag() throws {
        let (v, z) = try daten()
        let offen = z[2] // Fiktiv Kranken – Beitrag 02/2026, 23,90
        #expect(offen.vertragID == nil)
        let vorschlaege = ZahlungsZuordnung.vorschlaege(fuer: offen, vertraege: v, zugeordnet: z)
        let erster = try #require(vorschlaege.first)
        #expect(erster.vertragID == v[2].id)
        #expect(erster.sicher)
        #expect(erster.punkte >= 90)
        #expect(erster.gruende.contains { $0.contains("Beitrag") })
    }

    @Test func fremdeZahlungOhneVorschlag() throws {
        let (v, z) = try daten()
        #expect(ZahlungsZuordnung.vorschlaege(fuer: z[4], vertraege: v, zugeordnet: z).isEmpty)
    }

    @Test func historieZaehlt() {
        let vertrag = VertragsDaten(versicherer: "Ganz Anders AG", vertragsnummer: "99999", beitrag: 30, zahlweise: .monatlich)
        let alt = ZahlungsDaten(datum: tag(2026, 1, 1), betrag: -31, buchungstext: "GA Service GmbH – Lastschrift", quelle: "t", vertragID: vertrag.id)
        let neu = ZahlungsDaten(datum: tag(2026, 2, 1), betrag: -31, buchungstext: "GA Service GmbH – Lastschrift", quelle: "t")
        let v = ZahlungsZuordnung.vorschlaege(fuer: neu, vertraege: [vertrag], zugeordnet: [alt])
        #expect(v.first?.punkte == 70) // Gegenpartei 30 + gleicher Betrag 20 + Betrag nahe Beitrag 20
        #expect(v.first?.sicher == false)
    }

    @Test func zweiGleichstarkeSindNichtSicher() {
        let a = VertragsDaten(versicherer: "Muster Sach SE", sparte: "Hausrat", vertragsnummer: "11111", beitrag: 10, zahlweise: .monatlich)
        let b = VertragsDaten(versicherer: "Muster Sach SE", sparte: "Glas", vertragsnummer: "22222", beitrag: 10, zahlweise: .monatlich)
        let z = ZahlungsDaten(datum: tag(2026, 1, 1), betrag: -10, buchungstext: "Muster Sach – Lastschrift", quelle: "t")
        let v = ZahlungsZuordnung.vorschlaege(fuer: z, vertraege: [a, b], zugeordnet: [])
        #expect(v.count == 2)
        #expect(!v.contains { $0.sicher })
    }
}

@Suite("Sicherung und Rückimport")
struct SicherungTests {
    @Test func rundreise() throws {
        let v = VertragsDaten(versicherer: "X", vertragsnummer: "12345", beginn: tag(2020, 1, 1), beitrag: Decimal(string: "12.34"),
                              zahlweise: .monatlich, notizen: "Ä Ö ü ß")
        let z = ZahlungsDaten(externeID: "nwo-pay:1", datum: tag(2026, 1, 2), betrag: Decimal(string: "-12.34")!,
                              buchungstext: "X – 12345", quelle: "NWO-Pay", vertragID: v.id)
        let d = Sicherung.Dokument(daten: DokumentDaten(pfad: "/a/b.pdf", typ: .police, datum: tag(2020, 1, 1), vertragID: v.id),
                                   erkannterText: "Versicherungsschein", kandidaten: "12345")
        let a = AufgabeDaten(titel: "Kündigen?", faelligkeit: tag(2026, 12, 1), vertragID: v.id)
        let s = Sicherung(erstellt: tag(2026, 11, 14), vertraege: [v], zahlungen: [z], dokumente: [d], aufgaben: [a])
        let gelesen = try Sicherung.lesen(try s.json())
        #expect(gelesen == s)
        #expect(gelesen.zusammenfassung == "1 Verträge, 1 Zahlungen, 1 Dokumente, 1 Aufgaben")
    }

    @Test func fremdeDateiWirdAbgelehnt() {
        #expect(throws: Sicherung.Fehler.keineSicherung) { _ = try Sicherung.lesen(Data("{\"a\":1}".utf8)) }
    }

    @Test func verwaisteVerweiseWerdenGeloest() throws {
        let z = ZahlungsDaten(datum: tag(2026, 1, 2), betrag: -1, buchungstext: "", quelle: "", vertragID: UUID())
        let s = Sicherung(erstellt: .now, vertraege: [], zahlungen: [z], dokumente: [], aufgaben: [])
        #expect(try Sicherung.lesen(try s.json()).zahlungen[0].vertragID == nil)
    }

    let lv = VertragsDaten(versicherer: "Beispiel Leben AG", sparte: "Rentenversicherung", vertragsnummer: "LV-123.456.78",
                           tarif: "Basisrente", beginn: tag(2008, 6, 1), ablauf: tag(2028, 6, 1), kuendigungsfrist: "3 Monate",
                           beitrag: 150, zahlweise: .monatlich, dynamikProzent: 5, status: .beitragsfrei,
                           steuerlicheEinordnung: "Schicht 1", betreuer: .neu, notizen: "Kapitalauszahlung")

    func ohneID(_ v: VertragsDaten) -> VertragsDaten { var x = v; x.id = lv.id; return x }

    @Test func jsonRueckimport() throws {
        let json = try BeraterExport.json([lv], erstellt: tag(2026, 11, 14))
        let e = try BeraterExport.vertraege(ausJSON: json, quelle: "vertraege.json")
        #expect(ohneID(e.vertraege[0]) == lv)
    }

    @Test func csvRueckimportOhneRauschen() throws {
        let csv = BeraterExport.csv([lv])
        let e = try BestandImport.lesen(csv, dateiname: "Vertraege.csv")
        #expect(ohneID(e.vertraege[0]) == lv)
        #expect(e.warnungen.isEmpty)
    }

    @Test func nurJahresbeitragBekannt() {
        let t = CSVTabelle(kopf: ["Versicherer", "VSNR", "Jahresbeitrag", "Zahlweise"], zeilen: [
            ["A AG", "11111", "120,00", "monatlich"],
            ["B AG", "22222", "89,50", ""]
        ])
        let v = BestandImport.lesen(t, quelle: "t").vertraege
        #expect(v[0].beitrag == 10)
        #expect(v[1].beitrag == Decimal(string: "89.5"))
        #expect(v[1].zahlweise == .jaehrlich)
    }

    @Test func widerspruechlicherJahresbeitragWirdNotiert() {
        let t = CSVTabelle(kopf: ["Versicherer", "VSNR", "Beitrag", "Zahlweise", "Jahresbeitrag"],
                           zeilen: [["A AG", "11111", "10,00", "monatlich", "130,00"]])
        let v = BestandImport.lesen(t, quelle: "t").vertraege[0]
        #expect(v.beitrag == 10)
        #expect(v.notizen == "Jahresbeitrag laut Quelle: 130,00 €")
    }
}
