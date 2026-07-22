import Foundation

public enum ExternalSkillLibrarySource: String, Sendable, Equatable, Hashable, CaseIterable {
    case claudeCode
    case codex
    case cursor
    case githubCopilot
    case geminiCLI
    case openCode
    case windsurf
    case cline
    case agents
    case custom

    public var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .githubCopilot: "GitHub Copilot"
        case .geminiCLI: "Gemini CLI"
        case .openCode: "OpenCode"
        case .windsurf: "Windsurf"
        case .cline: "Cline"
        case .agents: "通用 Agent"
        case .custom: "其他目录"
        }
    }
}

public struct ExternalSkillLibraryRoot: Sendable, Equatable {
    public var source: ExternalSkillLibrarySource
    public var directoryURL: URL

    public init(source: ExternalSkillLibrarySource, directoryURL: URL) {
        self.source = source
        self.directoryURL = directoryURL
    }
}

public struct ExternalSkillImportCandidate: Sendable, Equatable, Identifiable {
    public var id: String { "\(source.rawValue):\(packageURL.standardizedFileURL.path)" }
    public var source: ExternalSkillLibrarySource
    public var slug: String
    public var name: String
    public var description: String
    public var packageURL: URL
    public var isAlreadyImported: Bool

    public init(source: ExternalSkillLibrarySource, slug: String, name: String, description: String, packageURL: URL, isAlreadyImported: Bool) {
        self.source = source
        self.slug = slug
        self.name = name
        self.description = description
        self.packageURL = packageURL
        self.isAlreadyImported = isAlreadyImported
    }
}

public struct ExternalSkillLibraryDiscovery: Sendable, Equatable {
    public var candidates: [ExternalSkillImportCandidate]
    public var warnings: [String]

    public init(candidates: [ExternalSkillImportCandidate], warnings: [String] = []) {
        self.candidates = candidates
        self.warnings = warnings
    }
}

public struct ExternalSkillImportResult: Sendable, Equatable {
    public var importedIDs: [String]
    public var skippedIDs: [String]

    public init(importedIDs: [String], skippedIDs: [String]) {
        self.importedIDs = importedIDs
        self.skippedIDs = skippedIDs
    }
}

public enum ExternalSkillLibraryImporterError: Error, LocalizedError, Sendable, Equatable {
    case symbolicLinkNotAllowed(String)

    public var errorDescription: String? {
        switch self {
        case .symbolicLinkNotAllowed(let path):
            "技能目录包含符号链接，已拒绝导入：\(path)"
        }
    }
}

public struct ExternalSkillLibraryImporter: @unchecked Sendable {
    public var roots: [ExternalSkillLibraryRoot]
    public var parser: SkillManifestParser
    public var fileManager: FileManager

