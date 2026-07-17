import Foundation
import Testing
@testable import ConnorGraphAgentMac
import ConnorGraphAppSupport

@MainActor
@Suite("Knowledge Publication Progress Tests")
struct KnowledgePublicationProgressTests {
    @Test func activitySummaryTracksGenerationProgressAndPauseState() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("knowledge-progress-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudKnowledgeCreatorStore(repository: .init(fileURL: root.appendingPathComponent("snapshot.json")))
        store.toggleConversation("one")
        store.toggleConversation("two")
        store.advance(to: .generating)
        store.noteProcessed(conversationID: "one", summary: "已整理一组知识")

        var summary = KnowledgePublicationActivitySummary(store: store)
        #expect(summary.isVisible)
        #expect(summary.progressFraction == 0.5)
        #expect(summary.presentationState == .running)

        store.pause()
        summary = KnowledgePublicationActivitySummary(store: store)
        #expect(summary.presentationState == .paused)
    }

    @Test func pendingPublicationHasVisibleAutomaticCommitFallback() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/KnowledgePublicationProgressViews.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains(".task(id: store.snapshot.stage)"))
        #expect(source.contains("await store.finalizePublication()"))
        #expect(source.contains("\"提交知识变更\""))
        #expect(source.contains("\"重试提交\""))
    }
}
