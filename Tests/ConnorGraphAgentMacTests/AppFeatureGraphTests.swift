import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("App Feature Graph Tests")
struct AppFeatureGraphTests {
    private let legacyMegaTypeName = "App" + "View" + "Model"

    @MainActor
    @Test func placeholderRuntimePublishesStableFeatureReferences() {
        let runtime = AppRuntimeLifecycle.placeholder()
        let graph = runtime.graph

        #expect(graph.chatActions.dependencies.browser === graph.browser)
        #expect(graph.chatActions.dependencies.appSettings === graph.appSettings)
        #expect(graph.chatActions.dependencies.inputSettings === graph.inputSettings)
        #expect(graph.chatActions.dependencies.workspaceSettings === graph.workspaceSettings)
        #expect(graph.chatActions.dependencies.skills === graph.skills)
        #expect(graph.chatActions.dependencies.contacts === graph.contacts)
        #expect(graph.chatActions.dependencies.governance === graph.governance)
        #expect(graph.chatActions.dependencies.aiConnections === graph.aiConnections)

        runtime.shutdown()
        runtime.shutdown()
    }

    @Test func compositionRootPublishesGraphWithoutLegacyFacade() throws {
        let source = try projectSource(named: "AppCompositionRoot.swift")
        #expect(source.contains("@Published private(set) var graph: AppFeatureGraph"))
        #expect(source.contains("private var runtime: AppRuntimeLifecycle"))
        #expect(!source.contains(legacyMegaTypeName))
        #expect(!source.contains("@Published private(set) var runtime"))
    }

    @Test func swiftUIEntryPointsDoNotReferenceLegacyFacade() throws {
        for filename in [
            "ConnorGraphAgentMacApp.swift",
            "AppShellViews.swift",
            "AppPrimarySidebarView.swift",
            "AppListDetailPanes.swift",
            "ConnorSettingsViews.swift"
        ] {
            let source = try projectSource(named: filename)
            #expect(!source.contains(legacyMegaTypeName), "\(filename) must consume narrow feature models and typed ports")
        }
    }

    @Test func sidebarCreationActionsUseTypedInteractiveCommands() throws {
        let source = try projectSource(named: "AppPrimarySidebarView.swift")
        #expect(source.contains("sendCommand(.shortcut(.newSession))"))
        #expect(source.contains("sendCommand(.newNote)"))
        #expect(!source.contains("newChatSession()"))
        #expect(!source.contains("newNoteSession()"))
    }

    @Test func featureGraphDoesNotOwnBackendsOrPerformIO() throws {
        let source = try projectSource(named: "AppFeatureGraph.swift")
        for forbidden in [
            legacyMegaTypeName,
            "AppGraphRepository",
            "AppStoragePaths",
            "SQLite",
            "FileManager",
            "Task {",
            "Timer",
            "@Published"
        ] {
            #expect(!source.contains(forbidden), "AppFeatureGraph must remain a reference graph: forbidden token \(forbidden)")
        }
    }

    private func projectSource(named filename: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/\(filename)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
