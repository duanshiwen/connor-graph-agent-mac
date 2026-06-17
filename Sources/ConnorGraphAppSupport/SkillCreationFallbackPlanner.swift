import Foundation

public struct SkillCreationFallbackIdentity: Sendable, Equatable {
    public var name: String
    public var slug: String

    public init(name: String, slug: String) {
        self.name = name
        self.slug = slug
    }
}

public struct SkillCreationFallbackPlanner: Sendable {
    public init() {}

    public func suggestedIdentity(for userRequest: String, existingSlugs: Set<String>) -> SkillCreationFallbackIdentity {
        let lowercased = userRequest.lowercased()
        let name: String
        let baseSlug: String
        if lowercased.contains("golang") || lowercased.contains("go language") || lowercased.contains(" go ") || lowercased.contains(".go") || lowercased.contains("go.mod") {
            name = "Go 语言专家"
            baseSlug = "go-expert"
        } else if let firstSentence = userRequest.split(whereSeparator: { ".。\n".contains($0) }).first {
            let trimmed = String(firstSentence).trimmingCharacters(in: .whitespacesAndNewlines)
            name = String(trimmed.prefix(28)).isEmpty ? "新技能" : String(trimmed.prefix(28))
            baseSlug = skillSlug(from: trimmed)
        } else {
            name = "新技能"
            baseSlug = "custom-skill"
        }
        var candidate = baseSlug.isEmpty ? "custom-skill" : baseSlug
        var suffix = 2
        while existingSlugs.contains(candidate) {
            candidate = "\(baseSlug)-\(suffix)"
            suffix += 1
        }
        return SkillCreationFallbackIdentity(name: name, slug: candidate)
    }

    public func skillSlug(from text: String) -> String {
        let lowercased = text.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lowercased.unicodeScalars {
            if CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains(scalar) {
                result.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
            if result.count >= 48 { break }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.count >= 3 ? trimmed : "custom-skill"
    }

    public func generatedSkillMarkdown(name: String, slug: String, userRequest: String) -> String {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedDescription = userRequest.replacingOccurrences(of: "\"", with: "\\\"")
        let lowercased = userRequest.lowercased()
        let globs = (lowercased.contains("go") || lowercased.contains("golang")) ? "\n  - \"**/*.go\"\n  - \"**/go.mod\"" : ""
        return """
        ---
        name: "\(escapedName)"
        description: "\(escapedDescription)"
        tags:
          - generated
          - skill
        globs:\(globs.isEmpty ? " []" : globs)
        x-connor:
          lifecycle: stable
          riskLevel: low
          requiredCapabilities:
            - readSession
          graphContextPolicy: readOnly
          sourcePolicy: preenableIfReady
        ---

        # \(name)

        Use this skill when the user request matches the following need:

        > \(userRequest)

        ## When to use

        - The user asks for work in this specialty area.
        - The current task, files, or project context match the triggers described above.
        - The user needs structured review, debugging, planning, or implementation guidance.

        ## Workflow

        1. Restate the concrete task and identify the relevant context.
        2. Inspect available files, errors, requirements, or examples before making changes.
        3. Apply domain-specific best practices and explain important trade-offs.
        4. Produce actionable output: code, review findings, diagnosis, plan, or next steps.
        5. Call out assumptions, risks, validation steps, and follow-up work.

        ## Output

        - Be concise and practical.
        - Prefer concrete recommendations over generic advice.
        - Include commands, file paths, or code snippets when they help the user act.

        ## Notes

        Created by Connor Skill Manager as `\(slug)`.
        """
    }
}
