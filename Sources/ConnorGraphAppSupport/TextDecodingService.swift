import Foundation
import CoreFoundation

public enum TextDecodingConfidence: String, Codable, Sendable, Equatable { case certain, high, medium, low, ambiguous }
public enum TextEncodingDetectionSource: String, Codable, Sendable, Equatable { case userOverride, byteOrderMark, declaredMetadata, strictUTFValidation, statisticalDetection, heuristicFallback }

public struct TextDecodingRequest: Sendable, Equatable {
    public var data: Data
    public var declaredEncoding: String?
    public var userSelectedEncoding: String?
    public var preferredEncodings: [String]
    public var allowLossy: Bool
    public init(data: Data, declaredEncoding: String? = nil, userSelectedEncoding: String? = nil, preferredEncodings: [String] = [], allowLossy: Bool = false) {
        self.data = data; self.declaredEncoding = declaredEncoding; self.userSelectedEncoding = userSelectedEncoding; self.preferredEncodings = preferredEncodings; self.allowLossy = allowLossy
    }
}

public struct TextDecodingResult: Sendable, Equatable {
    public var text: String
    public var encodingName: String
    public var confidence: TextDecodingConfidence
    public var detectionSource: TextEncodingDetectionSource
    public var hadBOM: Bool
    public var wasLossy: Bool
    public var replacementCharacterCount: Int
    public var controlCharacterCount: Int
    public var candidateEncodingNames: [String]
}

public enum TextDecodingError: Error, Sendable, Equatable { case unsupportedEncoding(String); case unableToDecode; case ambiguous([String]); case lossyDecodingNotAllowed }

public struct TextDecodingService: Sendable {
    public static let decoderVersion = "1"
    public init() {}

    public func decode(_ request: TextDecodingRequest) throws -> TextDecodingResult {
        if let name = request.userSelectedEncoding {
            return try explicit(request.data, name: name, source: .userOverride, confidence: .certain, allowLossy: request.allowLossy)
        }
        if let bom = detectBOM(request.data) {
            let body = request.data.dropFirst(bom.length)
            return try explicit(Data(body), name: bom.name, source: .byteOrderMark, confidence: .certain, allowLossy: false, hadBOM: true)
        }
        if let declared = request.declaredEncoding, let result = try? explicit(request.data, name: declared, source: .declaredMetadata, confidence: .high, allowLossy: false) { return result }
        if let utf8 = String(data: request.data, encoding: .utf8) {
            return result(utf8, name: "utf-8", confidence: request.data.allSatisfy { $0 < 128 } ? .medium : .high, source: .strictUTFValidation, hadBOM: false, wasLossy: false, candidates: ["utf-8"])
        }
        let candidates = unique(request.preferredEncodings + Self.defaultCandidates).compactMap { name -> Candidate? in
            guard let encoding = Self.encoding(named: name), let text = String(data: request.data, encoding: encoding) else { return nil }
            return Candidate(name: Self.normalized(name), text: text, score: qualityScore(text))
        }.sorted { $0.score < $1.score }
        guard let best = candidates.first else {
            guard request.allowLossy else { throw TextDecodingError.unableToDecode }
            let text = String(decoding: request.data, as: UTF8.self)
            return result(text, name: "utf-8-lossy", confidence: .low, source: .heuristicFallback, hadBOM: false, wasLossy: true, candidates: [])
        }
        let near = candidates.filter { $0.score <= best.score + 1 }.map(\.name)
        let confidence: TextDecodingConfidence = near.count > 1 ? .ambiguous : (best.score == 0 ? .medium : .low)
        return result(best.text, name: best.name, confidence: confidence, source: .statisticalDetection, hadBOM: false, wasLossy: false, candidates: Array(candidates.prefix(4).map(\.name)))
    }

    private func explicit(_ data: Data, name: String, source: TextEncodingDetectionSource, confidence: TextDecodingConfidence, allowLossy: Bool, hadBOM: Bool = false) throws -> TextDecodingResult {
        guard let encoding = Self.encoding(named: name) else { throw TextDecodingError.unsupportedEncoding(name) }
        if let text = String(data: data, encoding: encoding) { return result(text, name: Self.normalized(name), confidence: confidence, source: source, hadBOM: hadBOM, wasLossy: false, candidates: [Self.normalized(name)]) }
        guard allowLossy else { throw TextDecodingError.lossyDecodingNotAllowed }
        let text: String
        if encoding == .utf8 {
            text = String(decoding: data, as: UTF8.self)
        } else if let decoded = NSString(data: data, encoding: encoding.rawValue) as String? {
            text = decoded
        } else {
            throw TextDecodingError.unableToDecode
        }
        return result(text, name: Self.normalized(name), confidence: .low, source: source, hadBOM: hadBOM, wasLossy: true, candidates: [Self.normalized(name)])
    }

    private func result(_ text: String, name: String, confidence: TextDecodingConfidence, source: TextEncodingDetectionSource, hadBOM: Bool, wasLossy: Bool, candidates: [String]) -> TextDecodingResult {
        TextDecodingResult(text: text, encodingName: name, confidence: confidence, detectionSource: source, hadBOM: hadBOM, wasLossy: wasLossy, replacementCharacterCount: text.filter { $0 == "�" }.count, controlCharacterCount: text.unicodeScalars.filter { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t" }.count, candidateEncodingNames: candidates)
    }

    private func detectBOM(_ data: Data) -> (name: String, length: Int)? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x00,0x00,0xFE,0xFF]) { return ("utf-32be",4) }
        if bytes.starts(with: [0xFF,0xFE,0x00,0x00]) { return ("utf-32le",4) }
        if bytes.starts(with: [0xEF,0xBB,0xBF]) { return ("utf-8",3) }
        if bytes.starts(with: [0xFE,0xFF]) { return ("utf-16be",2) }
        if bytes.starts(with: [0xFF,0xFE]) { return ("utf-16le",2) }
        return nil
    }

    private struct Candidate { var name: String; var text: String; var score: Int }
    private func qualityScore(_ text: String) -> Int { text.filter { $0 == "�" }.count * 20 + text.unicodeScalars.filter { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t" }.count * 5 + ["Ã", "Â", "â€™", "锟斤拷"].reduce(0) { $0 + (text.contains($1) ? 10 : 0) } }
    private func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert(Self.normalized($0)).inserted } }

    private static let defaultCandidates = ["gb18030", "big5", "shift-jis", "euc-jp", "iso-2022-jp", "euc-kr", "windows-1252", "windows-1251", "windows-1250", "iso-8859-1", "iso-8859-2", "iso-8859-15", "koi8-r", "macintosh"]
    private static func normalized(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-") }
    public static func encoding(named raw: String) -> String.Encoding? {
        let name = normalized(raw)
        let cf: CFStringEncoding?
        switch name {
        case "utf-8", "utf8": return .utf8
        case "utf-16le": return .utf16LittleEndian
        case "utf-16be": return .utf16BigEndian
        case "utf-32le": return .utf32LittleEndian
        case "utf-32be": return .utf32BigEndian
        case "ascii": return .ascii
        case "gb2312", "gbk", "gb18030": cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        case "big5": cf = CFStringEncoding(CFStringEncodings.big5.rawValue)
        case "shift-jis", "cp932", "windows-31j": cf = CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
        case "euc-jp": cf = CFStringEncoding(CFStringEncodings.EUC_JP.rawValue)
        case "iso-2022-jp": cf = CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)
        case "euc-kr", "cp949": cf = CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        default:
            let detected = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            cf = detected == kCFStringEncodingInvalidId ? nil : detected
        }
        return cf.map { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding($0)) }
    }
}
