import Foundation

public enum SkillTemplateCreatorError: Error, Sendable, Equatable {
    case unableToCreateUniqueSlug
}

public struct SkillTemplateCreator {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func createSkill(in skillsDirectory: URL, now: Date = Date()) throws -> URL {
        try fileManager.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        let slug = try nextAvailableSlug(in: skillsDirectory)
        let skillDirectory = skillsDirectory.appendingPathComponent(slug, isDirectory: true)
        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
        try template(slug: slug, now: now).write(to: skillFile, atomically: true, encoding: .utf8)
        return skillFile
    }

    private func nextAvailableSlug(in skillsDirectory: URL) throws -> String {
        let base = "new-skill"
        for index in 1...999 {
            let slug = index == 1 ? base : "\(base)-\(index)"
            let candidate = skillsDirectory.appendingPathComponent(slug, isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                return slug
            }
        }
        throw SkillTemplateCreatorError.unableToCreateUniqueSlug
    }

    private func template(slug: String, now: Date) -> String {
        """
        ---
        name: New Skill
        description: Describe what this skill helps Connor do and when it should be used.
        tags:
          - draft
        x-connor:
          lifecycle: draft
          risk: low
          invocation:
            manual: true
            semantic: true
        ---

        # New Skill

        Use this skill when the user asks Connor to perform a repeatable workflow or apply specialized operating instructions.

        ## Instructions

        1. Clarify the user’s goal and constraints.
        2. Apply the workflow, checklist, or domain-specific rules documented here.
        3. Return a concise result and call out assumptions, risks, and next steps.

        ## Arguments

        If the user invokes this skill with arguments, treat `$ARGUMENTS` as the task-specific input.

        ## Notes

        Created by Connor Skill Manager as `\(slug)` on \(Self.isoDateString(from: now)).
        """
    }

    private static func isoDateString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
