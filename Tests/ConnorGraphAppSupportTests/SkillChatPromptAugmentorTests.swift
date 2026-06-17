import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Commercial Skill Chat Prompt Augmentor Tests")
struct SkillChatPromptAugmentorTests {
    @Test func augmentsPromptWithInvokedSkillAndAuditsPlan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-chat-augmentor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = AppStoragePaths(applicationSupportDirectory: root.appendingPathComponent("app", isDirectory: true))
        try storage.ensureDirectoryHierarchy()
        let skillDirectory = storage.skillsDirectory.appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: Review
        description: Review code changes
        arguments:
          - target
        x-connor:
          requiredCapabilities:
            - readSession
        ---
        Review $ARGUMENTS carefully.
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let augmentor = SkillChatPromptAugmentor(storagePaths: storage)
        let result = augmentor.augment(prompt: "/review Sources", sessionID: "session-1", runID: "run-1")

        #expect(result.didAugment)
        #expect(result.plans.map { $0.package.slug.rawValue } == ["review"])
        #expect(result.augmentedPrompt.contains("<connor-active-skills count=\"1\">"))
        #expect(result.augmentedPrompt.contains("Review Sources carefully."))
        let auditURL = SkillInvocationAuditWriter(storagePaths: storage).skillAuditURL(sessionID: "session-1")
        #expect(FileManager.default.fileExists(atPath: auditURL.path))
        let audit = try String(contentsOf: auditURL, encoding: .utf8)
        #expect(audit.contains("review"))
    }

    @Test func leavesPromptUnchangedWhenNoSkillInvocationExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-chat-noop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = AppStoragePaths(applicationSupportDirectory: root.appendingPathComponent("app", isDirectory: true))
        try storage.ensureDirectoryHierarchy()

        let augmentor = SkillChatPromptAugmentor(storagePaths: storage)
        let result = augmentor.augment(prompt: "hello connor", sessionID: "session-1")

        #expect(result.didAugment == false)
        #expect(result.augmentedPrompt == "hello connor")
    }
}
