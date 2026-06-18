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

@Test func skillsRuntimeResolverUsesOnlyApplicationSkillsDirectory() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let globalRoot = storagePaths.applicationSupportDirectory.appendingPathComponent("global-skills", isDirectory: true)
    let projectRoot = storagePaths.applicationSupportDirectory.appendingPathComponent("project", isDirectory: true)
    let projectSkills = projectRoot.appendingPathComponent(".agents/skills", isDirectory: true)
    _ = try writeSkill(root: globalRoot, slug: "same-skill", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Global Skill"))
    _ = try writeSkill(root: storagePaths.skillsDirectory, slug: "same-skill", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Home Skill"))
    _ = try writeSkill(root: projectSkills, slug: "project-only", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Project Skill"))
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths)

    let resolved = try #require(try repository.resolveSkill(slug: "same-skill"))

    #expect(resolved.scope == .home)
    #expect(resolved.manifest.name == "Home Skill")
    #expect(try repository.resolveSkill(slug: "project-only") == nil)
}

@Test func skillRuntimeBuildsInstructionBundleForMatchingTriggerAndGlob() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths)
    let skillURL = try writeSkill(root: storagePaths.skillsDirectory, slug: "markdown-review", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Markdown Review"))
    let skill = try repository.loadSkill(slug: "markdown-review", scope: .home, skillURL: skillURL)
    let runtime = SkillRuntime(definitions: [skill])

    let maybeBundle = try runtime.instructionBundle(trigger: .afterModelResponse, filePaths: ["README.md"], sessionID: "session-1", runID: "run-1")
    let bundle = try #require(maybeBundle)

    #expect(bundle.skill.slug == "markdown-review")
    #expect(bundle.instructions.contains("# Markdown Review"))
    #expect(bundle.requiredSources == ["local-filesystem"])
    #expect(bundle.permissionRequests.map(\.capability) == [.readSession])
    #expect(bundle.registryEvent.entryID == "markdown-review")
    #expect(bundle.event.kind == .skillRegistryChanged)
}

@Test func skillRuntimeDoesNotActivateNonMatchingTriggerOrGlob() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths)
    let skillURL = try writeSkill(root: storagePaths.skillsDirectory, slug: "markdown-review", content: validSkillMarkdown)
    let skill = try repository.loadSkill(slug: "markdown-review", scope: .home, skillURL: skillURL)
    let runtime = SkillRuntime(definitions: [skill])

    let wrongTrigger = try runtime.instructionBundle(trigger: .sourceEvent, filePaths: ["README.md"], sessionID: "session-1")
    let wrongGlob = try runtime.instructionBundle(trigger: .afterModelResponse, filePaths: ["main.swift"], sessionID: "session-1")
    #expect(wrongTrigger == nil)
    #expect(wrongGlob == nil)
}

@Test func skillRuntimeRejectsDisabledSkills() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths)
    let skillURL = try writeSkill(root: storagePaths.skillsDirectory, slug: "disabled-skill", content: validSkillMarkdown)
    let skill = try repository.loadSkill(slug: "disabled-skill", scope: .home, skillURL: skillURL)
    let runtime = SkillRuntime(definitions: [skill], disabledSkillIDs: ["disabled-skill"])

    do {
        _ = try runtime.instructionBundle(trigger: .manual, filePaths: ["README.md"], sessionID: "session-1")
        Issue.record("Expected disabled skill to be rejected")
    } catch let error as SkillRuntimeError {
        #expect(error == .skillDisabled("disabled-skill"))
    } catch {
        Issue.record("Expected SkillRuntimeError, got \(error)")
    }
}

@Test func skillsRuntimeRepositorySyncsProductOSRegistryAndReturnsEvent() throws {
    let storagePaths = temporaryPhaseDStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppSkillRuntimeRepository(storagePaths: storagePaths)
    let registryRepository = AppProductOSRegistryRepository(storagePaths: storagePaths)
    let skillURL = try writeSkill(root: storagePaths.skillsDirectory, slug: "review-notes", content: validSkillMarkdown.replacingOccurrences(of: "Session Summary", with: "Review Notes"))
    let skill = try repository.loadSkill(slug: "review-notes", scope: .home, skillURL: skillURL)
    try repository.save(skill)

    let result = try repository.syncProductOSRegistry(using: registryRepository, sessionID: "session-1", runID: "run-1")
    let synced = try #require(result.snapshot.skills.first { $0.id == "review-notes" })

    #expect(synced.displayName == "Review Notes")
    #expect(synced.status == .enabled)
    #expect(synced.triggers == [.manual, .afterModelResponse])
    #expect(synced.requiredCapabilities == [.readSession])
    #expect(result.event.kind == .skillRegistryChanged)
    #expect(result.registryEvent.entryID == "review-notes")
    #expect(result.registryEvent.status == .enabled)
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
