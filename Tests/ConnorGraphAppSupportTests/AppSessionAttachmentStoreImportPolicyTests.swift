import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("App Session Attachment Store Import Policy Tests")
struct AppSessionAttachmentStoreImportPolicyTests {
    @Test func importsAcceptedTextFileIntoCurrentAndRunDerivatives() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("notes.md")
        try "# Notes".write(to: source, atomically: true, encoding: .utf8)

        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s", now: Date(timeIntervalSince1970: 1))

        #expect(manifest.kind == .markdown)
        #expect(manifest.extractedTextRelativePath == "attachments/\(manifest.id)/derivatives/current/extracted.md")
        #expect(manifest.derivativeRefs.contains { $0.relativePath.contains("/derivatives/runs/") })
        let currentURL = paths.sessionArtifactDirectories(sessionID: "s").root.appendingPathComponent(manifest.extractedTextRelativePath!)
        #expect(FileManager.default.fileExists(atPath: currentURL.path))
    }

    @Test func rejectsUnsupportedHTMLWithoutCreatingAttachmentLedger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("page.html")
        try "<html></html>".write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s")
            Issue.record("Expected HTML import to be rejected")
        } catch let error as AppSessionAttachmentImportError {
            #expect(error == .rejected(filename: "page.html", reason: .unsupportedHTML))
        }

        let ledgerURL = paths.sessionArtifactDirectories(sessionID: "s").attachments.appendingPathComponent("attachment-manifest.jsonl")
        #expect(!FileManager.default.fileExists(atPath: ledgerURL.path))
    }

    @Test func rejectsTextAttachmentWhoseContentExceedsTotalBudgetWithoutLeavingArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("long.txt")
        try String(repeating: "长", count: 120_001).write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s")
            Issue.record("Expected total-budget import to be rejected")
        } catch let error as AppSessionAttachmentImportError {
            if case .rejected(let filename, let reason) = error {
                #expect(filename == "long.txt")
                if case .totalAttachmentBudgetExceeded = reason {} else {
                    Issue.record("Expected .totalAttachmentBudgetExceeded, got \(reason)")
                }
            } else {
                Issue.record("Expected .rejected, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let attachmentsDir = paths.sessionArtifactDirectories(sessionID: "s").attachments
        #expect(!FileManager.default.fileExists(atPath: attachmentsDir.path))
    }

    @Test func acceptsTextAttachmentBelowTotalBudgetWithoutPerFileCharacterLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("medium.txt")
        // 30,000 字符远大于旧的单附件上限，但在 60,000 字符总量内，应完整导入。
        try String(repeating: "中", count: 30_000).write(to: source, atomically: true, encoding: .utf8)

        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s")

        #expect(manifest.kind == .text)
        #expect(manifest.extractionStatus == .extracted)
        #expect(manifest.extractedTextRelativePath != nil)
        let stored = try String(
            contentsOf: paths.sessionArtifactDirectories(sessionID: "s").root
                .appendingPathComponent(manifest.extractedTextRelativePath!),
            encoding: .utf8
        )
        #expect(stored.count == 30_000)
    }

    @Test func importsImageAsStoredAttachmentWithoutTextDerivative() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s", now: Date(timeIntervalSince1970: 1))

        #expect(manifest.kind == .image)
        #expect(manifest.mimeType == "image/png")
        #expect(manifest.extractionStatus == .unsupported)
        #expect(manifest.extractedTextRelativePath == nil)
        #expect(manifest.derivativeRefs.isEmpty)
        let storedURL = paths.sessionArtifactDirectories(sessionID: "s").root.appendingPathComponent(manifest.storedRelativePath)
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
    }

    @Test func importsAudioWithMetadataAndReloadsManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("tone.wav")
        try Self.makePCM16WAV(sampleRate: 24_000, frameCount: 2_400).write(to: source)

        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: source, sessionID: "s", now: Date(timeIntervalSince1970: 1))
        let reloaded = try store.loadManifest(sessionID: "s", attachmentID: manifest.id)
        let jobs = try AttachmentExtractionJobStore(paths: paths).load(sessionID: "s")

        #expect(reloaded.kind == .audio)
        #expect(reloaded.mimeType == "audio/wav")
        #expect(reloaded.extractionStatus == .unsupported)
        #expect(reloaded.mediaMetadata?.sampleRate == 24_000)
        #expect(reloaded.mediaMetadata?.channelCount == 1)
        #expect(abs((reloaded.mediaMetadata?.durationSeconds ?? 0) - 0.1) < 0.001)
        #expect(jobs.isEmpty)
    }

    @Test func importsCommercialDocumentsAsPendingQueuedAttachments() throws {
        let cases: [(String, AgentAttachmentKind, [String])] = [
            ("paper.pdf", .pdf, ["pdf-selectable-text", "document-to-markdown"]),
            ("report.docx", .document, ["document-to-markdown"]),
            ("sheet.xlsx", .spreadsheet, ["document-to-markdown"]),
            ("slides.pptx", .presentation, ["document-to-markdown"])
        ]
        for (filename, expectedKind, expectedCapabilities) in cases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let paths = AppStoragePaths(applicationSupportDirectory: root)
            try paths.ensureDirectoryHierarchy()
            let source = root.appendingPathComponent(filename)
            try Data("document".utf8).write(to: source)

            let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s", now: Date(timeIntervalSince1970: 1))
            let jobs = try AttachmentExtractionJobStore(paths: paths).load(sessionID: "s")

            #expect(manifest.kind == expectedKind)
            #expect(manifest.extractionStatus == .pending)
            #expect(manifest.extractedTextRelativePath == nil)
            #expect(manifest.derivativeRefs.isEmpty)
            #expect(jobs.count == 1)
            #expect(jobs.first?.attachmentID == manifest.id)
            #expect(jobs.first?.requestedCapabilities == expectedCapabilities)
            let storedURL = paths.sessionArtifactDirectories(sessionID: "s").root.appendingPathComponent(manifest.storedRelativePath)
            #expect(FileManager.default.fileExists(atPath: storedURL.path))
        }
    }

    @Test func rejectsArchiveButAcceptsDocumentsAudioAndVideo() throws {
        let policy = AttachmentImportPolicy()
        for file in ["report.docx", "paper.pdf", "slides.pptx", "clip.mp4", "voice.m4a"] {
            if case .rejected(let reason) = policy.validate(url: URL(fileURLWithPath: "/tmp/\(file)")) {
                Issue.record("Expected \(file) to be accepted, rejected with \(reason)")
            }
        }
        for file in ["archive.zip"] {
            let result = policy.validate(url: URL(fileURLWithPath: "/tmp/\(file)"))
            if case .accepted = result {
                Issue.record("Expected \(file) to be rejected")
            }
        }
    }

    private static func makePCM16WAV(sampleRate: UInt32, frameCount: UInt32) -> Data {
        let dataSize = frameCount * 2
        var data = Data()
        func appendASCII(_ value: String) { data.append(Data(value.utf8)) }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        appendASCII("RIFF")
        appendUInt32(36 + dataSize)
        appendASCII("WAVEfmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(sampleRate)
        appendUInt32(sampleRate * 2)
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}
