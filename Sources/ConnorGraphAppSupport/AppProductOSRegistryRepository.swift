import Foundation
import ConnorGraphCore

public enum AppProductOSRegistryError: Error, Equatable, CustomStringConvertible {
    case duplicateSourceID(String)
    case duplicateSkillID(String)
    case invalidID(String)
    case unsafePermissionMode(String)

    public var description: String {
        switch self {
        case .duplicateSourceID(let id): "duplicateSourceID: \(id)"
        case .duplicateSkillID(let id): "duplicateSkillID: \(id)"
        case .invalidID(let id): "invalidID: \(id)"
        case .unsafePermissionMode(let message): "unsafePermissionMode: \(message)"
        }
    }
}

public struct AppProductOSRegistryRepository: Sendable {
    public var storagePaths: AppStoragePaths

    public init(storagePaths: AppStoragePaths) {
        self.storagePaths = storagePaths
    }

    public var registryURL: URL { storagePaths.configDirectory.appendingPathComponent("product-os-registry.json") }

    public func loadOrCreateDefault() throws -> ProductOSRegistrySnapshot {
        try storagePaths.ensureDirectoryHierarchy()
        try ensureRegistryDirectories()
        if FileManager.default.fileExists(atPath: registryURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ProductOSRegistrySnapshot.self, from: try Data(contentsOf: registryURL))
            try validate(snapshot)
            return snapshot
        }
        let snapshot = ProductOSRegistrySnapshot.default
        try save(snapshot)
        return snapshot
    }

    public func save(_ snapshot: ProductOSRegistrySnapshot) throws {
        try validate(snapshot)
        try FileManager.default.createDirectory(at: storagePaths.configDirectory, withIntermediateDirectories: true)
        try ensureRegistryDirectories()
        var normalized = snapshot
        normalized.sources = snapshot.sources.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        normalized.skills = snapshot.skills.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        normalized.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: registryURL, options: .atomic)
    }

    public func setSourceStatus(id: String, status: ProductOSRegistryEntryStatus) throws -> ProductOSRegistrySnapshot {
        var snapshot = try loadOrCreateDefault()
        guard let index = snapshot.sources.firstIndex(where: { $0.id == id }) else { return snapshot }
        snapshot.sources[index].status = status
        snapshot.sources[index].updatedAt = Date()
        try save(snapshot)
        return try loadOrCreateDefault()
    }

    public func setSkillStatus(id: String, status: ProductOSRegistryEntryStatus) throws -> ProductOSRegistrySnapshot {
        var snapshot = try loadOrCreateDefault()
        guard let index = snapshot.skills.firstIndex(where: { $0.id == id }) else { return snapshot }
        snapshot.skills[index].status = status
        snapshot.skills[index].updatedAt = Date()
        try save(snapshot)
        return try loadOrCreateDefault()
    }

    public func ensureRegistryDirectories() throws {
        try FileManager.default.createDirectory(at: storagePaths.sourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storagePaths.skillsDirectory, withIntermediateDirectories: true)
        for source in ProductOSSourceDefinition.defaults {
            let directory = storagePaths.sourcesDirectory.appendingPathComponent(source.id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for skill in ProductOSSkillDefinition.defaults {
            let directory = storagePaths.skillsDirectory.appendingPathComponent(skill.id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func validate(_ snapshot: ProductOSRegistrySnapshot) throws {
        var sourceIDs: Set<String> = []
        for source in snapshot.sources {
            try validateID(source.id)
            if !sourceIDs.insert(source.id).inserted { throw AppProductOSRegistryError.duplicateSourceID(source.id) }
            if source.graphWritePolicy == .allowAll {
                throw AppProductOSRegistryError.unsafePermissionMode("Source \(source.id) cannot use allowAll graph write policy")
            }
        }
        var skillIDs: Set<String> = []
        for skill in snapshot.skills {
            try validateID(skill.id)
            if !skillIDs.insert(skill.id).inserted { throw AppProductOSRegistryError.duplicateSkillID(skill.id) }
            if skill.graphContextPolicy == .allowAll {
                throw AppProductOSRegistryError.unsafePermissionMode("Skill \(skill.id) cannot use allowAll graph context policy")
            }
        }
    }

    private func validateID(_ id: String) throws {
        let pattern = #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw AppProductOSRegistryError.invalidID(id)
        }
    }
}
