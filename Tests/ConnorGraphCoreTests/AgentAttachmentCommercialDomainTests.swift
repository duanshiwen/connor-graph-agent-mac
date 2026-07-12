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

    @Test func presentationAndBuiltinPDFTextRoundTripThroughCodable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_200)
        let report = AgentAttachmentExtractionReport(
            attachmentID: "slides",
            engine: .builtinPDFText,
            status: .unsupported,
            warnings: ["No selectable PDF text"],
            startedAt: now,
            completedAt: now
        )
        let manifest = AgentAttachmentManifest(
            id: "slides",
            displayName: "deck.pptx",
            originalFilename: "deck.pptx",
            normalizedFilename: "deck.pptx",
            kind: .presentation,
            mimeType: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            fileExtension: "pptx",
            byteCount: 2048,
            sha256: "hash",
            lifecycleStatus: .ready,
            extractionStatus: .unsupported,
            storedRelativePath: "attachments/slides/original/deck.pptx",
            manifestRelativePath: "attachments/slides/manifest.json",
            extractionReports: [report],
            createdAt: now,
            updatedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentAttachmentManifest.self, from: encoder.encode(manifest))

        #expect(decoded.kind == .presentation)
        #expect(decoded.extractionReports.first?.engine == .builtinPDFText)
        #expect(decoded.messageRef.kind == .presentation)
    }

    @Test func extractionJobRoundTripsThroughCodable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_300)
        let job = AgentAttachmentExtractionJob(
            id: "job-1",
            sessionID: "session",
            attachmentID: "attachment",
            requestedCapabilities: ["document-to-markdown"],
            status: .running,
            attempt: 2,
            maxAttempts: 4,
            createdAt: now,
            startedAt: now,
            completedAt: nil,
            lastError: "previous failure"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentAttachmentExtractionJob.self, from: encoder.encode(job))

        #expect(decoded == job)
        #expect(decoded.status == .running)
        #expect(decoded.requestedCapabilities == ["document-to-markdown"])
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
        #expect(manifest.origin == .userImported)
        #expect(manifest.generationMetadata == nil)
        #expect(manifest.mediaMetadata == nil)
        #expect(manifest.messageRef.previewText == "hello")
    }

    @Test func generatedMediaMetadataRoundTripsThroughManifest() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_400)
        let generation = AgentAttachmentGenerationMetadata(
            providerID: "openai-responses",
            modelID: "gpt-5",
            responseID: "response-1",
            toolCallID: "call-1",
            revisedPrompt: "A calm lake",
            parameters: ["size": "1024x1024"]
        )
        let media = AgentAttachmentMediaMetadata(pixelWidth: 1024, pixelHeight: 1024)
        let manifest = AgentAttachmentManifest(
            id: "generated-image",
            displayName: "generated.png",
            originalFilename: "generated.png",
            normalizedFilename: "generated.png",
            kind: .image,
            mimeType: "image/png",
            fileExtension: "png",
            byteCount: 128,
            sha256: "hash",
            lifecycleStatus: .ready,
            extractionStatus: .unsupported,
            storedRelativePath: "attachments/generated-image/original/generated.png",
            manifestRelativePath: "attachments/generated-image/manifest.json",
            createdAt: now,
            updatedAt: now,
            origin: .modelGenerated,
            generationMetadata: generation,
            mediaMetadata: media
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentAttachmentManifest.self, from: encoder.encode(manifest))

        #expect(decoded.origin == .modelGenerated)
        #expect(decoded.generationMetadata == generation)
        #expect(decoded.mediaMetadata == media)
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
