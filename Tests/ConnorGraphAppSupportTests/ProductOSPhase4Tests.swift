import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Product OS Phase 4 Tests")
struct ProductOSPhase4Tests {
    @Test func productOSRegistrySeedsSourcesSkillsAndDirectoriesUnderSingleHomeRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let repository = AppProductOSRegistryRepository(storagePaths: paths)

        let snapshot = try repository.loadOrCreateDefault()

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.sources.contains { $0.id == "local-filesystem" })
        #expect(snapshot.skills.contains { $0.id == "graph-memory-review" })
        #expect(FileManager.default.fileExists(atPath: repository.registryURL.path))
        #expect(FileManager.default.fileExists(atPath: paths.sourcesDirectory.appendingPathComponent("local-filesystem", isDirectory: true).path))
        #expect(FileManager.default.fileExists(atPath: paths.skillsDirectory.appendingPathComponent("graph-memory-review", isDirectory: true).path))
        #expect(paths.sourcesDirectory.path.contains("workspace") == false)
        #expect(paths.skillsDirectory.path.contains("workspace") == false)
    }

    @Test func productOSRegistryRejectsDuplicateIDsAndAllowAllPolicies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSRegistryRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))

        var duplicate = ProductOSRegistrySnapshot.default
        duplicate.sources.append(duplicate.sources[0])
        #expect(throws: AppProductOSRegistryError.self) {
            try repository.save(duplicate)
        }

        var unsafeSource = ProductOSRegistrySnapshot.default
        unsafeSource.sources[0].graphWritePolicy = .allowAll
        #expect(throws: AppProductOSRegistryError.self) {
            try repository.save(unsafeSource)
        }

        var unsafeSkill = ProductOSRegistrySnapshot.default
        unsafeSkill.skills[0].graphContextPolicy = .allowAll
        #expect(throws: AppProductOSRegistryError.self) {
            try repository.save(unsafeSkill)
        }
    }

    @Test func productOSRegistryPersistsSourceAndSkillStatusChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSRegistryRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))

        _ = try repository.loadOrCreateDefault()
        let afterSource = try repository.setSourceStatus(id: "mcp-source-registry", status: .needsReview)
        #expect(afterSource.sources.first { $0.id == "mcp-source-registry" }?.status == .needsReview)

        let afterSkill = try repository.setSkillStatus(id: "session-summary", status: .disabled)
        #expect(afterSkill.skills.first { $0.id == "session-summary" }?.status == .disabled)

        let reloaded = try repository.loadOrCreateDefault()
        #expect(reloaded.sources.first { $0.id == "mcp-source-registry" }?.status == .needsReview)
        #expect(reloaded.skills.first { $0.id == "session-summary" }?.status == .disabled)
    }
}
