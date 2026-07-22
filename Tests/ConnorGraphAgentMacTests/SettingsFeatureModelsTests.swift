import Foundation
import Testing
@testable import ConnorGraphAgentMac
import ConnorGraphAgent
import ConnorGraphAppSupport

@MainActor
@Suite("Settings Feature Models Tests")
struct SettingsFeatureModelsTests {
    @Test func appSettingsRoundTripOnlyOwnedFields() {
        var settings = AgentRuntimeSettings.default
        settings.loop.maxConsecutiveToolResultErrors = 0
        let model = AppSettingsFeatureModel()
        model.apply(settings)
        model.defaultSearchEngine = .google
        model.desktopNotificationsEnabled = false
        model.apply(to: &settings)
        #expect(settings.preferences.defaultSearchEngine == .google)
        #expect(!settings.app.desktopNotificationsEnabled)
        #expect(settings.loop.maxConsecutiveToolResultErrors == 0)
    }

    @Test func directBoundFieldsEmitChangeOutsideApply() {
        let model = InputSettingsFeatureModel()
        var changes = 0
        model.onChanged = { changes += 1 }
        model.apply(.default)
        #expect(changes == 0)
        model.spellCheckEnabled = false
        #expect(changes == 1)
    }

    @Test func userPreferencesPreserveCustomGenderAndBirthDate() {
        let model = UserPreferencesFeatureModel()
        model.apply(AgentRuntimePreferenceSettings(genderIdentity: "自我描述", birthDate: "1990-01-02"))
        #expect(model.genderIdentitySelection == UserPreferencesFeatureModel.customGenderIdentitySelection)
        #expect(model.genderIdentityCustomText == "自我描述")
        var settings = AgentRuntimeSettings.default
        model.apply(to: &settings)
        #expect(settings.preferences.genderIdentity == "自我描述")
        #expect(settings.preferences.birthDate == "1990-01-02")
    }

    @Test func personalityGenerationRequiresConfirmationBeforeSaving() async {
        let model = UserPreferencesFeatureModel()
        let generated = ConnorPersonalitySettings(summary: "冷静、直接", traits: ["严谨"])
        var changes = 0
        model.onChanged = { changes += 1 }
        model.personalityGenerator = { _ in generated }
        model.personalityRequest = "希望更冷静严谨"

        await model.generatePersonalityDraft()

        #expect(model.personalityDraft == generated)
        #expect(model.connorPersonality.isEmpty)
        #expect(changes == 0)

        model.confirmPersonalityDraft()
        #expect(model.connorPersonality == generated)
        #expect(model.personalityDraft == nil)
        #expect(changes == 1)

        var settings = AgentRuntimeSettings.default
        model.apply(to: &settings)
        #expect(settings.preferences.connorPersonality == generated)
    }

    @Test func cancelAndFailedGenerationDoNotChangeSavedPersonality() async {
        let saved = ConnorPersonalitySettings(summary: "温和可靠")
        let model = UserPreferencesFeatureModel()
        model.apply(AgentRuntimePreferenceSettings(connorPersonality: saved))
        model.personalityGenerator = { _ in throw ConnorPersonalityError.invalidJSON }
        model.personalityRequest = "换一种风格"

        await model.generatePersonalityDraft()

        #expect(model.connorPersonality == saved)
        #expect(model.personalityDraft == nil)
        #expect(model.personalityErrorMessage != nil)
        model.cancelPersonalityDraft()
        #expect(model.connorPersonality == saved)
    }

    @Test func resetPersonalityTriggersPersistenceChange() {
        let model = UserPreferencesFeatureModel()
        model.apply(AgentRuntimePreferenceSettings(
            connorPersonality: ConnorPersonalitySettings(summary: "积极主动")
        ))
        var changes = 0
        model.onChanged = { changes += 1 }

        model.resetPersonality()

        #expect(model.connorPersonality.isEmpty)
        #expect(changes == 1)
    }

    @Test func workspaceMutationsEmitImmutableSnapshotValues() {
        let model = WorkspaceSettingsFeatureModel()
        var savedRoots: [WorkspaceRootDraft] = []
        var savedPath = ""
        model.onSaveSessionWorkspace = { roots, path in savedRoots = roots; savedPath = path }
        model.addRoot(path: "/tmp/project", makePrimary: true)
        #expect(savedRoots.count == 1)
        #expect(savedPath == "/tmp/project")
        #expect(model.recentPaths == ["/tmp/project"])
    }

    @Test func selectingWorkingDirectoryReplacesPreviousWorkspaceAuthorization() {
        let model = WorkspaceSettingsFeatureModel()
        var savedRoots: [WorkspaceRootDraft] = []
        model.onSaveSessionWorkspace = { roots, _ in savedRoots = roots }
        model.addRoot(path: "/tmp/old-project", makePrimary: true)

        model.selectWorkingDirectory(path: "/tmp/new-project")

        #expect(model.roots.map(\.path) == ["/tmp/new-project"])
        #expect(model.defaultWorkingDirectoryPath == "/tmp/new-project")
        #expect(savedRoots.map(\.path) == ["/tmp/new-project"])
        #expect(model.recentPaths == ["/tmp/new-project", "/tmp/old-project"])
    }

    @Test func persistenceCoordinatorPreservesFullLoopConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-coordinator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppRuntimeSettingsRepository(configDirectory: root)
        var initial = AgentRuntimeSettings.default
        initial.loop.maxToolIterations = 77
        initial.loop.maxConsecutiveToolResultErrors = 0
        try repository.save(initial)
        let coordinator = RuntimeSettingsPersistenceCoordinator(repository: repository)
        let loaded = try #require(coordinator.load())
        var next = coordinator.baseSnapshot()
        next.app.keepScreenAwake = true
        coordinator.save(snapshot: next)
        let persisted = try repository.loadOrCreateDefault()
        #expect(loaded.loop.maxToolIterations == 77)
        #expect(persisted.loop.maxToolIterations == 77)
        #expect(persisted.loop.maxConsecutiveToolResultErrors == 0)
        #expect(persisted.app.keepScreenAwake)
        coordinator.shutdown()
    }
}
