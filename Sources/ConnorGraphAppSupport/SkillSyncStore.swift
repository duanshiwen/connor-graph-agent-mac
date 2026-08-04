import Foundation
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
        return scanner.scan(storagePaths: storagePaths).packages
            .filter { $0.sourceTier == .user }
            .map(SyncSkillPack.init(package:))
    }

    public func pack(id: String) throws -> SyncSkillPack? {
        try listUserPacks().first { $0.id == id }
    }

    /// 应用远端技能包：同 id 已存在则更新其目录，否则按 slug 新建目录并写 SKILL.md。
    public func apply(_ pack: SyncSkillPack) throws {
        let snapshot = scanner.scan(storagePaths: storagePaths)
        let existing = snapshot.packages.first { $0.id.rawValue == pack.id }
        let directory: URL
        if let existing {
            directory = URL(fileURLWithPath: existing.packagePath)
        } else {
            directory = storagePaths.skillsDirectory.appendingPathComponent(Self.slugify(pack.id), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.skillMarkdown(pack).write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    public func delete(id: String) throws {
        guard let existing = scanner.scan(storagePaths: storagePaths).packages.first(where: { $0.id.rawValue == id }) else { return }
        try FileManager.default.removeItem(at: URL(fileURLWithPath: existing.packagePath))
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
