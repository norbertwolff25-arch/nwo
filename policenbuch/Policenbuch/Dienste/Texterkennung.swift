import Foundation
import PDFKit
import Vision
import AppKit

/// Liest Text aus PDFs: zuerst die eingebettete Textebene (PDFKit), bei Scans per Vision-OCR.
/// Alles läuft lokal auf dem Mac, es werden keine Daten übertragen.
enum Texterkennung {
    /// Seiten mit weniger Zeichen gelten als Scan.
    static let mindestzeichenJeSeite = 40
    /// OCR auf die ersten Seiten begrenzen (Policen haben die Nummer vorn).
    static let maxSeitenOCR = 4

    nonisolated static func text(aus url: URL) -> String {
        guard let pdf = PDFDocument(url: url) else { return "" }
        var teile: [String] = []
        for i in 0..<pdf.pageCount {
            guard let seite = pdf.page(at: i) else { continue }
            let eingebettet = seite.string ?? ""
            if eingebettet.trimmingCharacters(in: .whitespacesAndNewlines).count >= mindestzeichenJeSeite {
                teile.append(eingebettet)
            } else if i < maxSeitenOCR {
                teile.append(ocr(seite))
            }
        }
        return teile.joined(separator: "\n")
    }

    nonisolated static func ocr(_ seite: PDFPage) -> String {
        let rahmen = seite.bounds(for: .mediaBox)
        // ca. 200 dpi
        let faktor: CGFloat = 200.0 / 72.0
        let groesse = NSSize(width: rahmen.width * faktor, height: rahmen.height * faktor)
        let bild = seite.thumbnail(of: groesse, for: .mediaBox)
        var proposed = CGRect(origin: .zero, size: groesse)
        guard let cg = bild.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return "" }
        return ocr(cg)
    }

    nonisolated static func ocr(_ bild: CGImage) -> String {
        let anfrage = VNRecognizeTextRequest()
        anfrage.recognitionLevel = .accurate
        anfrage.recognitionLanguages = ["de-DE", "en-US"]
        anfrage.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: bild, options: [:])
        do {
            try handler.perform([anfrage])
        } catch {
            return ""
        }
        let zeilen = (anfrage.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return zeilen.joined(separator: "\n")
    }

    /// Alle PDFs eines Ordners (rekursiv), sortiert.
    nonisolated static func pdfs(in ordner: URL) -> [URL] {
        guard let aufzaehlung = FileManager.default.enumerator(at: ordner, includingPropertiesForKeys: [.isRegularFileKey],
                                                               options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        var ergebnis: [URL] = []
        for case let url as URL in aufzaehlung where url.pathExtension.lowercased() == "pdf" {
            ergebnis.append(url)
        }
        return ergebnis.sorted { $0.path < $1.path }
    }
}
