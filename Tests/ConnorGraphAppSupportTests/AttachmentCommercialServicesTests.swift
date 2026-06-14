import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Attachment Commercial Services Tests")
struct AttachmentCommercialServicesTests {
    @Test func providerCachePersistsRemoteRefsAndPurgeLedger() throws {
        let paths = try tempPaths()
        let store = AppAttachmentProviderCacheStore(paths: paths)
        let ref = AgentAttachmentRemoteFileRef(provider: .gemini, attachmentID: "a", remoteFileID: "files/a", remoteURI: "gemini://a", status: .uploaded, retentionSummary: "48 hours")

        try store.save(ref, sessionID: "s")
        let loaded = try store.load(sessionID: "s", provider: .gemini, attachmentID: "a")

        #expect(loaded == ref)
    }

    @Test func auditLedgerAndFileMirrorPreserveLocalEvents() throws {
        let paths = try tempPaths()
        let ledger = AttachmentAuditLedger(paths: paths)
        let event = AgentAttachmentAuditEvent(sessionID: "s", attachmentID: "a", kind: .indexed, summary: "Indexed")

        try ledger.append(event)
        let events = try ledger.load(sessionID: "s")
        let mirrorURL = paths.applicationSupportDirectory.appendingPathComponent("mirror/audit.jsonl")
        let mirrorResult = try AttachmentEnterpriseAuditMirror(mode: .file(mirrorURL)).mirror(event)

        #expect(events.map(\.kind) == [.indexed])
        #expect(mirrorResult == "mirrored:file")
        #expect(FileManager.default.fileExists(atPath: mirrorURL.path))
    }

    @Test func searchAndEmbeddingIndexesAreSessionScoped() throws {
        let paths = try tempPaths()
        let search = AppAttachmentSearchIndex(paths: paths)
        let embedding = AppAttachmentEmbeddingIndex(paths: paths)
        let manifest = manifest(id: "a", name: "contract.pdf")

        try search.index(sessionID: "s", manifest: manifest, extractedText: "This contract includes a termination clause.")
        try embedding.index(sessionID: "s", attachmentID: "a", text: "This contract includes a termination clause.")

        let results = try search.search(sessionID: "s", query: "termination")
        let vectors = try embedding.load(sessionID: "s")

        #expect(results.first?.attachmentID == "a")
        #expect(vectors.first?.dimension == 8)
        #expect(try search.search(sessionID: "other", query: "termination").isEmpty)
    }

    @Test func graphEvidenceCandidateCapturesAttachmentProvenance() throws {
        let paths = try tempPaths()
        let admission = AttachmentGraphEvidenceAdmission(paths: paths)
        var m = manifest(id: "a", name: "evidence.md")
        m.extractedTextRelativePath = "attachments/a/derivatives/extracted.md"
        m.derivativeRefs = [AgentAttachmentDerivativeRef(kind: .structuredJSON, relativePath: "attachments/a/derivatives/structured.json", byteCount: 12)]

        let candidate = try admission.createCandidate(sessionID: "s", messageID: "m", manifest: m, extractor: .docling, summary: "Evidence")
        let loaded = try admission.loadCandidates(sessionID: "s")

        #expect(candidate.messageID == "m")
        #expect(candidate.derivativeRelativePaths.contains("attachments/a/derivatives/extracted.md"))
        #expect(candidate.derivativeRelativePaths.contains("attachments/a/derivatives/structured.json"))
        #expect(loaded.count == 1)
    }

    private func tempPaths() throws -> AppStoragePaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        return paths
    }

    private func manifest(id: String, name: String) -> AgentAttachmentManifest {
        AgentAttachmentManifest(
            id: id,
            displayName: name,
            originalFilename: name,
            normalizedFilename: name,
            kind: .pdf,
            mimeType: "application/pdf",
            fileExtension: "pdf",
            byteCount: 100,
            sha256: "sha",
            lifecycleStatus: .ready,
            extractionStatus: .extracted,
            storedRelativePath: "attachments/\(id)/original/\(name)",
            manifestRelativePath: "attachments/\(id)/manifest.json",
            previewText: "preview",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
