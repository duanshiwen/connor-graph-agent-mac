import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private func temporaryPhaseDStoragePaths(_ name: String = UUID().uuidString) -> AppStoragePaths {
    AppStoragePaths(applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ConnorPhaseDSkillsRuntime-\(name)", isDirectory: true))
}

private func writeSkill(root: URL, slug: String, content: String) throws -> URL {
    let directory = root.appendingPathComponent(slug, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("SKILL.md")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private let validSkillMarkdown = """
---
name: Session Summary
description: Summarize the current session safely.
triggers:
  - manual
  - afterModelResponse
requiredCapabilities:
  - readSession
requiredSources:
  - local-filesystem
globs:
  - "*.md"
---
# Session Summary

Use concise bullets. Never bypass Connor graph admission.
"""

@Test func skillsRuntimeRepositoryParsesAndPersistsSkillManifests() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths)
    let skillURL = try writeSkill(root: storagePaths.skillsDirectory, slug: "session-summary-plus", content: validSkillMarkdown)

    let skill = try repository.loadSkill(slug: "session-summary-plus", scope: .home, skillURL: skillURL)
    try repository.save(skill)
    let loaded = try #require(try repository.load(slug: "session-summary-plus"))

    #expect(loaded.slug == "session-summary-plus")
    #expect(loaded.manifest.name == "Session Summary")
    #expect(loaded.manifest.description == "Summarize the current session safely.")
    #expect(loaded.manifest.triggers == [.manual, .afterModelResponse])
    #expect(loaded.manifest.requiredCapabilities == [.readSession])
    #expect(loaded.manifest.requiredSources == ["local-filesystem"])
    #expect(loaded.instructions.contains("Never bypass Connor graph admission"))
    #expect(loaded.skillURL == skillURL)
}

@Test func skillsRuntimeResolverPrefersProjectThenHomeThenGlobal() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let globalRoot = storagePaths.applicationSupportDirectory.appendingPathComponent("global-skills", isDirectory: true)
    let projectRoot = storagePaths.applicationSupportDirectory.appendingPathComponent("project", isDirectory: true)
    let projectSkills = projectRoot.appendingPathComponent(".agents/skills", isDirectory: true)
    _ = try writeSkill(root: globalRoot, slug: "same-skill", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Global Skill"))
    _ = try writeSkill(root: storagePaths.skillsDirectory, slug: "same-skill", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Home Skill"))
    _ = try writeSkill(root: projectSkills, slug: "same-skill", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Project Skill"))
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths, globalSkillsDirectory: globalRoot, projectRoot: projectRoot)

    let resolved = try #require(try repository.resolveSkill(slug: "same-skill"))

    #expect(resolved.scope == .project)
    #expect(resolved.manifest.name == "Project Skill")
}

@Test func skillsRuntimeRepositoryRejectsUnsafeGraphContextPolicy() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let unsafeMarkdown = """
    ---
    name: Unsafe Skill
    description: Attempts to bypass governance.
    graphContextPolicy: allowAll
    ---
    # Unsafe

    Do unsafe things.
    """
    let skillURL = try writeSkill(root: storagePaths.skillsDirectory, slug: "unsafe-skill", content: unsafeMarkdown)
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths)

    do {
        _ = try repository.loadSkill(slug: "unsafe-skill", scope: .home, skillURL: skillURL)
        Issue.record("Expected unsafe skill graphContextPolicy to be rejected")
    } catch let error as AppSkillRuntimeRepositoryError {
        #expect(error == .unsafePermissionMode("Skill unsafe-skill cannot use allowAll graph context policy"))
    } catch {
        Issue.record("Expected AppSkillRuntimeRepositoryError, got \(error)")
    }
}
