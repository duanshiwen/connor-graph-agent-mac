import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Agent Runtime Workspace Settings Tests")
struct AgentRuntimeWorkspaceSettingsTests {
    @Test func rememberWorkspacePathMaintainsMRUOrderAndDeduplicates() {
        var settings = AgentRuntimeWorkspaceSettings()

        settings.rememberWorkspacePath("/tmp/project-a")
        settings.rememberWorkspacePath("/tmp/project-b")
        settings.rememberWorkspacePath("/tmp/project-a")

        #expect(settings.recentWorkspacePaths == ["/tmp/project-a", "/tmp/project-b"])
    }

    @Test func rememberWorkspacePathTrimsEmptyAndLimitsHistory() {
        var settings = AgentRuntimeWorkspaceSettings()

        settings.rememberWorkspacePath("   ")
        for index in 0..<10 {
            settings.rememberWorkspacePath("/tmp/project-\(index)", limit: 8)
        }

        #expect(settings.recentWorkspacePaths.count == 8)
        #expect(settings.recentWorkspacePaths.first == "/tmp/project-9")
        #expect(settings.recentWorkspacePaths.last == "/tmp/project-2")
    }

    @Test func decodesWorkspaceSettingsWithoutRecentHistory() throws {
        let data = Data("""
        {
          "defaultWorkingDirectoryPath": "/tmp/project",
          "additionalAllowedDirectoryPaths": [],
          "roots": []
        }
        """.utf8)

        let settings = try JSONDecoder().decode(AgentRuntimeWorkspaceSettings.self, from: data)

        #expect(settings.defaultWorkingDirectoryPath == "/tmp/project")
        #expect(settings.recentWorkspacePaths.isEmpty)
    }
}
