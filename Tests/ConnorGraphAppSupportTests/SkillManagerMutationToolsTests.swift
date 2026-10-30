import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private func temporarySkillMutationRoot(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ConnorSkillMutationToolsTests-\(name)", isDirectory: true)
}

private func mutationToolContext(toolCallID: String = UUID().uuidString) -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "run-skill-mutation",
        sessionID: "session-skill-mutation",
        groupID: "default",
        userPrompt: "manage skill",
        toolCallID: toolCallID,
        policyEngine: AgentPolicyEngine(permissionMode: .trustedWrite)
    )
}

@Suite("Skill Manager Mutation Tools Tests")
struct SkillManagerMutationToolsTests {
    @Test func updatePreservesPolicyMetadataAssetsAndDoesNotDuplicateManagedFooter() throws {
        let root = temporarySkillMutationRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let service = SkillManagerMutationService(storagePaths: paths)
        let path = try service.createSkill(slug: "custom-skill", name: "Custom", description: "Original", instructions: "Original workflow")
        let file = URL(fileURLWithPath: path)
        var raw = try String(contentsOf: file, encoding: .utf8)
        raw = raw.replacingOccurrences(of: "riskLevel: low", with: "riskLevel: high")
            .replacingOccurrences(of: "- readSession", with: "- writeWorkspaceFile")
            .replacingOccurrences(of: "description: \"Original\"", with: "description: \"Original\"\ncustom-extension:\n  retained: yes")
        try raw.write(to: file, atomically: true, encoding: .utf8)
        let asset = file.deletingLastPathComponent().appendingPathComponent("reference.txt")
        try Data("resource".utf8).write(to: asset)
        _ = try service.updateSkill(slug: "custom-skill", description: "Updated")
        _ = try service.updateSkill(slug: "custom-skill", name: "Renamed")
        let updated = try String(contentsOf: file, encoding: .utf8)
        #expect(updated.contains("riskLevel: high"))
        #expect(updated.contains("- writeWorkspaceFile"))
        #expect(updated.contains("custom-extension:\n  retained: yes"))
        #expect(updated.components(separatedBy: "Managed by Connor Skill Manager").count == 2)
        #expect(try String(contentsOf: asset, encoding: .utf8) == "resource")
    }

    @Test func createToolCreatesScannableUserSkill() async throws {
        let root = temporarySkillMutationRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
        let service = SkillManagerMutationService(storagePaths: storagePaths)
        let tool = ConnorSkillCreateTool(service: service)

        let result = try await tool.execute(arguments: AgentToolArguments(values: [
            "slug": .string("go-expert"),
            "name": .string("Go Expert"),
            "description": .string("Use for Go code review and debugging."),
            "instructions": .string("# Go Expert\n\nReview Go code carefully."),
            "tags": .array([.string("go")]),
            "globs": .array([.string("**/*.go"), .string("**/go.mod")])
        ]), context: mutationToolContext())

        #expect(result.toolName == "connor_skill_create")
        let snapshot = SkillPackageScanner().scan(storagePaths: storagePaths)
        let resolution = try #require(snapshot.resolution(slug: "go-expert"))
        #expect(resolution.selected?.manifest.name == "Go Expert")
        #expect(resolution.selected?.manifest.globs.contains("**/*.go") == true)
    }

    @Test func updateToolUpdatesExistingUserSkill() async throws {
        let root = temporarySkillMutationRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
        let service = SkillManagerMutationService(storagePaths: storagePaths)
        _ = try service.createSkill(
            slug: "go-expert",
            name: "Go Expert",
            description: "Initial description.",
            instructions: "# Go Expert\n\nInitial instructions.",
            tags: ["go"],
            globs: ["**/*.go"]
        )
        let tool = ConnorSkillUpdateTool(service: service)

        _ = try await tool.execute(arguments: AgentToolArguments(values: [
            "slug": .string("go-expert"),
            "description": .string("Updated Go debugging and performance skill."),
            "instructions": .string("# Go Expert\n\nUpdated workflow with profiling and race checks."),
            "tags": .array([.string("go"), .string("performance")])
        ]), context: mutationToolContext())

        let snapshot = SkillPackageScanner().scan(storagePaths: storagePaths)
        let package = try #require(snapshot.resolution(slug: "go-expert")?.selected)
        #expect(package.manifest.description == "Updated Go debugging and performance skill.")
        #expect(package.instructions.contains("profiling"))
        #expect(package.manifest.tags.contains("performance"))
    }

    @Test func deleteToolRemovesExistingUserSkill() async throws {
        let root = temporarySkillMutationRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
        let service = SkillManagerMutationService(storagePaths: storagePaths)
        _ = try service.createSkill(
            slug: "go-expert",
            name: "Go Expert",
            description: "Use for Go tasks.",
            instructions: "# Go Expert\n\nDo Go work."
        )
        let tool = ConnorSkillDeleteTool(service: service)

        _ = try await tool.execute(arguments: AgentToolArguments(values: [
            "slug": .string("go-expert")
        ]), context: mutationToolContext())

        let snapshot = SkillPackageScanner().scan(storagePaths: storagePaths)
        #expect(snapshot.resolution(slug: "go-expert") == nil)
        #expect(!FileManager.default.fileExists(atPath: storagePaths.skillsDirectory.appendingPathComponent("go-expert", isDirectory: true).path))
    }
}
