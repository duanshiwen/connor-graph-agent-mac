import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum SkillManagerMutationToolError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidSlug(String)
    case missingSkill(String)
    case unsafePath(String)
    case invalidMarkdown(String)

    public var description: String {
        switch self {
        case .invalidSlug(let slug): "invalidSlug: \(slug)"
        case .missingSkill(let slug): "missingSkill: \(slug)"
        case .unsafePath(let path): "unsafePath: \(path)"
        case .invalidMarkdown(let message): "invalidMarkdown: \(message)"
        }
    }
}

public struct SkillManagerMutationService: Sendable {
    public static let skillManifestFileName = "SKILL.md"

    public var storagePaths: AppStoragePaths
    public var parser: SkillManifestParser

    public init(storagePaths: AppStoragePaths, parser: SkillManifestParser = SkillManifestParser()) {
        self.storagePaths = storagePaths
        self.parser = parser
    }

    @discardableResult
    public func createSkill(
        slug rawSlug: String,
        name: String,
        description: String,
        instructions: String,
        tags: [String] = [],
        globs: [String] = [],
        overwrite: Bool = false
    ) throws -> String {
        let slug = normalizedSlug(rawSlug)
        try validateSlug(slug)
        let directory = try validatedUserSkillDirectory(slug: slug)
        let skillURL = skillManifestURL(in: directory)
        if FileManager.default.fileExists(atPath: skillURL.path), !overwrite {
            throw SkillManagerMutationToolError.invalidSlug("Skill \(slug) already exists. Pass overwrite=true to replace it.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let markdown = renderSkillMarkdown(
            name: name,
            description: description,
            instructions: instructions,
            tags: tags,
            globs: globs,
            slug: slug
        )
        _ = try parser.parse(markdown: markdown, slug: slug)
        try markdown.write(to: skillURL, atomically: true, encoding: .utf8)
        return skillURL.path
    }

    @discardableResult
    public func updateSkill(
        slug rawSlug: String,
        name: String? = nil,
        description: String? = nil,
        instructions: String? = nil,
        tags: [String]? = nil,
        globs: [String]? = nil
    ) throws -> String {
        let slug = normalizedSlug(rawSlug)
        try validateSlug(slug)
        let directory = try validatedUserSkillDirectory(slug: slug)
        let skillURL = skillManifestURL(in: directory)
        guard FileManager.default.fileExists(atPath: skillURL.path) else { throw SkillManagerMutationToolError.missingSkill(slug) }
        let raw = try String(contentsOf: skillURL, encoding: .utf8)
        let parsed = try parser.parse(markdown: raw, slug: slug)
        let markdown = renderSkillMarkdown(
            name: nonEmpty(name, fallback: parsed.manifest.name),
            description: nonEmpty(description, fallback: parsed.manifest.description),
            instructions: nonEmpty(instructions, fallback: parsed.instructions),
            tags: tags ?? parsed.manifest.tags,
            globs: globs ?? parsed.manifest.globs,
            slug: slug
        )
        _ = try parser.parse(markdown: markdown, slug: slug)
        try markdown.write(to: skillURL, atomically: true, encoding: .utf8)
        return skillURL.path
    }

    public func deleteSkill(slug rawSlug: String) throws {
        let slug = normalizedSlug(rawSlug)
        try validateSlug(slug)
        let directory = try validatedUserSkillDirectory(slug: slug)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw SkillManagerMutationToolError.missingSkill(slug) }
        try FileManager.default.removeItem(at: directory)
    }

    public func skillManifestURL(slug rawSlug: String) throws -> URL {
        let slug = normalizedSlug(rawSlug)
        try validateSlug(slug)
        return skillManifestURL(in: try validatedUserSkillDirectory(slug: slug))
    }

    private func userSkillDirectory(slug: String) -> URL {
        storagePaths.skillsDirectory.appendingPathComponent(slug, isDirectory: true).standardizedFileURL
    }

    private func skillManifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent(Self.skillManifestFileName)
    }

    private func validatedUserSkillDirectory(slug: String) throws -> URL {
        let directory = userSkillDirectory(slug: slug)
        let expected = storagePaths.skillsDirectory.appendingPathComponent(slug, isDirectory: true).standardizedFileURL.path
        guard directory.path == expected else { throw SkillManagerMutationToolError.unsafePath(directory.path) }
        return directory
    }

    private func nonEmpty(_ candidate: String?, fallback: String) -> String {
        guard let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        return candidate
    }

    private func normalizedSlug(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validateSlug(_ slug: String) throws {
        guard SkillSlug(slug).isValid else { throw SkillManagerMutationToolError.invalidSlug(slug) }
    }

    private func renderSkillMarkdown(name: String, description: String, instructions: String, tags: [String], globs: [String], slug: String) -> String {
        let normalizedTags = Array(Set(tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } + ["skill"])).sorted()
        let normalizedGlobs = globs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return """
        ---
        name: \"\(escapeYAML(name))\"
        description: \"\(escapeYAML(description))\"
        tags:\(yamlArray(normalizedTags))
        globs:\(yamlArray(normalizedGlobs))
        x-connor:
          lifecycle: stable
          riskLevel: low
          requiredCapabilities:
            - readSession
          graphContextPolicy: readOnly
          sourcePolicy: preenableIfReady
        ---

        \(instructions.trimmingCharacters(in: .whitespacesAndNewlines))

        ## Notes

        Managed by Connor Skill Manager as `\(slug)`.
        """
    }

    private func yamlArray(_ values: [String]) -> String {
        guard !values.isEmpty else { return " []" }
        return "\n" + values.map { "  - \"\(escapeYAML($0))\"" }.joined(separator: "\n")
    }

    private func escapeYAML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

