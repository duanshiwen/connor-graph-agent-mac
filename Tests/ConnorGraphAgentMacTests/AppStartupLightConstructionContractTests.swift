import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("App Startup Light Construction Contract Tests")
struct AppStartupLightConstructionContractTests {
    private let legacyMegaTypeName = "App" + "View" + "Model"

    @Test func compositionRootLiveDoesNotPerformPersistentBootstrap() throws {
        let source = try projectSource(named: "AppCompositionRoot.swift")
        let liveBody = try #require(source.range(of: "static func live() -> AppCompositionRoot"))
        let tail = String(source[liveBody.lowerBound...])
        let end = try #require(tail.range(of: "    func sendWhenInteractive"))
        let body = String(tail[..<end.lowerBound])

        #expect(!body.contains(legacyMegaTypeName))
        #expect(!body.contains("AppGraphRepository.bootstrap"))
        #expect(!body.contains("loadSnapshot()"))
        #expect(!body.contains("SQLite"))
        #expect(!body.contains("SearchKernel"))
        #expect(!body.contains("makeNoteImportViewModel()"))
        #expect(body.contains("AppRuntimeLifecycle.placeholder()"))
    }

    @Test func stagedContentAndMaintenanceUseActorSnapshots() throws {
        let viewModelSource = try projectSource(named: "AppRuntimeLifecycle.swift")
        let content = try functionBody(named: "func loadStartupContent", in: viewModelSource, endingAt: "    func reconcileStartupRefreshTasks")
        #expect(content.contains("applyStartupSnapshot"))
        #expect(content.contains("applyStartupHistory"))
        #expect(!content.contains("reloadRegistry()"))
        #expect(!content.contains("taskAutomationModel.reload()"))
        #expect(!content.contains("sourceRuntimeModel.reload()"))
        #expect(!content.contains("skillRuntimeModel.reload()"))
        #expect(!content.contains("browserFeatureModel.loadHistory()"))

        let interactive = try functionBody(
            named: "func prepareInteractiveStartup(snapshot:",
            in: viewModelSource,
            endingAt: "    private func applyInteractiveLLMSettings"
        )
        #expect(interactive.contains("applyInteractiveLLMSettings"))
        #expect(interactive.contains("applyInteractiveRuntimeSettings"))
        #expect(interactive.contains("applyInteractiveSessionContent"))
        #expect(!interactive.contains("loadLLMSettings()"))
        #expect(!interactive.contains("loadRuntimeSettings()"))
        #expect(!interactive.contains("reloadChatSessions()"))

        let compositionSource = try projectSource(named: "AppCompositionRoot.swift")
        #expect(compositionSource.contains("interactiveBootstrapActor.load"))
        #expect(compositionSource.contains("AppRuntimeLifecycle.live(core: snapshot)"))
        #expect(compositionSource.contains("contentBootstrapActor.load"))
        #expect(compositionSource.contains("maintenanceBootstrapActor.load"))
        #expect(!compositionSource.contains(legacyMegaTypeName))
        #expect(compositionSource.contains("self.runtime = runtime"))
        #expect(compositionSource.contains("self.graph = runtime.graph"))
        let publicationStart = try #require(compositionSource.range(of: "let previousRuntime = self.runtime"))
        let publication = compositionSource[publicationStart.lowerBound...]
        let shutdown = try #require(publication.range(of: "previousRuntime.shutdown()"))
        let publishRuntime = try #require(publication.range(of: "self.runtime = runtime"))
        let publishGraph = try #require(publication.range(of: "self.graph = runtime.graph"))
        let publishNoteImport = try #require(publication.range(of: "self.noteImportModel = noteImportModel"))
        #expect(shutdown.lowerBound < publishRuntime.lowerBound)
        #expect(publishRuntime.lowerBound < publishGraph.lowerBound)
        #expect(publishGraph.lowerBound < publishNoteImport.lowerBound)
        let maintenance = try functionBody(
            named: "startMaintenance: {",
            in: compositionSource,
            endingAt: "            shutdown: {"
        )
        let scheduler = try #require(maintenance.range(of: "runtime.startScheduler()"))
        let recovery = try #require(maintenance.range(of: "recoverPersistedJobs()"))
        let identity = try #require(maintenance.range(of: "identityStore.restoreSession()"))
        #expect(scheduler.lowerBound < recovery.lowerBound)
        #expect(recovery.lowerBound < identity.lowerBound)
        #expect(maintenance.components(separatedBy: "runtime.startScheduler()").count - 1 == 1)
        #expect(!maintenance.contains("startTaskSchedulerTimer()"))
        #expect(maintenance.components(separatedBy: "recoverPersistedJobs()").count - 1 == 1)
        #expect(maintenance.components(separatedBy: "identityStore.restoreSession()").count - 1 == 1)
    }

    @Test func persistentCoreBootstrapIsOwnedByBootstrapActor() throws {
        let source = try projectSource(named: "AppBootstrapActor.swift")
        #expect(source.contains("actor AppBootstrapActor"))
        #expect(source.contains("AppStoragePaths.live()"))
        #expect(source.contains("AppGraphRepository.bootstrap(paths: paths)"))
        #expect(source.contains("repository.loadSnapshot()"))
        #expect(source.contains("SQLiteMemoryOSStore"))
        #expect(source.contains("AppMemoryOSSearchKernelFactory.healthReport"))
    }

    @Test func skillPresentationIsBuiltDuringContentBootstrapNotRouteAppearance() throws {
        let bootstrapSource = try projectSource(named: "AppContentBootstrapActor.swift")
        #expect(bootstrapSource.contains("SkillPackageScanner().scan(storagePaths: paths)"))
        #expect(bootstrapSource.contains("SkillCommercialUIPresentationBuilder().build"))

        let skillListSource = try projectSource(named: "SkillManagerListViews.swift")
        #expect(!skillListSource.contains(".onAppear {\n            model.reload()"))

        let composerSource = try projectSource(named: "AgentChatComposerView.swift")
        #expect(!composerSource.contains(".onAppear {\n            chatActions.dependencies.skills.reload()"))
    }

    private func functionBody(named marker: String, in source: String, endingAt endMarker: String) throws -> String {
        let start = try #require(source.range(of: marker))
        let tail = String(source[start.lowerBound...])
        let end = try #require(tail.range(of: endMarker))
        return String(tail[..<end.lowerBound])
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
