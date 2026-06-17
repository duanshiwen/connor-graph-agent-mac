import Foundation
import ConnorGraphCore

public enum SkillManifestParserError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingFrontmatter(String)
    case missingRequiredField(String)
    case emptyInstructions(String)
    case invalidSlug(String)
    case unsafeGraphPolicy(String)
    case unsupportedCapability(String)
    case unsupportedPermissionMode(String)

    public var description: String {
        switch self {
        case .missingFrontmatter(let slug): "missingFrontmatter: \(slug)"
        case .missingRequiredField(let field): "missingRequiredField: \(field)"
        case .emptyInstructions(let slug): "emptyInstructions: \(slug)"
        case .invalidSlug(let slug): "invalidSlug: \(slug)"
        case .unsafeGraphPolicy(let slug): "unsafeGraphPolicy: \(slug)"
        case .unsupportedCapability(let value): "unsupportedCapability: \(value)"
        case .unsupportedPermissionMode(let value): "unsupportedPermissionMode: \(value)"
        }
    }
}

public struct ParsedSkillMarkdown: Sendable, Equatable {
    public var manifest: SkillManifest
    public var instructions: String
    public var rawFields: [String: SkillYAMLValue]

    public init(manifest: SkillManifest, instructions: String, rawFields: [String: SkillYAMLValue]) {
        self.manifest = manifest
        self.instructions = instructions
        self.rawFields = rawFields
    }
}

public indirect enum SkillYAMLValue: Sendable, Equatable, Hashable {
    case string(String)
    case bool(Bool)
    case array([String])
    case object([String: SkillYAMLValue])

    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .bool(let value): value ? "true" : "false"
        case .array, .object: nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .string(let value):
            switch value.lowercased() {
            case "true", "yes": true
            case "false", "no": false
            default: nil
            }
        case .array, .object: nil
        }
    }

    public var arrayValue: [String]? {
        switch self {
        case .array(let values): values
        case .string(let value): value.isEmpty ? [] : [value]
        case .bool, .object: nil
        }
    }

    public var objectValue: [String: SkillYAMLValue]? {
        switch self {
        case .object(let value): value
        default: nil
        }
    }
}

public struct SkillManifestParser: Sendable {
    public init() {}

