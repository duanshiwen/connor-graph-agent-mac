import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Suite("Agent Attachment Context Plan Builder Tests")
struct AgentAttachmentContextPlanBuilderTests {
    @Test func buildsInlineContextForExtractedTextAttachment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-context-builder-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let sessionID = "session"
        let source = root.appendingPathComponent("note.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Hello\n\nBody".write(to: source, atomically: true, encoding: .utf8)
        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: sessionID)
        let builder = AgentAttachmentContextPlanBuilder(storagePaths: paths)

        let plan = builder.build(sessionID: sessionID, attachments: [manifest.messageRef])

        #expect(plan.inlineBlocks.count == 1)
        #expect(plan.inlineBlocks.first?.content.contains("Hello") == true)
        #expect(plan.imageBlocks.isEmpty)
    }

    @Test func omitsAttachmentThatDoesNotFitTotalBudgetInsteadOfTruncating() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-total-budget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = AppSessionAttachmentStore(paths: paths)
        let sessionID = "session"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        func importText(name: String, content: String) throws -> AgentAttachmentManifest {
            let url = root.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return try store.importFile(at: url, sessionID: sessionID)
        }

        let first = try importText(name: "first.md", content: String(repeating: "a", count: 12))
        let second = try importText(name: "second.md", content: String(repeating: "b", count: 12))
        let builder = AgentAttachmentContextPlanBuilder(
            storagePaths: paths,
            totalCharacterLimit: 15
        )

        let plan = builder.build(sessionID: sessionID, attachments: [first.messageRef, second.messageRef])

        #expect(plan.inlineBlocks.count == 1)
        #expect(plan.inlineBlocks.first?.attachmentID == first.id)
        #expect(plan.inlineBlocks.first?.isTruncated == false)
        #expect(plan.inlineBlocks.first?.content == String(repeating: "a", count: 12))
        #expect(plan.omittedAttachments.count == 1)
        #expect(plan.omittedAttachments.first?.attachmentID == second.id)
        #expect(plan.omittedAttachments.first?.reason.contains("Total attachment prompt budget") == true)
    }

    @Test func includesSingleAttachmentWithinTotalBudgetInFull() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-in-budget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let sessionID = "session"
        let source = root.appendingPathComponent("medium.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // 单个附件内容超过旧的 20,000 字符单附件上限，但只要低于总量上限就应完整纳入。
        let content = String(repeating: "中", count: 30_000)
        try content.write(to: source, atomically: true, encoding: .utf8)
        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: sessionID)

        let plan = AgentAttachmentContextPlanBuilder(storagePaths: paths)
            .build(sessionID: sessionID, attachments: [manifest.messageRef])

        #expect(plan.inlineBlocks.count == 1)
        #expect(plan.inlineBlocks.first?.attachmentID == manifest.id)
        #expect(plan.inlineBlocks.first?.isTruncated == false)
        #expect(plan.inlineBlocks.first?.content.count == 30_000)
        #expect(plan.omittedAttachments.isEmpty)
    }

    @Test func rebuildsHistoricalImageFromStoredBytesAndDeduplicatesConversationAttachments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-history-builder-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let sessionID = "session"
        let source = root.appendingPathComponent("history.png")
        let originalBytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02, 0x03])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try originalBytes.write(to: source)
        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: sessionID)
        let messages = [
            AgentMessage(role: .assistant, content: "Generated image", attachments: [manifest.messageRef])
        ]

        let attachments = AgentAttachmentContextPlanBuilder.conversationAttachments(
            messages: messages,
            currentAttachments: [manifest.messageRef]
        )
        let plan = AgentAttachmentContextPlanBuilder(storagePaths: paths).build(
            sessionID: sessionID,
            attachments: attachments
        )
        let imageBlock = try #require(plan.imageBlocks.first)
        let encodedPayload = try #require(imageBlock.dataURL.split(separator: ",", maxSplits: 1).last)
        let rebuiltBytes = try #require(Data(base64Encoded: String(encodedPayload)))

        #expect(attachments == [manifest.messageRef])
        #expect(plan.imageBlocks.count == 1)
        #expect(plan.estimatedTokens == 8_192)
        #expect(rebuiltBytes == originalBytes)
    }

    @Test func conversationAttachmentsExcludeCoveredPrefixUnlessExplicitlyRehydrated() throws {
        let covered = AgentMessageAttachmentRef(id: "covered", displayName: "covered.png", kind: .image, byteCount: 10, lifecycleStatus: .ready, extractionStatus: .pending, manifestRelativePath: "covered/manifest.json")
        let tail = AgentMessageAttachmentRef(id: "tail", displayName: "tail.png", kind: .image, byteCount: 10, lifecycleStatus: .ready, extractionStatus: .pending, manifestRelativePath: "tail/manifest.json")
        let coveredMessages = [AgentMessage(id: "covered-message", role: .user, content: "old", attachments: [covered])]
        let allMessages = coveredMessages + [AgentMessage(id: "tail-message", role: .assistant, content: "recent", attachments: [tail])]
        let state = ConversationSummaryState(
            sessionID: "session",
            revision: 1,
            compressionGeneration: 1,
            payload: ConversationSummaryPayload(),
            coveredThroughMessageID: "covered-message",
            coveredMessageCount: 1,
            coveredPrefixHash: try ConversationSummaryIntegrity.coveredPrefixHash(messages: coveredMessages),
            currentSummaryHash: "hash",
            sourceTokenEstimate: 1,
            summaryTokenEstimate: 1,
            generationModelID: "model"
        )
        let selection = ConversationSummaryHistorySelector().select(messages: allMessages, state: state)

        let defaultAttachments = AgentAttachmentContextPlanBuilder.conversationAttachments(
            messages: selection.messages,
            currentAttachments: []
        )
        let rehydratedAttachments = AgentAttachmentContextPlanBuilder.conversationAttachments(
            messages: selection.messages,
            currentAttachments: [],
            explicitlyRehydratedAttachments: [covered]
        )

        #expect(defaultAttachments == [tail])
        #expect(rehydratedAttachments == [tail, covered])
    }

    @Test func sendsOnlyLatestImageEditLeafUnlessOlderVersionIsExplicitlyPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-image-chain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = AppSessionAttachmentStore(paths: paths)
        let sessionID = "session"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        func importImage(name: String, marker: UInt8, sourceID: String? = nil) throws -> AgentAttachmentManifest {
            let url = root.appendingPathComponent(name)
            try Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, marker]).write(to: url)
            let metadata = sourceID.map {
                AgentAttachmentGenerationMetadata(
                    providerID: "test",
                    modelID: "image-model",
                    parameters: [AgentAttachmentGenerationMetadata.sourceAttachmentIDParameterKey: $0]
                )
            }
            return try store.importFile(at: url, sessionID: sessionID, origin: .modelGenerated, generationMetadata: metadata)
        }

        let original = try importImage(name: "original.png", marker: 1)
        let firstEdit = try importImage(name: "first.png", marker: 2, sourceID: original.id)
        let latestEdit = try importImage(name: "latest.png", marker: 3, sourceID: firstEdit.id)
        let builder = AgentAttachmentContextPlanBuilder(storagePaths: paths)
        let attachments = [original.messageRef, firstEdit.messageRef, latestEdit.messageRef]

        let defaultPlan = builder.build(sessionID: sessionID, attachments: attachments)
        let restoredPlan = builder.build(
            sessionID: sessionID,
            attachments: attachments,
            preservingAttachmentIDs: [original.id]
        )

        #expect(defaultPlan.imageBlocks.map(\.attachmentID) == [latestEdit.id])
        #expect(defaultPlan.estimatedTokens == 8_192)
        #expect(restoredPlan.imageBlocks.map(\.attachmentID) == [original.id, latestEdit.id])
        #expect(restoredPlan.estimatedTokens == 16_384)
    }

    @Test func appliesLatestLeafSelectionToAudioAndReportsNativeInputRequirement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-audio-chain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = AppSessionAttachmentStore(paths: paths)
        let sessionID = "session"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalURL = root.appendingPathComponent("original.mp3")
        let latestURL = root.appendingPathComponent("latest.mp3")
        try Data([0x49, 0x44, 0x33, 1]).write(to: originalURL)
        try Data([0x49, 0x44, 0x33, 2]).write(to: latestURL)
        let original = try store.importFile(at: originalURL, sessionID: sessionID, origin: .userImported)
        let latest = try store.importFile(
            at: latestURL,
            sessionID: sessionID,
            origin: .modelGenerated,
            generationMetadata: AgentAttachmentGenerationMetadata(
                providerID: "test",
                modelID: "audio-model",
                parameters: [AgentAttachmentGenerationMetadata.sourceAttachmentIDParameterKey: original.id]
            )
        )

        let plan = AgentAttachmentContextPlanBuilder(storagePaths: paths).build(
            sessionID: sessionID,
            attachments: [original.messageRef, latest.messageRef]
        )

        #expect(plan.omittedAttachments.map(\.attachmentID) == [latest.id])
        #expect(plan.omittedAttachments.first?.reason.contains("native audio input") == true)
    }

    @Test func historicalAssistantMediaIsCatalogedInsteadOfRetransmitted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-media-catalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let sessionID = "session"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("generated.png")
        try Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1]).write(to: source)
        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: sessionID, origin: .modelGenerated)
        let image = AgentMessageAttachmentRef(
            id: manifest.id,
            displayName: manifest.displayName,
            kind: .image,
            byteCount: manifest.byteCount,
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            manifestRelativePath: manifest.manifestRelativePath
        )
        let messages = [AgentMessage(role: .assistant, content: "Done", attachments: [image])]
        let attachments = AgentAttachmentContextPlanBuilder.conversationAttachments(messages: messages, currentAttachments: [])
        let plan = AgentAttachmentContextPlanBuilder(storagePaths: paths).build(
            sessionID: sessionID,
            attachments: attachments,
            deferredMediaAttachmentIDs: AgentAttachmentContextPlanBuilder.historicalAssistantMediaAttachmentIDs(messages: messages)
        )

        #expect(plan.imageBlocks.isEmpty)
        #expect(plan.inlineBlocks.count == 1)
        #expect(plan.inlineBlocks.first?.content.contains(manifest.id) == true)
        #expect(plan.inlineBlocks.first?.content.contains("load_attachment_context") == true)
    }
}
