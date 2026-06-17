import Foundation
import ConnorGraphCore

public struct SkillPackageScanRoot: Sendable, Equatable {
    public var tier: SkillSourceTier
    public var rootURL: URL
    public var isContextual: Bool

    public init(tier: SkillSourceTier, rootURL: URL, isContextual: Bool = false) {
        self.tier = tier
        self.rootURL = rootURL
        self.isContextual = isContextual
    }
}

public struct SkillPackageScanSnapshot: Sendable, Equatable {
    public var packages: [SkillPackage]
    public var resolutions: [SkillResolution]
    public var warnings: [String]
    public var scannedAt: Date

    public init(packages: [SkillPackage], resolutions: [SkillResolution], warnings: [String] = [], scannedAt: Date = Date()) {
        self.packages = packages
        self.resolutions = resolutions
        self.warnings = warnings
        self.scannedAt = scannedAt
    }

    public func resolution(slug: String) -> SkillResolution? {
        resolutions.first { $0.slug.rawValue == slug }
    }
}

public struct SkillPackageScanner {
    public var parser: SkillManifestParser
    public var fileManager: FileManager
    public var globalSkillsDirectory: URL
    public var bundledSkillsDirectory: URL?

    public init(
        parser: SkillManifestParser = SkillManifestParser(),
        fileManager: FileManager = .default,
        globalSkillsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills", isDirectory: true),
        bundledSkillsDirectory: URL? = nil
    ) {
        self.parser = parser
        self.fileManager = fileManager
        self.globalSkillsDirectory = globalSkillsDirectory
        self.bundledSkillsDirectory = bundledSkillsDirectory
    }

    public func defaultRoots(storagePaths: AppStoragePaths, projectRoots: [URL] = [], nestedRoots: [URL] = []) -> [SkillPackageScanRoot] {
        var roots: [SkillPackageScanRoot] = []
        if let bundledSkillsDirectory { roots.append(SkillPackageScanRoot(tier: .bundled, rootURL: bundledSkillsDirectory)) }
        roots.append(SkillPackageScanRoot(tier: .global, rootURL: globalSkillsDirectory))
        roots.append(SkillPackageScanRoot(tier: .user, rootURL: storagePaths.skillsDirectory))
        for projectRoot in projectRoots {
            roots.append(SkillPackageScanRoot(tier: .project, rootURL: projectRoot.appendingPathComponent(".agents/skills", isDirectory: true)))
        }
        for nestedRoot in nestedRoots {
            roots.append(SkillPackageScanRoot(tier: .nestedContextual, rootURL: nestedRoot.appendingPathComponent(".agents/skills", isDirectory: true), isContextual: true))
        }
        return roots
    }

    public func scan(roots: [SkillPackageScanRoot]) -> SkillPackageScanSnapshot {
        var packages: [SkillPackage] = []
        var warnings: [String] = []
        for root in roots {
            let result = scanRoot(root)
            packages.append(contentsOf: result.packages)
            warnings.append(contentsOf: result.warnings)
        }
        let resolutions = buildResolutions(packages: packages)
        return SkillPackageScanSnapshot(packages: packages.sorted(by: packageSort), resolutions: resolutions, warnings: warnings)
    }

    public func scan(storagePaths: AppStoragePaths, projectRoots: [URL] = [], nestedRoots: [URL] = []) -> SkillPackageScanSnapshot {
        scan(roots: defaultRoots(storagePaths: storagePaths, projectRoots: projectRoots, nestedRoots: nestedRoots))
    }

