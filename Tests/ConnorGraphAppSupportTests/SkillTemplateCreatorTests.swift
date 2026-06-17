import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Commercial Skill Template Creator Tests")
struct SkillTemplateCreatorTests {
    @Test func createsDraftSkillTemplateWithUniqueSlug() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-template-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let creator = SkillTemplateCreator(fileManager: .default)

        let first = try creator.createSkill(in: root, now: Date(timeIntervalSince1970: 0))
        let second = try creator.createSkill(in: root, now: Date(timeIntervalSince1970: 0))

        #expect(first.lastPathComponent == "SKILL.md")
        #expect(first.deletingLastPathComponent().lastPathComponent == "new-skill")
        #expect(second.deletingLastPathComponent().lastPathComponent == "new-skill-2")

        let content = try String(contentsOf: first, encoding: .utf8)
        #expect(content.contains("name: New Skill"))
        #expect(content.contains("description: Describe what this skill helps Connor do"))
        #expect(content.contains("lifecycle: draft"))
        #expect(content.contains("$ARGUMENTS"))
    }
}
