import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Text decoding service")
struct TextDecodingServiceTests {
    let service = TextDecodingService()

    @Test("Detects and removes UTF-8 BOM")
    func utf8BOM() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("# 笔记".utf8)
        let result = try service.decode(.init(data: data))
        #expect(result.text == "# 笔记")
        #expect(result.encodingName == "utf-8")
        #expect(result.hadBOM)
        #expect(result.confidence == .certain)
    }

    @Test("Detects UTF-16 little endian BOM")
    func utf16LE() throws {
        let text = "中文笔记"
        let body = text.data(using: .utf16LittleEndian)!
        let result = try service.decode(.init(data: Data([0xFF, 0xFE]) + body))
        #expect(result.text == text)
        #expect(result.encodingName == "utf-16le")
    }

    @Test("Explicit GB18030 decodes simplified Chinese")
    func gb18030() throws {
        let encoding = TextDecodingService.encoding(named: "gb18030")!
        let data = "简体中文笔记".data(using: encoding)!
        let result = try service.decode(.init(data: data, userSelectedEncoding: "gb18030"))
        #expect(result.text == "简体中文笔记")
        #expect(result.detectionSource == .userOverride)
    }

    @Test("Explicit Big5 decodes traditional Chinese")
    func big5() throws {
        let encoding = TextDecodingService.encoding(named: "big5")!
        let data = "繁體中文筆記".data(using: encoding)!
        #expect(try service.decode(.init(data: data, userSelectedEncoding: "big5")).text == "繁體中文筆記")
    }

    @Test("Explicit Shift-JIS decodes Japanese")
    func shiftJIS() throws {
        let encoding = TextDecodingService.encoding(named: "shift-jis")!
        let data = "日本語ノート".data(using: encoding)!
        #expect(try service.decode(.init(data: data, userSelectedEncoding: "shift-jis")).text == "日本語ノート")
    }

    @Test("Declared Windows-1252 preserves smart punctuation")
    func windows1252() throws {
        let encoding = TextDecodingService.encoding(named: "windows-1252")!
        let data = "“commercial” — note".data(using: encoding)!
        let result = try service.decode(.init(data: data, declaredEncoding: "windows-1252"))
        #expect(result.text == "“commercial” — note")
        #expect(result.detectionSource == .declaredMetadata)
    }

    @Test("Strict UTF-8 wins before permissive legacy encodings")
    func strictUTF8() throws {
        let result = try service.decode(.init(data: Data("康纳同学".utf8), preferredEncodings: ["windows-1252"]))
        #expect(result.encodingName == "utf-8")
        #expect(result.text == "康纳同学")
    }

    @Test("Unsupported explicit encoding is reported")
    func unsupportedEncoding() {
        #expect(throws: TextDecodingError.unsupportedEncoding("not-a-real-encoding")) {
            _ = try service.decode(.init(data: Data([0x80]), userSelectedEncoding: "not-a-real-encoding"))
        }
    }

    @Test("Lossy UTF-8 fallback is opt-in")
    func lossyFallback() throws {
        let impossible = Data([0x81])
        #expect(throws: TextDecodingError.lossyDecodingNotAllowed) {
            _ = try service.decode(.init(data: impossible, userSelectedEncoding: "utf-8"))
        }
        let lossy = try service.decode(.init(data: impossible, userSelectedEncoding: "utf-8", allowLossy: true))
        #expect(lossy.wasLossy)
        #expect(lossy.replacementCharacterCount > 0)
    }
}
