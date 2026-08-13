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

    @Test func aiTracePanelStoresEventsAndClearsOnReset() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("knowledge-trace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudKnowledgeCreatorStore(repository: .init(fileURL: root.appendingPathComponent("snapshot.json")))
        let event = CloudKnowledgeExtractionTraceEvent(sequence: 1, iteration: 1, kind: .toolExecution, modelID: "test-model")
        store.recordTraceEvent(event)
        #expect(store.traceEvents.count == 1)
        #expect(store.traceEvents.first?.kind == .toolExecution)
        #expect(store.traceEvents.first?.modelID == "test-model")

        store.clearTraceEvents()
        #expect(store.traceEvents.isEmpty)
    }

    @Test func aiTracePanelRenderedBetweenTableAndButtonsWithDefaultExpanded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let creatorSource = try String(contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/CloudKnowledgeCreatorView.swift"), encoding: .utf8)
        #expect(creatorSource.contains("isAITraceExpanded = true"))
        #expect(creatorSource.contains("KnowledgePublicationAITracePanel("))
        #expect(creatorSource.contains("isExpanded: $isAITraceExpanded"))

        let panelSource = try String(contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/KnowledgePublicationProgressViews.swift"), encoding: .utf8)
        #expect(panelSource.contains("struct KnowledgePublicationAITracePanel"))
        #expect(panelSource.contains("DisclosureGroup(isExpanded: $isExpanded)"))
    }

    @Test func completedStageNoLongerOffersDestructiveResetButton() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let creatorSource = try String(contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/CloudKnowledgeCreatorView.swift"), encoding: .utf8)
        // 完成态不应再有“创建新的发布”直接 reset 的按钮，避免误触丢失进度。
        #expect(!creatorSource.contains("Button(\"创建新的发布\")"))
        #expect(creatorSource.contains("可在“发布历史”中查看或恢复"))
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
