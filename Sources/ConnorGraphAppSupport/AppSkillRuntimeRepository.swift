import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct SkillRuntimeManifest: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var triggers: [ProductOSSkillTrigger]
    public var requiredCapabilities: [AgentPermissionCapability]
    public var requiredSources: [String]
    public var globs: [String]
    public var graphContextPolicy: AgentPermissionMode
    public var tags: [String]
    public var icon: String?

    public init(
        name: String,
        description: String,
        triggers: [ProductOSSkillTrigger] = [.manual],
        requiredCapabilities: [AgentPermissionCapability] = [.readSession],
        requiredSources: [String] = [],
        globs: [String] = [],
        graphContextPolicy: AgentPermissionMode = .readOnly,
        tags: [String] = [],
        icon: String? = nil
    ) {
        self.name = name
        self.description = description
        self.triggers = triggers
        self.requiredCapabilities = requiredCapabilities
        self.requiredSources = requiredSources
        self.globs = globs
        self.graphContextPolicy = graphContextPolicy
        self.tags = tags
        self.icon = icon
    }
}

public struct SkillRuntimeDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String { slug }
    public var slug: String
    public var scope: ProductOSSkillScope
    public var manifest: SkillRuntimeManifest
    public var instructions: String
    public var skillURL: URL
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        slug: String,
        scope: ProductOSSkillScope,
        manifest: SkillRuntimeManifest,
        instructions: String,
        skillURL: URL,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.slug = slug
        self.scope = scope
        self.manifest = manifest
        self.instructions = instructions
        self.skillURL = skillURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func productOSSkillDefinition() -> ProductOSSkillDefinition {
        ProductOSSkillDefinition(
            id: slug,
            displayName: manifest.name,
            scope: scope,
            status: .enabled,
            manifestPath: skillURL.path,
            triggers: manifest.triggers,
            requiredCapabilities: manifest.requiredCapabilities,
            graphContextPolicy: manifest.graphContextPolicy,
            tags: Array(Set(manifest.tags + ["skill"])).sorted(),
            notes: manifest.description,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public enum AppSkillRuntimeRepositoryError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidSlug(String)
    case missingSkillFile(String)
    case invalidFrontmatter(String)
    case missingRequiredField(String)
    case emptyInstructions(String)
    case unsupportedTrigger(String)
    case unsupportedCapability(String)
    case unsupportedPermissionMode(String)
    case unsafePermissionMode(String)

    public var description: String {
        switch self {
        case .invalidSlug(let slug): "invalidSlug: \(slug)"
        case .missingSkillFile(let path): "missingSkillFile: \(path)"
        case .invalidFrontmatter(let slug): "invalidFrontmatter: \(slug)"
        case .missingRequiredField(let field): "missingRequiredField: \(field)"
        case .emptyInstructions(let slug): "emptyInstructions: \(slug)"
        case .unsupportedTrigger(let value): "unsupportedTrigger: \(value)"
        case .unsupportedCapability(let value): "unsupportedCapability: \(value)"
        case .unsupportedPermissionMode(let value): "unsupportedPermissionMode: \(value)"
        case .unsafePermissionMode(let message): "unsafePermissionMode: \(message)"
        }
    }
}

public struct SkillRuntimeRegistrySyncResult: Sendable, Equatable {
    public var snapshot: ProductOSRegistrySnapshot
    public var registryEvent: AgentProductOSRegistryEvent
    public var event: AgentEvent

    public init(snapshot: ProductOSRegistrySnapshot, registryEvent: AgentProductOSRegistryEvent) {
        self.snapshot = snapshot
        self.registryEvent = registryEvent
        self.event = .skillRegistryChanged(registryEvent)
    }
}

public struct AppSkillRuntimeRepository: Sendable {
    public var storagePaths: AppStoragePaths

    public init(storagePaths: AppStoragePaths) {
        self.storagePaths = storagePaths
    }

    public var runtimeDirectory: URL { storagePaths.skillsDirectory }

    public func skillDirectory(slug: String) -> URL {
        runtimeDirectory.appendingPathComponent(slug, isDirectory: true)
    }

    public func runtimeDefinitionURL(slug: String) -> URL {
        skillDirectory(slug: slug).appendingPathComponent("skill-runtime.json")
    }

    public func loadSkill(slug: String, scope: ProductOSSkillScope, skillURL: URL) throws -> SkillRuntimeDefinition {
        try validateSlug(slug)
        guard FileManager.default.fileExists(atPath: skillURL.path) else {
            throw AppSkillRuntimeRepositoryError.missingSkillFile(skillURL.path)
        }
        let raw = try String(contentsOf: skillURL, encoding: .utf8)
        let parsed = try parseSkillMarkdown(raw, slug: slug)
        let definition = SkillRuntimeDefinition(
            slug: slug,
            scope: scope,
            manifest: parsed.manifest,
            instructions: parsed.instructions,
            skillURL: skillURL
        )
        try validate(definition)
        return definition
    }

    public func resolveSkill(slug: String) throws -> SkillRuntimeDefinition? {
        try validateSlug(slug)
        let homeURL = runtimeDirectory.appendingPathComponent(slug, isDirectory: true).appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: homeURL.path) {
            return try loadSkill(slug: slug, scope: .home, skillURL: homeURL)
        }
        return nil
    }

    public func save(_ definition: SkillRuntimeDefinition) throws {
        try validate(definition)
        try storagePaths.ensureDirectoryHierarchy()
        try FileManager.default.createDirectory(at: skillDirectory(slug: definition.slug), withIntermediateDirectories: true)
        var normalized = definition
        normalized.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: runtimeDefinitionURL(slug: normalized.slug), options: .atomic)
    }

    public func load(slug: String) throws -> SkillRuntimeDefinition? {
        let url = runtimeDefinitionURL(slug: slug)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let definition = try decoder.decode(SkillRuntimeDefinition.self, from: try Data(contentsOf: url))
        try validate(definition)
        return definition
    }

    public func list() throws -> [SkillRuntimeDefinition] {
        guard FileManager.default.fileExists(atPath: runtimeDirectory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try FileManager.default.contentsOfDirectory(at: runtimeDirectory, includingPropertiesForKeys: nil)
        return try entries.compactMap { entry in
            let url = entry.appendingPathComponent("skill-runtime.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let definition = try decoder.decode(SkillRuntimeDefinition.self, from: try Data(contentsOf: url))
            try validate(definition)
            return definition
        }.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }

    public func syncProductOSRegistry(
        using registryRepository: AppProductOSRegistryRepository,
        sessionID: String,
        runID: String? = nil
    ) throws -> SkillRuntimeRegistrySyncResult {
        let definitions = try list()
        var snapshot = try registryRepository.loadOrCreateDefault()
        for definition in definitions {
            let skill = definition.productOSSkillDefinition()
            if let index = snapshot.skills.firstIndex(where: { $0.id == skill.id }) {
                snapshot.skills[index] = skill
            } else {
                snapshot.skills.append(skill)
            }
        }
        try registryRepository.save(snapshot)
        let reloaded = try registryRepository.loadOrCreateDefault()
        let latestDefinition = definitions.sorted { $0.updatedAt > $1.updatedAt }.first
        let registryEvent = AgentProductOSRegistryEvent(
            runID: runID,
            sessionID: sessionID,
            registryKind: "skill",
            entryID: latestDefinition?.slug ?? "skill-runtime",
            status: latestDefinition.map { _ in ProductOSRegistryEntryStatus.enabled },
            message: "Skills runtime synchronized with Product OS registry."
        )
        return SkillRuntimeRegistrySyncResult(snapshot: reloaded, registryEvent: registryEvent)
    }

    public func validate(_ definition: SkillRuntimeDefinition) throws {
        try validateSlug(definition.slug)
        guard !definition.manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppSkillRuntimeRepositoryError.missingRequiredField("name")
        }
        guard !definition.manifest.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppSkillRuntimeRepositoryError.missingRequiredField("description")
        }
        guard !definition.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppSkillRuntimeRepositoryError.emptyInstructions(definition.slug)
        }
        if definition.manifest.graphContextPolicy == .allowAll {
            throw AppSkillRuntimeRepositoryError.unsafePermissionMode("Skill \(definition.slug) cannot use allowAll graph context policy")
        }
    }

    private func validateSlug(_ slug: String) throws {
        let pattern = #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#
        guard slug.range(of: pattern, options: .regularExpression) != nil else {
            throw AppSkillRuntimeRepositoryError.invalidSlug(slug)
        }
    }

    private func parseSkillMarkdown(_ raw: String, slug: String) throws -> (manifest: SkillRuntimeManifest, instructions: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { throw AppSkillRuntimeRepositoryError.invalidFrontmatter(slug) }
        let remainder = String(normalized.dropFirst(4))
        guard let endRange = remainder.range(of: "\n---") else { throw AppSkillRuntimeRepositoryError.invalidFrontmatter(slug) }
        let frontmatter = String(remainder[..<endRange.lowerBound])
        let bodyStart = endRange.upperBound
        let body = String(remainder[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw AppSkillRuntimeRepositoryError.emptyInstructions(slug) }
        let fields = parseSimpleYAML(frontmatter)
        guard let name = fields.scalars["name"], !name.isEmpty else { throw AppSkillRuntimeRepositoryError.missingRequiredField("name") }
        guard let description = fields.scalars["description"], !description.isEmpty else { throw AppSkillRuntimeRepositoryError.missingRequiredField("description") }
        let triggers = try parseTriggers(fields.arrays["triggers"] ?? fields.scalars["triggers"].map { [$0] } ?? ["manual"])
        let capabilities = try parseCapabilities(fields.arrays["requiredCapabilities"] ?? fields.scalars["requiredCapabilities"].map { [$0] } ?? ["readSession"])
        let policy = try parsePermissionMode(fields.scalars["graphContextPolicy"] ?? "readOnly")
        let manifest = SkillRuntimeManifest(
            name: name,
            description: description,
            triggers: triggers,
            requiredCapabilities: capabilities,
            requiredSources: fields.arrays["requiredSources"] ?? fields.scalars["requiredSources"].map { [$0] } ?? [],
            globs: fields.arrays["globs"] ?? [],
            graphContextPolicy: policy,
            tags: fields.arrays["tags"] ?? [],
            icon: fields.scalars["icon"]
        )
        return (manifest, body)
    }

    private func parseSimpleYAML(_ text: String) -> (scalars: [String: String], arrays: [String: [String]]) {
        var scalars: [String: String] = [:]
        var arrays: [String: [String]] = [:]
        var currentArrayKey: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if trimmed.hasPrefix("- "), let key = currentArrayKey {
                arrays[key, default: []].append(cleanYAMLValue(String(trimmed.dropFirst(2))))
                continue
            }
            currentArrayKey = nil
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                arrays[key] = []
                currentArrayKey = key
            } else {
                scalars[key] = cleanYAMLValue(value)
            }
        }
        return (scalars, arrays)
    }

    private func cleanYAMLValue(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (result.hasPrefix("\"") && result.hasSuffix("\"")) || (result.hasPrefix("'") && result.hasSuffix("'")) {
            result.removeFirst()
            result.removeLast()
        }
        return result
    }

    private func parseTriggers(_ values: [String]) throws -> [ProductOSSkillTrigger] {
        try values.map { value in
            guard let trigger = ProductOSSkillTrigger(rawValue: value) else { throw AppSkillRuntimeRepositoryError.unsupportedTrigger(value) }
            return trigger
        }
    }

    private func parseCapabilities(_ values: [String]) throws -> [AgentPermissionCapability] {
        try values.map { value in
            guard let capability = AgentPermissionCapability(rawValue: value) else { throw AppSkillRuntimeRepositoryError.unsupportedCapability(value) }
            return capability
        }
    }

    private func parsePermissionMode(_ value: String) throws -> AgentPermissionMode {
        guard let mode = AgentPermissionMode(rawValue: value) else { throw AppSkillRuntimeRepositoryError.unsupportedPermissionMode(value) }
        return mode
    }
}