public struct ConnorSkillCreateTool: AgentTool {
    public let name = "connor_skill_create"
    public let description = "Create or overwrite a Connor skill package in the user skills directory. Use this when the user asks to add a skill; do not merely say the skill was added."
    public let permission: AgentPermissionCapability = .writeWorkspaceFile
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "slug": .string(description: "Kebab-case skill slug, for example go-expert."),
        "name": .string(description: "Human-readable skill name."),
        "description": .string(description: "When and why this skill should be used."),
        "instructions": .string(description: "Full markdown body containing workflow, usage guidance, output expectations, and validation notes."),
        "tags": .array(items: .string(description: "Tag"), description: "Optional skill tags."),
        "globs": .array(items: .string(description: "Glob"), description: "Optional file globs that should activate or suggest the skill."),
        "overwrite": .boolean(description: "Whether to overwrite an existing user skill with the same slug.")
    ], required: ["slug", "name", "description", "instructions"])

    private let service: SkillManagerMutationService

    public init(service: SkillManagerMutationService) {
        self.service = service
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let slug = arguments.string("slug"), let name = arguments.string("name"), let description = arguments.string("description"), let instructions = arguments.string("instructions") else {
            throw AgentToolError.invalidArguments("slug, name, description, and instructions are required")
        }
        let path = try service.createSkill(
            slug: slug,
            name: name,
            description: description,
            instructions: instructions,
            tags: arguments.stringArray("tags"),
            globs: arguments.stringArray("globs"),
            overwrite: arguments.bool("overwrite") ?? false
        )
        return skillMutationToolResult(
            context: context,
            toolName: self.name,
            contentText: "Created Connor skill `\(slug)` at \(path).",
            payload: ["slug": slug, "path": path]
        )
    }
}

public struct ConnorSkillUpdateTool: AgentTool {
    public let name = "connor_skill_update"
    public let description = "Update an existing user Connor skill package by slug. Use this when the user asks to edit or refine a skill."
    public let permission: AgentPermissionCapability = .writeWorkspaceFile
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "slug": .string(description: "Existing user skill slug to update."),
        "name": .string(description: "Optional replacement skill name."),
        "description": .string(description: "Optional replacement description."),
        "instructions": .string(description: "Optional replacement full markdown body."),
        "tags": .array(items: .string(description: "Tag"), description: "Optional replacement tags."),
        "globs": .array(items: .string(description: "Glob"), description: "Optional replacement globs.")
    ], required: ["slug"])

    private let service: SkillManagerMutationService

    public init(service: SkillManagerMutationService) {
        self.service = service
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let slug = arguments.string("slug") else { throw AgentToolError.invalidArguments("slug is required") }
        let path = try service.updateSkill(
            slug: slug,
            name: arguments.string("name"),
            description: arguments.string("description"),
            instructions: arguments.string("instructions"),
            tags: arguments.array("tags") == nil ? nil : arguments.stringArray("tags"),
            globs: arguments.array("globs") == nil ? nil : arguments.stringArray("globs")
        )
        return skillMutationToolResult(
            context: context,
            toolName: self.name,
            contentText: "Updated Connor skill `\(slug)` at \(path).",
            payload: ["slug": slug, "path": path]
        )
    }
}

public struct ConnorSkillDeleteTool: AgentTool {
    public let name = "connor_skill_delete"
    public let description = "Delete an existing user Connor skill package by slug. Use only after the user explicitly asks to delete a skill."
    public let permission: AgentPermissionCapability = .writeWorkspaceFile
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "slug": .string(description: "Existing user skill slug to delete.")
    ], required: ["slug"])

    private let service: SkillManagerMutationService

    public init(service: SkillManagerMutationService) {
        self.service = service
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let slug = arguments.string("slug") else { throw AgentToolError.invalidArguments("slug is required") }
        try service.deleteSkill(slug: slug)
        return skillMutationToolResult(
            context: context,
            toolName: self.name,
            contentText: "Deleted Connor skill `\(slug)`.",
            payload: ["slug": slug]
        )
    }
}

private func skillMutationToolResult(
    context: AgentToolExecutionContext,
    toolName: String,
    contentText: String,
    payload: [String: String]
) -> AgentToolResult {
    let contentJSON: String?
    if let data = try? JSONEncoder().encode(payload), let encoded = String(data: data, encoding: .utf8) {
        contentJSON = encoded
    } else {
        contentJSON = nil
    }
    return AgentToolResult(
        runID: context.runID,
        sessionID: context.sessionID,
        toolCallID: context.toolCallID,
        toolName: toolName,
        contentText: contentText,
        contentJSON: contentJSON
    )
}

private extension AgentToolArguments {
    func stringArray(_ key: String) -> [String] {
        array(key)?.compactMap(\.stringValue) ?? []
    }
}
