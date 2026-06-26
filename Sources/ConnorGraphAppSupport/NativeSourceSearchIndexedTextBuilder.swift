import Foundation
import ConnorGraphCore

public enum NativeSourceSearchIndexedTextBuilder {
    public static func searchableText(for document: NativeSearchDocument) -> String {
        let rawParts = [
            document.title,
            document.summary,
            document.participants.joined(separator: " "),
            document.location ?? "",
            document.body ?? "",
            document.metadata.values.joined(separator: " ")
        ]
        let raw = rawParts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let cjk = cjkIndexTerms(in: raw).joined(separator: " ")
        return [raw, cjk]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func cjkIndexTerms(in text: String) -> [String] {
        var terms: [String] = []
        for run in cjkRuns(in: text) {
            let normalized = NativeSearchQueryNormalizer.normalize(run)
            terms.append(contentsOf: normalized.tokens.map(\.value))
        }
        var seen: Set<String> = []
        return terms.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func cjkRuns(in text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { runs.append(current) }
            current = ""
        }
        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return runs
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}
