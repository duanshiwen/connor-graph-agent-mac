import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct SourceRuntimeFeatureModelTests {
    @Test func reloadBuildsSinglePresentationStateAndClearsMissingSelection() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let configuration = makeConfiguration(sourceID: "source-one", displayName: "Source One")
        try fixture.repository.save(configuration)
        try fixture.repository.saveHealthRecord(MCPSourceRuntimeHealthRecord(
            sourceID: configuration.sourceID,
            healthStatus: .healthy,
            discoveredToolCount: 1
        ))
        let tool = MCPSourceToolDescriptor(
            sourceID: configuration.sourceID,
            name: "source-one.search",
            rawName: "search",
            description: "Search",
            inputSchema: .object([:]),
            requiredCapabilities: [.externalNetwork]
        )
        try fixture.repository.saveToolCatalog(sourceID: configuration.sourceID, catalog: [tool])
        let audit = MCPSourceRuntimeAuditRecord(sourceID: configuration.sourceID, eventKind: .toolFinished)
        try fixture.repository.appendAuditRecord(audit)

        let model = SourceRuntimeFeatureModel(repository: fixture.repository)
        model.selectedCardID = "missing-source"
        var events: [SourceRuntimeFeatureModel.Event] = []
        model.onEvent = { events.append($0) }

        model.reload()

        #expect(model.configurations.map(\.sourceID) == [configuration.sourceID])
        #expect(model.healthRecords.map(\.sourceID) == [configuration.sourceID])
        #expect(model.toolCatalogs[configuration.sourceID] == [tool])
        #expect(model.auditRecordsBySource[configuration.sourceID]?.map(\.id) == [audit.id])
        #expect(model.auditRecordsBySource[configuration.sourceID]?.map(\.eventKind) == [.toolFinished])
        #expect(model.presentation.cards.map(\.id) == [configuration.sourceID])
        #expect(model.selectedCardID == nil)
        #expect(events.count == 1)
    }

    @Test func addEditStatusArchiveAndDeletePreserveExistingActions() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = SourceRuntimeFeatureModel(repository: fixture.repository)

        model.presentAddSheet()
        model.addDraft.sourceID = "source-two"
        model.addDraft.displayName = "Source Two"
        model.addDraft.command = "/usr/bin/true"
        model.addDraft.argumentsText = "--version"
        model.addDraft.tagsText = "mcp, test"
        model.saveDraft()

        #expect(model.isPresentingAddSheet == false)
        #expect(model.selectedCardID == "source-two")
        #expect(model.testMessages["source-two"] == "Source saved. Run Test Source to discover tools.")
        #expect(model.configurations.first?.displayName == "Source Two")

        model.presentEditSheet(sourceID: "source-two")
        model.addDraft.displayName = "Edited Source"
        model.saveDraft()
        #expect(model.configurations.first?.displayName == "Edited Source")
        #expect(model.testMessages["source-two"] == "Source updated. Run Test Source to refresh tools if transport changed.")

        model.setStatus(sourceID: "source-two", status: .enabled)
        #expect(model.configurations.first?.status == .enabled)
        #expect(model.testMessages["source-two"] == "Source status updated to enabled.")

        model.archive(sourceID: "source-two")
        #expect(model.configurations.first?.status == .deprecated)
        #expect(model.testMessages["source-two"] == "Source archived as deprecated. Catalog, health and audit history are preserved.")

        model.requestDelete(sourceID: "source-two")
        #expect(model.pendingDeletionName == "Edited Source")
        model.confirmDelete()
        #expect(model.configurations.isEmpty)
        #expect(model.selectedCardID == nil)
        #expect(model.pendingDeletionID == nil)
        #expect(try fixture.repository.list().isEmpty)
    }

    @Test func unavailableRepositoryPreservesUserFacingFallbacks() async {
        let model = SourceRuntimeFeatureModel(repository: nil)
        model.presentAddSheet()
        model.addDraft.sourceID = "source-three"
        model.addDraft.command = "/usr/bin/true"
        model.saveDraft()
        #expect(model.addMessage == "Source runtime repository is not available.")

        model.setStatus(sourceID: "source-three", status: .enabled)
        #expect(model.testMessages["source-three"] == "Source runtime repository is not available.")

        await model.testSource(sourceID: "source-three")
        #expect(model.testMessages["source-three"] == "Source runtime repository is not available.")
    }

    private func makeFixture() throws -> (root: URL, repository: AppMCPSourceRuntimeRepository) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-source-runtime-model-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        return (root, AppMCPSourceRuntimeRepository(storagePaths: paths))
    }

    private func makeConfiguration(sourceID: String, displayName: String) -> MCPSourceRuntimeConfiguration {
        MCPSourceRuntimeConfiguration(
            sourceID: sourceID,
            displayName: displayName,
            transport: .stdio(command: "/usr/bin/true", arguments: []),
            status: .enabled,
            allowedCapabilities: [.readSession]
        )
    }
}
