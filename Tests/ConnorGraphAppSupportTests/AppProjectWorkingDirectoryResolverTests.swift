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

    @Test("runtime workspace roots resolve primary and additional roots")
    func runtimeWorkspaceRootsResolvePrimaryAndAdditionalRoots() throws {
        let runtime = AgentRuntimeSettings(workspace: AgentRuntimeWorkspaceSettings(roots: [
            AgentRuntimeWorkspaceRoot(id: "app", displayName: "App", path: "/tmp/app", role: "project", isPrimary: true),
            AgentRuntimeWorkspaceRoot(id: "docs", displayName: "Docs", path: "/tmp/docs", role: "docs", isPrimary: false)
        ]))

        let resolved = AppProjectWorkingDirectoryResolver.resolveWorkspace(
            runtimeSettings: runtime,
            llmSettings: .default,
            processCurrentDirectoryPath: "/tmp/process"
        )

        #expect(resolved.primary.url.path == "/tmp/app")
        #expect(resolved.primary.source == .runtimeSettings)
        #expect(resolved.roots.map(\.url.path) == ["/tmp/app", "/tmp/docs"])
        #expect(resolved.additionalAllowedDirectories.map(\.path) == ["/tmp/docs"])
    }

    @Test("runtime workspace roots prefer explicit primary over first root")
    func runtimeWorkspaceRootsPreferExplicitPrimaryOverFirstRoot() throws {
        let runtime = AgentRuntimeSettings(workspace: AgentRuntimeWorkspaceSettings(roots: [
            AgentRuntimeWorkspaceRoot(id: "docs", displayName: "Docs", path: "/tmp/docs", role: "docs", isPrimary: false),
            AgentRuntimeWorkspaceRoot(id: "app", displayName: "App", path: "/tmp/app", role: "project", isPrimary: true)
        ]))

        let resolved = AppProjectWorkingDirectoryResolver.resolveWorkspace(
            runtimeSettings: runtime,
            llmSettings: .default,
            processCurrentDirectoryPath: "/tmp/process"
        )

        #expect(resolved.primary.url.path == "/tmp/app")
        #expect(resolved.additionalAllowedDirectories.map(\.path) == ["/tmp/docs"])
    }

    @Test("legacy workspace fields still resolve when roots are empty")
    func legacyWorkspaceFieldsStillResolveWhenRootsAreEmpty() throws {
        let runtime = AgentRuntimeSettings(workspace: AgentRuntimeWorkspaceSettings(
            defaultWorkingDirectoryPath: "/tmp/runtime-project",
            additionalAllowedDirectoryPaths: ["/tmp/shared"]
        ))

        let resolved = AppProjectWorkingDirectoryResolver.resolveWorkspace(
            runtimeSettings: runtime,
            llmSettings: .default,
            processCurrentDirectoryPath: "/tmp/process"
        )

        #expect(resolved.primary.url.path == "/tmp/runtime-project")
        #expect(resolved.additionalAllowedDirectories.map(\.path) == ["/tmp/shared"])
    }
}
