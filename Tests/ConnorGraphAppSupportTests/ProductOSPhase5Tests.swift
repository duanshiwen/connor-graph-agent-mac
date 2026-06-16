import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Product OS Phase 5 Tests")
struct ProductOSPhase5Tests {
    @Test func automationRepositorySeedsRulesAndMirrorsLabelsStatuses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let governance = AppSessionGovernanceConfig.default
        let repository = AppProductOSAutomationRepository(storagePaths: paths)

        let config = try repository.loadOrCreateDefault(governanceConfig: governance)

        #expect(config.schemaVersion == 1)
        #expect(config.rules.contains { $0.id == "important-label-adds-review-note" })
        #expect(FileManager.default.fileExists(atPath: repository.automationConfigURL.path))
        #expect(FileManager.default.fileExists(atPath: repository.statusesMirrorURL.path))
        #expect(FileManager.default.fileExists(atPath: repository.labelsMirrorURL.path))
        #expect(paths.automationsDirectory.path.contains("workspace") == false)
        #expect(paths.statusesDirectory.path.contains("workspace") == false)
        #expect(paths.labelsDirectory.path.contains("workspace") == false)
    }

    @Test func automationRepositoryRejectsDuplicateIDsAndUnsafeActions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSAutomationRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))

        var duplicate = ProductOSAutomationConfig.default
        duplicate.rules.append(duplicate.rules[0])
        #expect(throws: AppProductOSAutomationError.self) {
            try repository.save(duplicate)
        }

        var missingStatus = ProductOSAutomationConfig.default
        missingStatus.rules[0].actions = [ProductOSAutomationAction(kind: .setSessionStatus, message: "missing status")]
        #expect(throws: AppProductOSAutomationError.self) {
            try repository.save(missingStatus)
        }

        var unsafeArchive = ProductOSAutomationConfig.default
        unsafeArchive.rules[0].actions = [ProductOSAutomationAction(kind: .setSessionStatus, status: .archived, message: "archive automatically")]
        #expect(throws: AppProductOSAutomationError.self) {
            try repository.save(unsafeArchive)
        }
    }

    @Test func automationRepositoryMatchesStatusAndLabelTriggersAndPersistsTriggerLog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSAutomationRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))

        let statusRecords = try repository.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionStatusChanged,
            sessionID: "session-1",
            status: .needsReview
        ))
        #expect(statusRecords.isEmpty)

        let labelRecords = try repository.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionLabelAdded,
            sessionID: "session-1",
            labelID: "important"
        ))
        #expect(labelRecords.map(\.ruleID).contains("important-label-adds-review-note"))

        let noMatch = try repository.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionStatusChanged,
            sessionID: "session-1",
            status: .done
        ))
        #expect(noMatch.isEmpty)

        let recent = try repository.loadRecentTriggerRecords()
        #expect(recent.count == 1)
        #expect(recent.allSatisfy { $0.sessionID == "session-1" })
    }
}
