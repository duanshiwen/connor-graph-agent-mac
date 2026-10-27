import Foundation
import CryptoKit
import ConnorGraphCore

/// 技能同步存储适配：扫描用户级技能包、落盘/更新、按 tombstone 删除。
/// 仅同步用户级（sourceTier == .user）技能包，内置/全局等技能不参与。
public struct SkillSyncStore: @unchecked Sendable {
    public var scanner: SkillPackageScanner
    public var storagePaths: AppStoragePaths

    public init(scanner: SkillPackageScanner = .applicationDefault(), storagePaths: AppStoragePaths) {
        self.scanner = scanner
        self.storagePaths = storagePaths
    }

    public func listUserPacks() throws -> [SyncSkillPack] {
        return try scanner.scan(storagePaths: storagePaths).packages
            .filter { $0.sourceTier == .user }
            .map { try Self.wire(package: $0) }
    }

    public func pack(id: String) throws -> SyncSkillPack? {
        try listUserPacks().first { $0.id == id }
    }

    /// 应用远端技能包：同 id 已存在则更新其目录，否则按 slug 新建目录并写 SKILL.md。
    public func apply(_ pack: SyncSkillPack) throws {
        let snapshot = scanner.scan(storagePaths: storagePaths)
        let existing = try snapshot.packages.filter { $0.sourceTier == .user }.first { try Self.wire(package: $0).id == pack.id }
        let directory: URL
        if let existing {
            directory = URL(fileURLWithPath: existing.packagePath)
        } else {
            directory = storagePaths.skillsDirectory.appendingPathComponent("synced-" + String(Self.hash(Data(pack.id.utf8)).prefix(32)), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let markdown = Self.skillMarkdown(pack)
        try markdown.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try JSONEncoder().encode(Metadata(wire: pack, markdownHash: Self.hash(Data(markdown.utf8))))
            .write(to: directory.appendingPathComponent(".connor-sync.json"), options: .atomic)
    }

    public func delete(id: String) throws {
        guard let existing = try scanner.scan(storagePaths: storagePaths).packages.filter { $0.sourceTier == .user }.first(where: { try Self.wire(package: $0).id == id }) else { return }
        try FileManager.default.removeItem(at: URL(fileURLWithPath: existing.packagePath))
    }

    private struct Metadata: Codable { var wire: SyncSkillPack; var markdownHash: String }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func wire(package: SkillPackage) throws -> SyncSkillPack {
        let directory = URL(fileURLWithPath: package.packagePath)
        let metadataURL = directory.appendingPathComponent(".connor-sync.json")
        var current = SyncSkillPack(package: package)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return current }
        let metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
        if try hash(Data(contentsOf: directory.appendingPathComponent("SKILL.md"))) == metadata.markdownHash { return metadata.wire }
        current.id = metadata.wire.id
        current.createdAt = metadata.wire.createdAt
        current.category = metadata.wire.category
        current.templatesJson = metadata.wire.templatesJson
        return current
    }

    private static func slugify(_ value: String) -> String {
        var result = ""
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains(scalar) {
                result.append(Character(scalar))
            } else if !result.isEmpty && !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        if result.count < 3 { result = "skill-\(result.isEmpty ? "pack" : result)" }
        return String(result.prefix(64))
    }

    private static func skillMarkdown(_ pack: SyncSkillPack) -> String {
        let name = pack.title.replacingOccurrences(of: "\"", with: "\\\"")
        let desc = pack.summary.replacingOccurrences(of: "\"", with: "\\\"")
        let lifecycle = pack.enabled ? "stable" : "deprecated"
        let instructions = (try? JSONSerialization.jsonObject(with: Data(pack.instructionsJson.utf8))) as? [String] ?? []
        let body = instructions.joined(separator: "\n\n")
        return """
        ---
        name: "\(name)"
        description: "\(desc)"
        tags:
          - synced
          - skill
        globs: []
        x-connor:
          lifecycle: \(lifecycle)
          riskLevel: low
          requiredCapabilities:
            - readSession
          graphContextPolicy: readOnly
          sourcePolicy: preenableIfReady
        ---

        # \(name)

        \(body)
        """
    }
}

extension SyncSkillPack {
    init(package: SkillPackage) {
        id = package.id.rawValue
        title = package.manifest.name
        category = "general"
        summary = package.manifest.description
        instructionsJson = Self.jsonArray([package.instructions])
        templatesJson = "[]"
        enabled = package.manifest.connor.lifecycle != .deprecated
        createdAt = Int64(package.createdAt.timeIntervalSince1970 * 1_000)
        updatedAt = Int64(package.updatedAt.timeIntervalSince1970 * 1_000)
    }

    private static func jsonArray(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
