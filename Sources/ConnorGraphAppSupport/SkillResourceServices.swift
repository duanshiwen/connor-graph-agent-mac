import Foundation
import ConnorGraphCore

public enum SkillResourceError: Error, Sendable, Equatable, CustomStringConvertible {
    case outsidePackage(String)
    case missingResource(String)
    case shellExecutionDisabled(String)

    public var description: String {
        switch self {
        case .outsidePackage(let path): "outsidePackage: \(path)"
        case .missingResource(let path): "missingResource: \(path)"
        case .shellExecutionDisabled(let command): "shellExecutionDisabled: \(command)"
        }
    }
}

public struct SkillSupportingResource: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String
    public var absolutePath: String
    public var byteCount: Int
    public var preview: String

    public init(relativePath: String, absolutePath: String, byteCount: Int, preview: String) {
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.byteCount = byteCount
        self.preview = preview
    }
}

public struct SkillDynamicContextPlaceholder: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var command: String
    public var replacement: String
    public var requiresApproval: Bool

    public init(id: String = UUID().uuidString, command: String, replacement: String, requiresApproval: Bool = true) {
        self.id = id
        self.command = command
        self.replacement = replacement
        self.requiresApproval = requiresApproval
    }
}

public struct SkillResourceService: Sendable {
    public var maxPreviewBytes: Int

    public init(maxPreviewBytes: Int = 8_192) {
        self.maxPreviewBytes = maxPreviewBytes
    }

    public func substituteSkillDirectoryVariables(in text: String, package: SkillPackage) -> String {
        text
            .replacingOccurrences(of: "${CONNOR_SKILL_DIR}", with: package.packagePath)
            .replacingOccurrences(of: "${CLAUDE_SKILL_DIR}", with: package.packagePath)
    }

    public func loadSupportingResource(relativePath: String, package: SkillPackage) throws -> SkillSupportingResource {
        let packageURL = URL(fileURLWithPath: package.packagePath).standardizedFileURL
        let resourceURL = packageURL.appendingPathComponent(relativePath).standardizedFileURL
        guard resourceURL.path.hasPrefix(packageURL.path + "/") else { throw SkillResourceError.outsidePackage(relativePath) }
        guard FileManager.default.fileExists(atPath: resourceURL.path) else { throw SkillResourceError.missingResource(relativePath) }
        let data = try Data(contentsOf: resourceURL)
        let previewData = data.prefix(maxPreviewBytes)
        let preview = String(data: previewData, encoding: .utf8) ?? "[binary resource omitted]"
        return SkillSupportingResource(relativePath: relativePath, absolutePath: resourceURL.path, byteCount: data.count, preview: preview)
    }

    public func detectDynamicContextPlaceholders(in text: String, shellExecutionEnabled: Bool = false) -> (rendered: String, placeholders: [SkillDynamicContextPlaceholder]) {
        var renderedLines: [String] = []
        var placeholders: [SkillDynamicContextPlaceholder] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("!") && trimmed.count > 1 {
                let command = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let replacement = shellExecutionEnabled ? "[shell command requires Connor Local Automation approval: \(command)]" : "[shell command execution disabled by Connor skill policy: \(command)]"
                placeholders.append(SkillDynamicContextPlaceholder(command: command, replacement: replacement, requiresApproval: true))
                renderedLines.append(replacement)
            } else {
                renderedLines.append(line)
            }
        }
        return (renderedLines.joined(separator: "\n"), placeholders)
    }
}
