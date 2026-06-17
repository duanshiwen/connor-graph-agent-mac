import Foundation
import ConnorGraphCore

public enum SkillInstallationState: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case installed
    case enabled
    case disabled
    case hidden
    case deleted
}

public struct SkillLifecycleRecord: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { packageID }
    public var packageID: String
    public var slug: String
    public var version: String?
    public var publisher: String?
    public var lifecycle: SkillLifecycleState
    public var installationState: SkillInstallationState
    public var updatedAt: Date

    public init(packageID: String, slug: String, version: String? = nil, publisher: String? = nil, lifecycle: SkillLifecycleState = .stable, installationState: SkillInstallationState = .enabled, updatedAt: Date = Date()) {
        self.packageID = packageID
        self.slug = slug
        self.version = version
        self.publisher = publisher
        self.lifecycle = lifecycle
        self.installationState = installationState
        self.updatedAt = updatedAt
    }
}

public struct SkillPackageIntegrity: Codable, Sendable, Equatable, Hashable {
    public var packageID: String
    public var fileCount: Int
    public var totalBytes: Int
    public var fileDigests: [String: String]

    public init(packageID: String, fileCount: Int, totalBytes: Int, fileDigests: [String: String]) {
        self.packageID = packageID
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.fileDigests = fileDigests
    }
}

public struct SkillLifecycleService: Sendable {
    public init() {}

    public func lifecycleRecord(for package: SkillPackage, state: SkillInstallationState = .enabled) -> SkillLifecycleRecord {
        SkillLifecycleRecord(
            packageID: package.id.rawValue,
            slug: package.slug.rawValue,
            version: package.manifest.version,
            publisher: package.manifest.publisher,
            lifecycle: package.manifest.connor.lifecycle,
            installationState: package.manifest.connor.lifecycle == .deprecated ? .disabled : state
        )
    }

    public func integrity(for package: SkillPackage) -> SkillPackageIntegrity {
        var digests: [String: String] = [:]
        var total = 0
        let files = (["SKILL.md"] + package.supportingFiles).sorted()
        for file in files {
            let url = URL(fileURLWithPath: package.packagePath).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url) else { continue }
            total += data.count
            digests[file] = stableDigest(data)
        }
        return SkillPackageIntegrity(packageID: package.id.rawValue, fileCount: digests.count, totalBytes: total, fileDigests: digests)
    }

    public func exportManifest(package: SkillPackage, integrity: SkillPackageIntegrity? = nil) -> [String: String] {
        var manifest: [String: String] = [
            "slug": package.slug.rawValue,
            "name": package.manifest.name,
            "sourceTier": package.sourceTier.rawValue,
            "lifecycle": package.manifest.connor.lifecycle.rawValue,
            "riskLevel": package.riskLevel.rawValue
        ]
        if let version = package.manifest.version { manifest["version"] = version }
        if let publisher = package.manifest.publisher { manifest["publisher"] = publisher }
        if let integrity { manifest["fileCount"] = "\(integrity.fileCount)"; manifest["totalBytes"] = "\(integrity.totalBytes)" }
        return manifest
    }

    private func stableDigest(_ data: Data) -> String {
        // Lightweight deterministic checksum for package integrity evidence without adding CryptoKit dependency.
        let value = data.reduce(UInt64(1469598103934665603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1099511628211
        }
        return String(value, radix: 16)
    }
}