    public func productOSSkillDefinitions(from snapshot: SkillPackageScanSnapshot) -> [ProductOSSkillDefinition] {
        snapshot.resolutions.compactMap { resolution in
            guard let package = resolution.selected else { return nil }
            return ProductOSSkillDefinition(
                id: package.slug.rawValue,
                displayName: package.manifest.name,
                scope: package.sourceTier.legacyScope,
                status: package.manifest.connor.lifecycle == .deprecated ? .deprecated : .enabled,
                manifestPath: package.skillFilePath,
                triggers: [.manual],
                requiredCapabilities: package.manifest.connor.requiredCapabilities,
                graphContextPolicy: package.manifest.connor.graphContextPolicy,
                tags: Array(Set(package.manifest.tags + ["skill", package.sourceTier.rawValue])).sorted(),
                notes: package.manifest.description,
                createdAt: package.createdAt,
                updatedAt: package.updatedAt
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func scanRoot(_ root: SkillPackageScanRoot) -> (packages: [SkillPackage], warnings: [String]) {
        guard fileManager.fileExists(atPath: root.rootURL.path) else { return ([], []) }
        var packages: [SkillPackage] = []
        var warnings: [String] = []
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: root.rootURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])
        } catch {
            return ([], ["Failed to read skill root \(root.rootURL.path): \(error)"])
        }
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let slug = entry.lastPathComponent
            let skillURL = entry.appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: skillURL.path) else { continue }
            do {
                let raw = try String(contentsOf: skillURL, encoding: .utf8)
                let parsed = try parser.parse(markdown: raw, slug: slug)
                let supportingFiles = listSupportingFiles(in: entry)
                let package = SkillPackage(
                    id: SkillPackageID("\(root.tier.rawValue):\(entry.path)"),
                    slug: SkillSlug(slug),
                    sourceTier: root.tier,
                    manifest: parsed.manifest,
                    instructions: parsed.instructions,
                    packagePath: entry.path,
                    skillFilePath: skillURL.path,
                    supportingFiles: supportingFiles,
                    trustState: trustState(for: root.tier),
                    riskLevel: max(parsed.manifest.connor.riskLevel, inferredPackageRisk(parsed.manifest)),
                    createdAt: fileDate(entry, key: .creationDateKey) ?? Date(),
                    updatedAt: fileDate(skillURL, key: .contentModificationDateKey) ?? Date()
                )
                packages.append(package)
            } catch {
                warnings.append("Invalid skill \(slug) at \(skillURL.path): \(error)")
            }
        }
        return (packages, warnings)
    }

    private func listSupportingFiles(in directory: URL) -> [String] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var files: [String] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent != "SKILL.md" else { continue }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                files.append(url.path.replacingOccurrences(of: directory.path + "/", with: ""))
            }
        }
        return files.sorted()
    }

    private func buildResolutions(packages: [SkillPackage]) -> [SkillResolution] {
        let grouped = Dictionary(grouping: packages, by: { $0.slug.rawValue })
        return grouped.keys.sorted().map { slug in
            let candidates = (grouped[slug] ?? []).sorted(by: precedenceSort)
            let selected = candidates.last
            let warnings = candidates.count > 1 ? ["Skill \(slug) has \(candidates.count) candidates; selected \(selected?.sourceTier.rawValue ?? "unknown") by precedence."] : []
            return SkillResolution(slug: SkillSlug(slug), selected: selected, candidates: candidates, warnings: warnings)
        }
    }

    private func precedenceSort(_ lhs: SkillPackage, _ rhs: SkillPackage) -> Bool {
        precedence(lhs.sourceTier) < precedence(rhs.sourceTier)
    }

    private func packageSort(_ lhs: SkillPackage, _ rhs: SkillPackage) -> Bool {
        if lhs.slug.rawValue == rhs.slug.rawValue { return precedence(lhs.sourceTier) < precedence(rhs.sourceTier) }
        return lhs.slug.rawValue < rhs.slug.rawValue
    }

    private func precedence(_ tier: SkillSourceTier) -> Int {
        switch tier {
        case .bundled: 0
        case .global: 1
        case .user: 2
        case .teamManaged: 3
        case .project: 4
        case .nestedContextual: 5
        case .marketplace: 6
        case .enterprise: 7
        }
    }

    private func trustState(for tier: SkillSourceTier) -> SkillTrustState {
        switch tier {
        case .bundled: .bundledTrusted
        case .global, .user: .userTrusted
        case .project, .nestedContextual: .projectRequiresTrust
        case .teamManaged, .enterprise: .trusted
        case .marketplace: .unknown
        }
    }

    private func inferredPackageRisk(_ manifest: SkillManifest) -> SkillRiskLevel {
        if manifest.shell != nil { return .high }
        if !manifest.allowedTools.isEmpty || !manifest.alwaysAllow.isEmpty { return .medium }
        return .low
    }

    private func fileDate(_ url: URL, key: URLResourceKey) -> Date? {
        try? url.resourceValues(forKeys: [key]).allValues[key] as? Date
    }
}
