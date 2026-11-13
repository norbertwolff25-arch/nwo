import XCTest
@testable import ReisemanagerKern

final class GrundlagenTests: XCTestCase {
    func testTagLesenUndAbstand() {
        XCTAssertEqual(Tag(iso: "2026-01-25")?.iso, "2026-01-25")
        XCTAssertEqual(Tag(tagMonatJahr: "31/12/2024")?.iso, "2024-12-31")
        XCTAssertEqual(Tag(tagMonatJahr: "05.03.2026")?.iso, "2026-03-05")
        XCTAssertNil(Tag(iso: "2026"))
        XCTAssertNil(Tag(iso: "2026-02-30"))
        XCTAssertNil(Tag(tagMonatJahr: "12/31/2024"))
        XCTAssertEqual(Tag(iso: "2026-02-27")!.abstandInTagen(zu: Tag(iso: "2026-03-02")!), 3)
        XCTAssertEqual(Tag(iso: "2026-01-01")!.abstandInTagen(zu: Tag(iso: "2025-12-30")!), -2)
        XCTAssertLessThan(Tag(iso: "2026-09-29")!, Tag(iso: "2026-10-02")!)
    }

    func testGeldLesen() {
        XCTAssertEqual(Geld.cent(aus: "55,00"), 5500)
        XCTAssertEqual(Geld.cent(aus: "-2,99"), -299)
        XCTAssertEqual(Geld.cent(aus: "1.234,56"), 123456)
        XCTAssertEqual(Geld.cent(aus: "1,267.13"), 126713)
        XCTAssertEqual(Geld.cent(aus: "16.20"), 1620)
        XCTAssertEqual(Geld.cent(aus: "12,5"), 1250)
        XCTAssertEqual(Geld.cent(aus: "7"), 700)
        XCTAssertEqual(Geld.cent(aus: "1.234"), 123400)
        XCTAssertEqual(Geld.cent(aus: " 28,50 € "), 2850)
        XCTAssertNil(Geld.cent(aus: ""))
        XCTAssertNil(Geld.cent(aus: "offen"))
        XCTAssertNil(Geld.cent(aus: "12,345,6x"))
    }

    func testGeldSchreiben() {
        XCTAssertEqual(Geld.text(cent: 320432), "3.204,32")
        XCTAssertEqual(Geld.text(cent: -299), "-2,99")
        XCTAssertEqual(Geld.text(cent: 5), "0,05")
        XCTAssertEqual(Geld.text(cent: 123456789), "1.234.567,89")
    }

    func testCSVMitAnfuehrungUndZeilenumbruch() {
        let text = "\u{FEFF}a,b,c\r\n1,\"x, y\",\"Zeile 1\nZeile 2\"\r\n2,\"sagt \"\"hallo\"\"\",\n"
        let zeilen = CSV.zeilen(text, trenner: ",")
        XCTAssertEqual(zeilen.count, 3)
        XCTAssertEqual(zeilen[0], ["a", "b", "c"])
        XCTAssertEqual(zeilen[1], ["1", "x, y", "Zeile 1\nZeile 2"])
        XCTAssertEqual(zeilen[2], ["2", "sagt \"hallo\"", ""])
    }

    func testSHA256Pruefwerte() {
        XCTAssertEqual(SHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(SHA256.hex(Data(repeating: 0x61, count: 1000)),
                       "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func testAbrechnungstitel() {
        let t = { Tag(iso: $0)! }
        XCTAssertEqual(Abrechnungstitel.zeitraum(beginn: t("2026-01-25"), ende: t("2026-01-28")), "25.-28.01.26")
        XCTAssertEqual(Abrechnungstitel.zeitraum(beginn: t("2026-09-29"), ende: t("2026-10-02")), "29.09.-02.10.26")
        XCTAssertEqual(Abrechnungstitel.zeitraum(beginn: t("2026-10-22"), ende: t("2026-10-22")), "22.10.26")
        XCTAssertEqual(Abrechnungstitel.zeitraum(beginn: t("2026-12-30"), ende: t("2027-01-02")), "30.12.26-02.01.27")
        XCTAssertEqual(try Abrechnungstitel.bilden(anlass: "Kongress", ort: "Wien", beginn: t("2026-01-25"), ende: t("2026-01-28")).get(),
                       "Kongress Wien 25.-28.01.26")
        XCTAssertEqual(try Abrechnungstitel.bilden(anlass: "Tagung+Kd", ort: "Bonn", beginn: t("2026-09-29"), ende: t("2026-10-02")).get(),
                       "Tagung+Kd Bonn 29.09.-02.10.26")
        // Ort schon im Anlass: nicht doppelt nennen.
        XCTAssertEqual(try Abrechnungstitel.bilden(anlass: "Messe Essen", ort: "Essen", beginn: t("2026-10-27"), ende: t("2026-10-28")).get(),
                       "Messe Essen 27.-28.10.26")
        // Zu lang: melden, nicht stillschweigend kürzen.
        let zuLang = Abrechnungstitel.bilden(anlass: "Fachkonferenz Agenten Europa", ort: "Rotterdam", beginn: t("2026-09-16"), ende: t("2026-09-19"))
        guard case .failure(let fehler) = zuLang else { return XCTFail("Titel hätte zu lang sein müssen") }
        XCTAssertGreaterThan(fehler.laenge, 32)
        XCTAssertTrue(Abrechnungstitel.istGueltig("Konferenz Rotterdam 16.-19.09.26"))
        XCTAssertFalse(Abrechnungstitel.istGueltig("Fachkonferenz Agenten Europa Rotterdam 16.-19.09.26"))
    }
}
