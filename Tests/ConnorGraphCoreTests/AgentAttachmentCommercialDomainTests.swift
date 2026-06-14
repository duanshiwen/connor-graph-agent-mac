import Foundation
import Testing
@testable import ConnorGraphCore

@Suite("Agent Attachment Commercial Domain Tests")
struct AgentAttachmentCommercialDomainTests {
    @Test func commercialAttachmentTypesRoundTripThroughCodable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let derivative = AgentAttachmentDerivativeRef(
            id: "derivative-1",
            kind: .structuredJSON,
            relativePath: "attachments/a/derivatives/structured.json",
            byteCount: 42,
            sha256: "abc",
            createdAt: now
        )
        let report = AgentAttachmentExtractionReport(
            attachmentID: "a",
            engine: .docling,
            status: .extracted,
            capabilitiesUsed: ["ocr", "vlm"],
            warnings: ["low confidence"],
            derivativeRefs: [derivative],
            startedAt: now,
            completedAt: now
        )
        let remote = AgentAttachmentRemoteFileRef(
            id: "remote-1",
            provider: .claude,
            attachmentID: "a",
            remoteFileID: "file_123",
            status: .uploaded,
            uploadedAt: now,
            retentionSummary: "retained until explicit deletion",
            zdrEligible: false,
            providerMetadata: ["beta": "files-api-2025-04-14"]
        )
        let manifest = AgentAttachmentManifest(
            id: "a",
            displayName: "report.pdf",
            originalFilename: "report.pdf",
            normalizedFilename: "report.pdf",
            kind: .pdf,
            mimeType: "application/pdf",
            fileExtension: "pdf",
            byteCount: 1024,
            sha256: "hash",
            lifecycleStatus: .ready,
            extractionStatus: .extracted,
            storedRelativePath: "attachments/a/original/report.pdf",
            manifestRelativePath: "attachments/a/manifest.json",
            extractedTextRelativePath: "attachments/a/derivatives/extracted.md",
            previewText: "Preview",
            derivativeRefs: [derivative],
            extractionReports: [report],
            remoteFileRefs: [remote],
            createdAt: now,
            updatedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentAttachmentManifest.self, from: data)

        #expect(decoded.derivativeRefs == [derivative])
        #expect(decoded.extractionReports == [report])
        #expect(decoded.remoteFileRefs == [remote])
        #expect(decoded.remoteFileRefs.first?.zdrEligible == false)
    }

    @Test func legacyAttachmentManifestDecodesWithEmptyCommercialCollections() throws {
        let json = """
        {
          "id": "legacy",
          "displayName": "notes.txt",
          "originalFilename": "notes.txt",
          "normalizedFilename": "notes.txt",
          "kind": "text",
          "byteCount": 12,
          "sha256": "hash",
          "lifecycleStatus": "ready",
          "extractionStatus": "extracted",
          "storedRelativePath": "attachments/legacy/original/notes.txt",
          "manifestRelativePath": "attachments/legacy/manifest.json",
          "extractedTextRelativePath": "attachments/legacy/derivatives/extracted.md",
          "previewText": "hello",
          "createdAt": "2026-06-15T00:00:00Z",
          "updatedAt": "2026-06-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(AgentAttachmentManifest.self, from: json)

        #expect(manifest.derivativeRefs.isEmpty)
        #expect(manifest.extractionReports.isEmpty)
        #expect(manifest.remoteFileRefs.isEmpty)
        #expect(manifest.messageRef.previewText == "hello")
    }

    @Test func auditAndEvidenceRecordsRepresentAttachmentLineage() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let audit = AgentAttachmentAuditEvent(
            id: "audit-1",
            sessionID: "session",
            attachmentID: "attachment",
            kind: .evidenceCandidateCreated,
            summary: "Created evidence candidate",
            metadata: ["manifest": "attachments/attachment/manifest.json"],
            createdAt: now
        )
        let evidence = AgentAttachmentEvidenceCandidate(
            id: "candidate-1",
            sessionID: "session",
            messageID: "message",
            attachmentID: "attachment",
            displayName: "contract.pdf",
            sha256: "sha",
            manifestRelativePath: "attachments/attachment/manifest.json",
            derivativeRelativePaths: ["attachments/attachment/derivatives/extracted.md"],
            extractor: .markItDown,
            summary: "Contract evidence",
            createdAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decodedAudit = try decoder.decode(AgentAttachmentAuditEvent.self, from: encoder.encode(audit))
        let decodedEvidence = try decoder.decode(AgentAttachmentEvidenceCandidate.self, from: encoder.encode(evidence))

        #expect(decodedAudit.kind == .evidenceCandidateCreated)
        #expect(decodedEvidence.extractor == .markItDown)
        #expect(decodedEvidence.derivativeRelativePaths.count == 1)
    }
}
