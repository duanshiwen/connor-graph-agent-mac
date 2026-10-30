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
        try clearPendingSkillDeletion(directory: directory)
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
        _ = try parser.parse(markdown: raw, slug: slug)
        let markdown = try updateMarkdown(raw, name: name, description: description, instructions: instructions, tags: tags, globs: globs)
        _ = try parser.parse(markdown: markdown, slug: slug)
        try markdown.write(to: skillURL, atomically: true, encoding: .utf8)
        try clearPendingSkillDeletion(directory: directory)
        return skillURL.path
    }

    public func deleteSkill(slug rawSlug: String) throws {
        let slug = normalizedSlug(rawSlug)
        try validateSlug(slug)
        let directory = try validatedUserSkillDirectory(slug: slug)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw SkillManagerMutationToolError.missingSkill(slug) }
        let existing = SkillPackageScanner.applicationDefault().scan(storagePaths: storagePaths).packages.first { $0.packagePath == directory.path }
        let recordID = try existing.map { try SkillSyncStore.wire(package: $0).id } ?? "user:\(directory.path)"
        try AccountSyncLocalDeletions(directory: storagePaths.configDirectory).record(collection: "skills", id: recordID)
        try FileManager.default.removeItem(at: directory)
    }

    public func skillManifestURL(slug rawSlug: String) throws -> URL {
        let slug = normalizedSlug(rawSlug)
        try validateSlug(slug)
        return skillManifestURL(in: try validatedUserSkillDirectory(slug: slug))
    }

    private func clearPendingSkillDeletion(directory: URL) throws {
        let existing = SkillPackageScanner.applicationDefault().scan(storagePaths: storagePaths).packages.first { $0.packagePath == directory.path }
        let id = try existing.map { try SkillSyncStore.wire(package: $0).id } ?? "user:\(directory.path)"
        try AccountSyncLocalDeletions(directory: storagePaths.configDirectory).clear("skills|\(id)")
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
        let resolvedRoot = storagePaths.skillsDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedDirectory.path == resolvedRoot.appendingPathComponent(slug, isDirectory: true).path,
              skillManifestURL(in: directory).resolvingSymlinksInPath().path == resolvedDirectory.appendingPathComponent(Self.skillManifestFileName).path
        else { throw SkillManagerMutationToolError.unsafePath(directory.path) }
        return directory
    }

    /// Replace only requested top-level fields; keep policy/extension metadata,
    /// resource declarations and an untouched body byte-for-byte.
    private func updateMarkdown(_ raw: String, name: String?, description: String?, instructions: String?, tags: [String]?, globs: [String]?) throws -> String {
        let expression = try NSRegularExpression(pattern: #"\A((?:\x{FEFF})?---[ \t]*\r?\n)([\s\S]*?)(\r?\n---[ \t]*(?:\r?\n|\z))([\s\S]*)\z"#)
        let text = raw as NSString
        guard let match = expression.firstMatch(in: raw, range: NSRange(location: 0, length: text.length)) else {
            throw SkillManagerMutationToolError.invalidMarkdown("Missing skill frontmatter.")
        }
        let newline = raw.contains("\r\n") ? "\r\n" : "\n"
        var replacements: [String: String] = [:]
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { replacements["name"] = "name: \"\(escapeYAML(name))\"" }
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { replacements["description"] = "description: \"\(escapeYAML(description))\"" }
        if let tags { replacements["tags"] = "tags:" + yamlArray(tags).replacingOccurrences(of: "\n", with: newline) }
        if let globs { replacements["globs"] = "globs:" + yamlArray(globs).replacingOccurrences(of: "\n", with: newline) }
        let lines = text.substring(with: match.range(at: 2)).replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let first = line.first, !first.isWhitespace, let colon = line.firstIndex(of: ":"),
               let replacement = replacements.removeValue(forKey: String(line[..<colon])) {
                result.append(replacement)
                while index + 1 < lines.count && (lines[index + 1].isEmpty || lines[index + 1].first?.isWhitespace == true) { index += 1 }
            } else { result.append(line) }
            index += 1
        }
        result.append(contentsOf: replacements.keys.sorted().compactMap { replacements[$0] })
        let body: String
        if let instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = newline + instructions.trimmingCharacters(in: .whitespacesAndNewlines) + newline
        } else { body = text.substring(with: match.range(at: 4)) }
        return text.substring(with: match.range(at: 1)) + result.joined(separator: newline) + text.substring(with: match.range(at: 3)) + body
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
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
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
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
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
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
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
