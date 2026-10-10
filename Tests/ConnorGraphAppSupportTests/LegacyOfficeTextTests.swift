import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Legacy Office attachments")
struct LegacyOfficeTextTests {
    @Test func extractsRealBinaryWordExcelAndPowerPoint() async throws {
        for (ext, kind, expected) in [("doc", AgentAttachmentKind.document, "旧版 Word 中文正文"), ("xls", .spreadsheet, "A1=销售额"), ("ppt", .presentation, "旧版 PPT 中文正文")] {
            let url = try #require(Bundle.module.url(forResource: "legacy", withExtension: ext, subdirectory: "LegacyOffice"))
            let result = try OfficeAttachmentTextExtraction.extract(fileURL: url)
            #expect(result.report.status == .extracted)
            let text = try #require(result.extractedMarkdown)
            #expect(text.contains(expected))
            if ext == "xls" {
                #expect(text.contains("B1=42.5"))
                #expect(text.contains("C1=TRUE"))
                #expect(text.contains("第二张工作表"))
                #expect(text.contains(String(repeating: "续行中文", count: 2500)))
            }
            if ext == "ppt" {
                #expect(text.contains("Second slide 456"))
                #expect(try #require(text.range(of: "第一页标题")).lowerBound < #require(text.range(of: "第二页标题")).lowerBound)
            }
            let manifest = AgentAttachmentManifest(id: "legacy", displayName: "legacy.\(ext)", originalFilename: "legacy.\(ext)", normalizedFilename: "legacy.\(ext)", kind: kind, byteCount: Int64(try Data(contentsOf: url).count), sha256: "fixture", lifecycleStatus: .ready, extractionStatus: .pending, storedRelativePath: "legacy.\(ext)", manifestRelativePath: "manifest.json", createdAt: Date(), updatedAt: Date())
            let request = AttachmentExtractionRequest(sessionID: "s", manifest: manifest, originalFileURL: url, derivativesDirectoryURL: url.deletingLastPathComponent())
            #expect(try await AttachmentExtractionOrchestrator(sidecars: []).extract(request).report.status == .extracted)
        }
    }
    @Test func rejectsMalformedCompoundFiles() throws {
        let url = try #require(Bundle.module.url(forResource: "legacy", withExtension: "doc", subdirectory: "LegacyOffice"))
        var data = try Data(contentsOf: url)
        data.replaceSubrange(48..<52, with: [0xfe, 0xff, 0xff, 0xff])
        #expect(throws: (any Error).self) { try LegacyOfficeText.extract(data, fileExtension: "doc") }
        #expect(throws: (any Error).self) { try LegacyOfficeText.extract(Data("invalid".utf8), fileExtension: "xls") }
    }
}