    public init(
        roots: [ExternalSkillLibraryRoot]? = nil,
        parser: SkillManifestParser = SkillManifestParser(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.roots = roots ?? Self.defaultRoots(environment: environment, homeDirectory: homeDirectory)
        self.parser = parser
        self.fileManager = fileManager
    }

    public static func defaultRoots(environment: [String: String], homeDirectory: URL) -> [ExternalSkillLibraryRoot] {
        let claudeHome = environment["CLAUDE_CONFIG_DIR"].flatMap(nonEmptyURL)
            ?? homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        let codexHome = environment["CODEX_HOME"].flatMap(nonEmptyURL)
            ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let xdgConfigHome = environment["XDG_CONFIG_HOME"].flatMap(nonEmptyURL)
            ?? homeDirectory.appendingPathComponent(".config", isDirectory: true)
        return [
            ExternalSkillLibraryRoot(source: .claudeCode, directoryURL: claudeHome.appendingPathComponent("skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .codex, directoryURL: codexHome.appendingPathComponent("skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .cursor, directoryURL: homeDirectory.appendingPathComponent(".cursor/skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .githubCopilot, directoryURL: homeDirectory.appendingPathComponent(".copilot/skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .geminiCLI, directoryURL: homeDirectory.appendingPathComponent(".gemini/skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .openCode, directoryURL: xdgConfigHome.appendingPathComponent("opencode/skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .windsurf, directoryURL: homeDirectory.appendingPathComponent(".codeium/windsurf/skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .cline, directoryURL: homeDirectory.appendingPathComponent(".cline/skills", isDirectory: true)),
            ExternalSkillLibraryRoot(source: .agents, directoryURL: homeDirectory.appendingPathComponent(".agents/skills", isDirectory: true))
        ]
    }

    public func discover(destinationDirectory: URL, additionalRoots: [ExternalSkillLibraryRoot] = []) -> ExternalSkillLibraryDiscovery {
        var candidates: [ExternalSkillImportCandidate] = []
        var warnings: [String] = []

        for root in roots + additionalRoots {
            guard fileManager.fileExists(atPath: root.directoryURL.path) else { continue }
            let entries: [URL]
            do {
                if fileManager.fileExists(atPath: root.directoryURL.appendingPathComponent("SKILL.md").path) {
                    entries = [root.directoryURL]
                } else {
                    entries = try fileManager.contentsOfDirectory(
                        at: root.directoryURL,
                        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                        options: [.skipsHiddenFiles]
                    )
                }
            } catch {
                warnings.append("无法读取 \(root.source.title) 技能目录：\(error.localizedDescription)")
                continue
            }

            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let slug = entry.lastPathComponent
                do {
                    let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                    let skillURL = entry.appendingPathComponent("SKILL.md")
                    guard fileManager.fileExists(atPath: skillURL.path) else { continue }
                    try validateNoSymbolicLinks(in: entry)
                    let markdown = try String(contentsOf: skillURL, encoding: .utf8)
                    let parsed = try parser.parse(markdown: markdown, slug: slug)
                    candidates.append(ExternalSkillImportCandidate(
                        source: root.source,
                        slug: slug,
                        name: parsed.manifest.name,
                        description: parsed.manifest.description,
                        packageURL: entry,
                        isAlreadyImported: fileManager.fileExists(
                            atPath: destinationDirectory.appendingPathComponent(slug, isDirectory: true).path
                        )
                    ))
                } catch {
                    warnings.append("无法导入 \(root.source.title) 技能 \(slug)：\(error.localizedDescription)")
                }
            }
        }

        candidates.sort {
            if $0.source != $1.source { return $0.source.title < $1.source.title }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return ExternalSkillLibraryDiscovery(candidates: candidates, warnings: warnings)
    }

    public func importSkills(_ candidates: [ExternalSkillImportCandidate], destinationDirectory: URL) throws -> ExternalSkillImportResult {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var importedIDs: [String] = []
        var skippedIDs: [String] = []

        for candidate in candidates {
            try validateNoSymbolicLinks(in: candidate.packageURL)
            let destination = destinationDirectory.appendingPathComponent(candidate.slug, isDirectory: true)
            guard !fileManager.fileExists(atPath: destination.path) else {
                skippedIDs.append(candidate.id)
                continue
            }

            let staging = destinationDirectory.appendingPathComponent(".\(candidate.slug).import-\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.copyItem(at: candidate.packageURL, to: staging)
                try fileManager.moveItem(at: staging, to: destination)
                importedIDs.append(candidate.id)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
        }

        return ExternalSkillImportResult(importedIDs: importedIDs, skippedIDs: skippedIDs)
    }

    private func validateNoSymbolicLinks(in directory: URL) throws {
        let rootValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        if rootValues.isSymbolicLink == true {
            throw ExternalSkillLibraryImporterError.symbolicLinkNotAllowed(directory.path)
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else { return }
        for case let fileURL as URL in enumerator {
            if try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw ExternalSkillLibraryImporterError.symbolicLinkNotAllowed(fileURL.path)
            }
        }
    }

    private static func nonEmptyURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }
}