    public func parse(markdown raw: String, slug: String) throws -> ParsedSkillMarkdown {
        guard SkillSlug(slug).isValid else { throw SkillManifestParserError.invalidSlug(slug) }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { throw SkillManifestParserError.missingFrontmatter(slug) }
        let remainder = String(normalized.dropFirst(4))
        guard let endRange = remainder.range(of: "\n---") else { throw SkillManifestParserError.missingFrontmatter(slug) }
        let frontmatter = String(remainder[..<endRange.lowerBound])
        let body = String(remainder[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw SkillManifestParserError.emptyInstructions(slug) }
        let fields = parseYAMLSubset(frontmatter)
        guard let description = string(fields, "description"), !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillManifestParserError.missingRequiredField("description")
        }
        let name = string(fields, "name")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false) ? name! : slug
        let connorObject = object(fields, "x-connor") ?? object(fields, "connor") ?? [:]
        let requiredCapabilities = try parseCapabilities(array(connorObject, "requiredCapabilities") ?? array(fields, "requiredCapabilities") ?? inferCapabilities(fields: fields))
        let graphPolicy = try parsePermissionMode(string(connorObject, "graphContextPolicy") ?? string(fields, "graphContextPolicy") ?? "readOnly")
        if graphPolicy == .allowAll { throw SkillManifestParserError.unsafeGraphPolicy(slug) }
        let connor = ConnorSkillExtension(
            requiredCapabilities: requiredCapabilities,
            graphContextPolicy: graphPolicy,
            sourcePolicy: SkillSourcePolicy(rawValue: string(connorObject, "sourcePolicy") ?? "preenableIfReady") ?? .preenableIfReady,
            trustPolicy: string(connorObject, "trustPolicy"),
            auditLevel: SkillAuditLevel(rawValue: string(connorObject, "auditLevel") ?? "standard") ?? .standard,
            riskLevel: SkillRiskLevel(rawValue: string(connorObject, "riskLevel") ?? inferredRisk(fields: fields).rawValue) ?? inferredRisk(fields: fields),
            lifecycle: SkillLifecycleState(rawValue: string(connorObject, "lifecycle") ?? "stable") ?? .stable,
            commercialTier: string(connorObject, "commercialTier")
        )
        let knownFieldsA: Set<String> = [
            "name", "description", "when_to_use", "whenToUse", "argument-hint", "argumentHint",
            "arguments", "globs", "paths", "requiredSources", "alwaysAllow",
            "allowed-tools", "allowedTools", "disallowed-tools", "disallowedTools"
        ]
        let knownFieldsB: Set<String> = [
            "disable-model-invocation", "disableModelInvocation", "user-invocable", "userInvocable",
            "model", "effort", "context", "agent", "shell", "icon", "tags",
            "version", "publisher", "x-connor", "connor", "requiredCapabilities",
            "graphContextPolicy", "triggers", "hidden"
        ]
        var unsupported: [String] = []
        for key in fields.keys {
            if !knownFieldsA.contains(key) && !knownFieldsB.contains(key) { unsupported.append(key) }
        }
        unsupported.sort()
        let warnings = unsupported.map { "Unsupported skill frontmatter field preserved as warning: \($0)" }
        let whenToUse = string(fields, "when_to_use") ?? string(fields, "whenToUse")
        let argumentHint = string(fields, "argument-hint") ?? string(fields, "argumentHint")
        let arguments = array(fields, "arguments") ?? []
        let globs = array(fields, "globs") ?? []
        let paths = array(fields, "paths") ?? []
        let requiredSources = normalizedUnique(array(fields, "requiredSources") ?? [])
        let alwaysAllow = normalizedUnique(array(fields, "alwaysAllow") ?? [])
        let allowedTools = normalizedUnique(array(fields, "allowed-tools") ?? array(fields, "allowedTools") ?? [])
        let disallowedTools = normalizedUnique(array(fields, "disallowed-tools") ?? array(fields, "disallowedTools") ?? [])
        let disableModelInvocation = bool(fields, "disable-model-invocation") ?? bool(fields, "disableModelInvocation") ?? false
        let userInvocable = bool(fields, "user-invocable") ?? bool(fields, "userInvocable") ?? true
        let model = string(fields, "model")
        let effort = string(fields, "effort")
        let context = SkillExecutionContext(rawValue: string(fields, "context") ?? "inline") ?? .inline
        let agent = string(fields, "agent")
        let shell = string(fields, "shell")
        let icon = string(fields, "icon")
        let tags = array(fields, "tags") ?? []
        let version = string(fields, "version")
        let publisher = string(fields, "publisher")
        let hidden = bool(fields, "hidden") ?? false
        let manifest = SkillManifest(
            name: resolvedName,
            description: description,
            whenToUse: whenToUse,
            argumentHint: argumentHint,
            arguments: arguments,
            globs: globs,
            paths: paths,
            requiredSources: requiredSources,
            alwaysAllow: alwaysAllow,
            allowedTools: allowedTools,
            disallowedTools: disallowedTools,
            disableModelInvocation: disableModelInvocation,
            userInvocable: userInvocable,
            model: model,
            effort: effort,
            context: context,
            agent: agent,
            shell: shell,
            icon: icon,
            tags: tags,
            version: version,
            publisher: publisher,
            hidden: hidden,
            connor: connor,
            unsupportedFields: unsupported,
            warnings: warnings
        )
        return ParsedSkillMarkdown(manifest: manifest, instructions: body, rawFields: fields)
    }

    public func parseYAMLSubset(_ text: String) -> [String: SkillYAMLValue] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fields: [String: SkillYAMLValue] = [:]
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { index += 1; continue }
            guard indentation(rawLine) == 0, let colon = trimmed.firstIndex(of: ":") else { index += 1; continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                let child = collectIndentedBlock(lines: lines, start: index + 1, parentIndent: indentation(rawLine))
                fields[key] = parseBlock(child.lines)
                index = child.nextIndex
            } else {
                fields[key] = parseScalarOrInlineArray(value)
                index += 1
            }
        }
        return fields
    }

    private func collectIndentedBlock(lines: [String], start: Int, parentIndent: Int) -> (lines: [String], nextIndex: Int) {
        var child: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { child.append(line); index += 1; continue }
            if indentation(line) <= parentIndent { break }
            child.append(String(line.dropFirst(min(indentation(line), parentIndent + 2))))
            index += 1
        }
        return (child, index)
    }

    private func parseBlock(_ lines: [String]) -> SkillYAMLValue {
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        if meaningful.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }) {
            return .array(meaningful.map { cleanYAMLValue(String($0.trimmingCharacters(in: .whitespaces).dropFirst(2))) })
        }
        var object: [String: SkillYAMLValue] = [:]
        for line in meaningful {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            object[key] = value.isEmpty ? .string("") : parseScalarOrInlineArray(value)
        }
        return .object(object)
    }

    private func parseScalarOrInlineArray(_ value: String) -> SkillYAMLValue {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("[") && cleaned.hasSuffix("]") {
            let inner = String(cleaned.dropFirst().dropLast())
            let values = inner.split(separator: ",").map { cleanYAMLValue(String($0)) }.filter { !$0.isEmpty }
            return .array(values)
        }
        switch cleaned.lowercased() {
        case "true", "yes": return .bool(true)
        case "false", "no": return .bool(false)
        default: return .string(cleanYAMLValue(cleaned))
        }
    }

    private func indentation(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private func cleanYAMLValue(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (result.hasPrefix("\"") && result.hasSuffix("\"")) || (result.hasPrefix("'") && result.hasSuffix("'")) {
            result.removeFirst()
            result.removeLast()
        }
        return result
    }

    private func string(_ fields: [String: SkillYAMLValue], _ key: String) -> String? { fields[key]?.stringValue }
    private func bool(_ fields: [String: SkillYAMLValue], _ key: String) -> Bool? { fields[key]?.boolValue }
    private func array(_ fields: [String: SkillYAMLValue], _ key: String) -> [String]? { fields[key]?.arrayValue }
    private func object(_ fields: [String: SkillYAMLValue], _ key: String) -> [String: SkillYAMLValue]? { fields[key]?.objectValue }

    private func normalizedUnique(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func inferCapabilities(fields: [String: SkillYAMLValue]) -> [String] {
        var capabilities = ["readSession"]
        let toolNames = (array(fields, "alwaysAllow") ?? []) + (array(fields, "allowed-tools") ?? []) + (array(fields, "allowedTools") ?? [])
        for tool in toolNames.map({ $0.lowercased() }) {
            if tool.contains("bash") || tool.contains("shell") { capabilities.append("runWorkspaceShellCommand") }
            if tool.contains("write") || tool.contains("edit") { capabilities.append("writeWorkspaceFile") }
            if tool.contains("web") || tool.contains("fetch") { capabilities.append("externalNetwork") }
        }
        return normalizedUnique(capabilities)
    }

    private func inferredRisk(fields: [String: SkillYAMLValue]) -> SkillRiskLevel {
        let tools = ((array(fields, "alwaysAllow") ?? []) + (array(fields, "allowed-tools") ?? []) + (array(fields, "allowedTools") ?? [])).map { $0.lowercased() }
        if tools.contains(where: { $0.contains("delete") || $0.contains("destructive") }) { return .critical }
        if tools.contains(where: { $0.contains("bash") || $0.contains("shell") || $0.contains("write") || $0.contains("edit") }) { return .high }
        if !(array(fields, "requiredSources") ?? []).isEmpty { return .medium }
        return .low
    }

    private func parseCapabilities(_ values: [String]) throws -> [AgentPermissionCapability] {
        try values.map { value in
            guard let capability = AgentPermissionCapability(rawValue: value) else { throw SkillManifestParserError.unsupportedCapability(value) }
            return capability
        }
    }

    private func parsePermissionMode(_ value: String) throws -> AgentPermissionMode {
        guard let mode = AgentPermissionMode(rawValue: value) else { throw SkillManifestParserError.unsupportedPermissionMode(value) }
        return mode
    }
}
