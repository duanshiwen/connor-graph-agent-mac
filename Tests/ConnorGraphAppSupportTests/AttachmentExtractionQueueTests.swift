import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Attachment Extraction Queue Tests")
struct AttachmentExtractionQueueTests {
    @Test func jobStorePersistsQueuedJobs() throws {
        let paths = try tempPaths()
        let store = AttachmentExtractionJobStore(paths: paths)
        let job = AgentAttachmentExtractionJob(
            id: "job",
            sessionID: "s",
            attachmentID: "a",
            requestedCapabilities: ["document-to-markdown"],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try store.append(job)
        let jobs = try store.load(sessionID: "s")

        #expect(jobs == [job])
    }

    @Test func jobStoreRecoversRunningJobsAsQueued() throws {
        let paths = try tempPaths()
        let store = AttachmentExtractionJobStore(paths: paths)
        let running = AgentAttachmentExtractionJob(id: "job", sessionID: "s", attachmentID: "a", status: .running, attempt: 1)
        try store.append(running)

        let recovered = try store.recoverInterruptedJobs(sessionID: "s", now: Date(timeIntervalSince1970: 10))

        #expect(recovered.count == 1)
        #expect(recovered[0].status == .queued)
        #expect(recovered[0].lastError?.contains("interrupted") == true)
    }

    @Test func processorWritesDerivativeAndUpdatesManifestOnSuccess() async throws {
        let paths = try tempPaths()
        let sessionID = "s"
        let manifest = try seedAttachment(paths: paths, sessionID: sessionID, attachmentID: "a", filename: "report.docx", kind: .document)
        let processor = AttachmentExtractionJobProcessor(
            paths: paths,
            extractor: StaticAttachmentExtractor(result: .success(markdown: "# Extracted\nHello", engine: .docling))
        )
        let job = AgentAttachmentExtractionJob(id: "job", sessionID: sessionID, attachmentID: manifest.id, requestedCapabilities: ["document-to-markdown"])

        let completed = try await processor.process(job)
        let loaded = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: sessionID, attachmentID: manifest.id)
        let extractedURL = paths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(loaded.extractedTextRelativePath ?? "")

        #expect(completed.status == .succeeded)
        #expect(loaded.extractionStatus == .extracted)
        #expect(loaded.previewText?.contains("Extracted") == true)
        #expect(loaded.extractionReports.first?.engine == .docling)
        #expect(FileManager.default.fileExists(atPath: extractedURL.path))
        #expect(try String(contentsOf: extractedURL, encoding: .utf8).contains("Hello"))
    }

    @Test func processorMarksUnsupportedWithoutDerivative() async throws {
        let paths = try tempPaths()
        let sessionID = "s"
        let manifest = try seedAttachment(paths: paths, sessionID: sessionID, attachmentID: "a", filename: "deck.pptx", kind: .presentation)
        let processor = AttachmentExtractionJobProcessor(
            paths: paths,
            extractor: StaticAttachmentExtractor(result: .unsupported(engine: .unavailable, warning: "No available extractor"))
        )
        let job = AgentAttachmentExtractionJob(id: "job", sessionID: sessionID, attachmentID: manifest.id)

        let completed = try await processor.process(job)
        let loaded = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: sessionID, attachmentID: manifest.id)

        #expect(completed.status == .unsupported)
        #expect(loaded.extractionStatus == .unsupported)
        #expect(loaded.extractedTextRelativePath == nil)
        #expect(loaded.extractionReports.first?.warnings.first?.contains("No available extractor") == true)
    }

    @Test func queueRunsEnqueuedJobsAndPersistsStatus() async throws {
        let paths = try tempPaths()
        let sessionID = "s"
        let manifest = try seedAttachment(paths: paths, sessionID: sessionID, attachmentID: "a", filename: "report.docx", kind: .document)
        let jobStore = AttachmentExtractionJobStore(paths: paths)
        let queue = AttachmentExtractionQueue(
            jobStore: jobStore,
            processor: AttachmentExtractionJobProcessor(
                paths: paths,
                extractor: StaticAttachmentExtractor(result: .success(markdown: "Done", engine: .markItDown))
            )
        )

        let job = try await queue.enqueue(sessionID: sessionID, attachmentID: manifest.id, requestedCapabilities: ["document-to-markdown"])
        try await queue.drain(sessionID: sessionID)
        let jobs = try jobStore.load(sessionID: sessionID)

        #expect(job.status == .queued)
        #expect(jobs.contains { $0.id == job.id && $0.status == .succeeded })
    }

    private func tempPaths() throws -> AppStoragePaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        return paths
    }

    @discardableResult
    private func seedAttachment(paths: AppStoragePaths, sessionID: String, attachmentID: String, filename: String, kind: AgentAttachmentKind) throws -> AgentAttachmentManifest {
        let directories = try paths.ensureSessionArtifactDirectories(sessionID: sessionID)
        let attachmentDirectory = directories.attachments.appendingPathComponent(attachmentID, isDirectory: true)
        let originalDirectory = attachmentDirectory.appendingPathComponent("original", isDirectory: true)
        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: originalDirectory.appendingPathComponent(filename))
        let manifest = AgentAttachmentManifest(
            id: attachmentID,
            displayName: filename,
            originalFilename: filename,
            normalizedFilename: filename,
            kind: kind,
            byteCount: 8,
            sha256: "sha",
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            storedRelativePath: "attachments/\(attachmentID)/original/\(filename)",
            manifestRelativePath: "attachments/\(attachmentID)/manifest.json",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: attachmentDirectory.appendingPathComponent("manifest.json"), options: .atomic)
        return manifest
    }
}

private struct StaticAttachmentExtractor: AttachmentExtractorService {
    enum Result {
        case success(markdown: String, engine: AgentAttachmentExtractionEngine)
        case unsupported(engine: AgentAttachmentExtractionEngine, warning: String)
    }

    var result: Result

    func extract(_ request: AttachmentExtractionRequest) async throws -> AttachmentExtractionResult {
        switch result {
        case .success(let markdown, let engine):
            let report = AgentAttachmentExtractionReport(
                attachmentID: request.manifest.id,
                engine: engine,
                status: .extracted,
                capabilitiesUsed: request.requestedCapabilities,
                startedAt: Date(timeIntervalSince1970: 2),
                completedAt: Date(timeIntervalSince1970: 3)
            )
            return AttachmentExtractionResult(report: report, extractedMarkdown: markdown, previewText: markdown)
        case .unsupported(let engine, let warning):
            let report = AgentAttachmentExtractionReport(
                attachmentID: request.manifest.id,
                engine: engine,
                status: .unsupported,
                warnings: [warning],
                startedAt: Date(timeIntervalSince1970: 2),
                completedAt: Date(timeIntervalSince1970: 3)
            )
            return AttachmentExtractionResult(report: report)
        }
    }
}
