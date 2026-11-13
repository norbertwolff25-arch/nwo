import Foundation
import SwiftData
import PolicenbuchKern

@Model
final class Vertrag {
    @Attribute(.unique) var id: UUID
    var versicherer: String
    var sparte: String
    var vertragsnummer: String
    var tarif: String
    var beginn: Date?
    var ablauf: Date?
    var kuendigungsfrist: String
    var beitrag: Decimal?
    var zahlweiseRoh: String?
    var dynamikProzent: Decimal?
    var statusRoh: String
    var steuerlicheEinordnung: String
    var betreuerRoh: String?
    var notizen: String
    var angelegt: Date

    @Relationship(deleteRule: .nullify, inverse: \Dokument.vertrag) var dokumente: [Dokument] = []
    @Relationship(deleteRule: .nullify, inverse: \Zahlung.vertrag) var zahlungen: [Zahlung] = []
    @Relationship(deleteRule: .cascade, inverse: \Aufgabe.vertrag) var aufgaben: [Aufgabe] = []

    init(_ d: VertragsDaten) {
        id = d.id
        versicherer = d.versicherer
        sparte = d.sparte
        vertragsnummer = d.vertragsnummer
        tarif = d.tarif
        beginn = d.beginn
        ablauf = d.ablauf
        kuendigungsfrist = d.kuendigungsfrist
        beitrag = d.beitrag
        zahlweiseRoh = d.zahlweise?.rawValue
        dynamikProzent = d.dynamikProzent
        statusRoh = d.status.rawValue
        steuerlicheEinordnung = d.steuerlicheEinordnung
        betreuerRoh = d.betreuer?.rawValue
        notizen = d.notizen
        angelegt = .now
    }

    var status: VertragsStatus {
        get { VertragsStatus(rawValue: statusRoh) ?? .pruefen }
        set { statusRoh = newValue.rawValue }
    }

    var zahlweise: Zahlweise? {
        get { zahlweiseRoh.flatMap(Zahlweise.init(rawValue:)) }
        set { zahlweiseRoh = newValue?.rawValue }
    }

    var betreuer: Betreuer? {
        get { betreuerRoh.flatMap(Betreuer.init(rawValue:)) }
        set { betreuerRoh = newValue?.rawValue }
    }

    var daten: VertragsDaten {
        VertragsDaten(id: id, versicherer: versicherer, sparte: sparte, vertragsnummer: vertragsnummer, tarif: tarif,
                      beginn: beginn, ablauf: ablauf, kuendigungsfrist: kuendigungsfrist, beitrag: beitrag,
                      zahlweise: zahlweise, dynamikProzent: dynamikProzent, status: status,
                      steuerlicheEinordnung: steuerlicheEinordnung, betreuer: betreuer, notizen: notizen)
    }

    /// Übernimmt alle Felder außer der ID.
    func uebernehmen(_ d: VertragsDaten) {
        versicherer = d.versicherer
        sparte = d.sparte
        vertragsnummer = d.vertragsnummer
        tarif = d.tarif
        beginn = d.beginn
        ablauf = d.ablauf
        kuendigungsfrist = d.kuendigungsfrist
        beitrag = d.beitrag
        zahlweise = d.zahlweise
        dynamikProzent = d.dynamikProzent
        status = d.status
        steuerlicheEinordnung = d.steuerlicheEinordnung
        betreuer = d.betreuer
        notizen = d.notizen
    }

    var titel: String {
        let name = versicherer.isEmpty ? "Unbekannter Versicherer" : versicherer
        return sparte.isEmpty ? name : "\(name) · \(sparte)"
    }

    var jahresbeitrag: Decimal { daten.jahresbeitrag }
}

@Model
final class Zahlung {
    @Attribute(.unique) var id: UUID
    var externeID: String?
    var datum: Date
    var betrag: Decimal
    var buchungstext: String
    var quelle: String
    var vertrag: Vertrag?

    init(_ d: ZahlungsDaten, vertrag: Vertrag? = nil) {
        id = d.id
        externeID = d.externeID
        datum = d.datum
        betrag = d.betrag
        buchungstext = d.buchungstext
        quelle = d.quelle
        self.vertrag = vertrag
    }

    var daten: ZahlungsDaten {
        ZahlungsDaten(id: id, externeID: externeID, datum: datum, betrag: betrag, buchungstext: buchungstext,
                      quelle: quelle, vertragID: vertrag?.id)
    }
}

@Model
final class Dokument {
    @Attribute(.unique) var id: UUID
    var pfad: String
    var typRoh: String
    var datum: Date?
    var vertrag: Vertrag?
    /// Per PDFKit oder Vision erkannter Text (bleibt lokal, dient der Suche und Nachzuordnung).
    var erkannterText: String
    /// Im Text gefundene, aber keinem Vertrag zuordenbare Nummern.
    var kandidaten: String
    var eingelesen: Date

    init(pfad: String, typ: DokumentTyp, datum: Date?, vertrag: Vertrag?, erkannterText: String = "", kandidaten: [String] = []) {
        id = UUID()
        self.pfad = pfad
        typRoh = typ.rawValue
        self.datum = datum
        self.vertrag = vertrag
        self.erkannterText = erkannterText
        self.kandidaten = kandidaten.joined(separator: ", ")
        eingelesen = .now
    }

    var typ: DokumentTyp {
        get { DokumentTyp(rawValue: typRoh) ?? .sonstiges }
        set { typRoh = newValue.rawValue }
    }

    var dateiname: String { (pfad as NSString).lastPathComponent }
    var url: URL { URL(fileURLWithPath: pfad) }
    var existiert: Bool { FileManager.default.fileExists(atPath: pfad) }

    var daten: DokumentDaten {
        DokumentDaten(id: id, pfad: pfad, typ: typ, datum: datum, vertragID: vertrag?.id)
    }
}

@Model
final class Aufgabe {
    @Attribute(.unique) var id: UUID
    var titel: String
    var faelligkeit: Date?
    var erledigt: Bool
    var vertrag: Vertrag?

    init(titel: String, faelligkeit: Date?, vertrag: Vertrag?, erledigt: Bool = false) {
        id = UUID()
        self.titel = titel
        self.faelligkeit = faelligkeit
        self.vertrag = vertrag
        self.erledigt = erledigt
    }

    var daten: AufgabeDaten {
        AufgabeDaten(id: id, titel: titel, faelligkeit: faelligkeit, vertragID: vertrag?.id, erledigt: erledigt)
    }
}
