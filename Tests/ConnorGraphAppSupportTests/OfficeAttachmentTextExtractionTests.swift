import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Office attachments")
struct OfficeAttachmentTextExtractionTests {
    @Test func extractsWordSpreadsheetAndSlides() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let docx = root.appendingPathComponent("sample.docx")
        try Data(base64Encoded: "UEsDBBQAAAAIAMiNSl0JKT+/TwAAAH0AAAARAAAAd29yZC9kb2N1bWVudC54bWyzKbdKyU8uzU3NK1GoyM3JK7Yqt1UqLcqzKleysym3SspPqQTRBSCiCESU2D1du/jprmU2+iA2iCxCknvWtfTpxC4UOX2wbn2YWfoIC+0AUEsBAhQDFAAAAAgAyI1KXQkpP79PAAAAfQAAABEAAAAAAAAAAAAAAIABAAAAAHdvcmQvZG9jdW1lbnQueG1sUEsFBgAAAAABAAEAPwAAAH4AAAAAAA==")!.write(to: docx)
        let docxResult = try OfficeAttachmentTextExtraction.extract(fileURL: docx)
        #expect(docxResult.report.status == .extracted)
        let xlsx = root.appendingPathComponent("sample.xlsx")
        try Data(base64Encoded: "UEsDBBQAAAAIAMiNSl1mZ0QZMgAAADIAAAAUAAAAeGwvc2hhcmVkU3RyaW5ncy54bWyzKS4uUajIzckrtlUqLcqzKlaysynOtLMpsXs5peHplHUvF8210S+xs9EHCeoDFdsBAFBLAwQUAAAACADIjUpdcfoCfXgAAACsAAAAGAAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbLMpzy/KLs5ITS1RqMjNySu2VSotyrMqVrKzAQu6JJYk2tkU5Zfb2SQrFNkqORoqKZTYKoHky+wMbPTL7Gz0k6FyToZgURMjVGFniJbMvJzMvNTgkiKgosxiO5sSuyc71j6b1m6jXwJUDBIB6dAHW6WPZLc+3IF2AFBLAQIUAxQAAAAIAMiNSl1mZ0QZMgAAADIAAAAUAAAAAAAAAAAAAACAAQAAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbFBLAQIUAxQAAAAIAMiNSl1x+gJ9eAAAAKwAAAAYAAAAAAAAAAAAAACAAWQAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAIAAgCIAAAAEgEAAAAA")!.write(to: xlsx)
        let xlsxResult = try OfficeAttachmentTextExtraction.extract(fileURL: xlsx)
        #expect(xlsxResult.report.status == .extracted)
        let pptx = root.appendingPathComponent("sample.pptx")
        try Data(base64Encoded: "UEsDBBQAAAAIAMiNSl1bN+WoQQAAAFkAAAAWAAAAcHB0L3NsaWRlcy9zbGlkZTEwLnhtbLMpsCrOSVGoyM3JK7YqsFUqLcqzKlCC8hMh/EQlO5tEqwIQUQQiSuyer1nztLfx5cKtNvogLogsApNARfpgE+0AUEsDBBQAAAAIAMiNSl2eSO9tQgAAAFkAAAAVAAAAcHB0L3NsaWRlcy9zbGlkZTIueG1ssymwKs5JUajIzckrtiqwVSotyrMqUILyEyH8RCU7m0SrAhBRBCJK7J6vWfNkV8/LhVtt9EFcEFkEJoGK9MEm2gEAUEsBAhQDFAAAAAgAyI1KXVs35ahBAAAAWQAAABYAAAAAAAAAAAAAAIABAAAAAHBwdC9zbGlkZXMvc2xpZGUxMC54bWxQSwECFAMUAAAACADIjUpdnkjvbUIAAABZAAAAFQAAAAAAAAAAAAAAgAF1AAAAcHB0L3NsaWRlcy9zbGlkZTIueG1sUEsFBgAAAAACAAIAhwAAAOoAAAAAAA==")!.write(to: pptx)
        let pptxResult = try OfficeAttachmentTextExtraction.extract(fileURL: pptx)
        #expect(pptxResult.report.status == .extracted)
        #expect(docxResult.extractedMarkdown?.contains("季度报告") == true)
        #expect(xlsxResult.extractedMarkdown?.contains("A1=销售额\tB1=42\tC1=中文") == true)
        let slides = try #require(pptxResult.extractedMarkdown)
        #expect(try #require(slides.range(of: "第二页")).lowerBound < #require(slides.range(of: "第十页")).lowerBound)
    }
    @Test func corruptOfficeFileReportsFailure() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        #expect(try OfficeAttachmentTextExtraction.extract(fileURL: url).report.status == .failed)
    }
}
