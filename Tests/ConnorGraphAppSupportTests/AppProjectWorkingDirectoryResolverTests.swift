import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Project working directory resolver")
struct AppProjectWorkingDirectoryResolverTests {
    @Test("runtime workspace path takes priority over legacy sidecar path")
    func runtimeWorkspacePathTakesPriorityOverLegacySidecarPath() throws {
        let runtime = AgentRuntimeSettings(workspace: AgentRuntimeWorkspaceSettings(defaultWorkingDirectoryPath: "/tmp/runtime-project"))
        let llm = AppLLMSettings(
            baseURLString: AppLLMSettings.default.baseURLString,
            model: AppLLMSettings.default.model,
            hasAPIKey: false,
            providerMode: .governedClaudeSidecar,
            sidecarWorkingDirectoryPath: "/tmp/legacy-sidecar"
        )
        let resolved = AppProjectWorkingDirectoryResolver.resolve(runtimeSettings: runtime, llmSettings: llm, processCurrentDirectoryPath: "/tmp/process")

        #expect(resolved.url.path == "/tmp/runtime-project")
        #expect(resolved.source == .runtimeSettings)
    }

    @Test("legacy sidecar path is compatibility fallback")
    func legacySidecarPathIsCompatibilityFallback() throws {
        let runtime = AgentRuntimeSettings.default
        let llm = AppLLMSettings(
            baseURLString: AppLLMSettings.default.baseURLString,
            model: AppLLMSettings.default.model,
            hasAPIKey: false,
            providerMode: .governedClaudeSidecar,
            sidecarWorkingDirectoryPath: "/tmp/legacy-sidecar"
        )
        let resolved = AppProjectWorkingDirectoryResolver.resolve(runtimeSettings: runtime, llmSettings: llm, processCurrentDirectoryPath: "/tmp/process")

        #expect(resolved.url.path == "/tmp/legacy-sidecar")
        #expect(resolved.source == .legacySidecarSettings)
    }

    @Test("process current directory is final fallback")
    func processCurrentDirectoryIsFinalFallback() throws {
        let resolved = AppProjectWorkingDirectoryResolver.resolve(
            runtimeSettings: .default,
            llmSettings: .default,
            processCurrentDirectoryPath: "/tmp/process"
        )

        #expect(resolved.url.path == "/tmp/process")
        #expect(resolved.source == .processCurrentDirectory)
    }

    @Test("session override takes highest priority")
    func sessionOverrideTakesHighestPriority() throws {
        let runtime = AgentRuntimeSettings(workspace: AgentRuntimeWorkspaceSettings(defaultWorkingDirectoryPath: "/tmp/runtime-project"))
        let resolved = AppProjectWorkingDirectoryResolver.resolve(
            sessionWorkingDirectoryPath: "/tmp/session-project",
            runtimeSettings: runtime,
            llmSettings: .default,
            processCurrentDirectoryPath: "/tmp/process"
        )

        #expect(resolved.url.path == "/tmp/session-project")
        #expect(resolved.source == .session)
    }
}
