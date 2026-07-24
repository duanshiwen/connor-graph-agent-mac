import CoreLocation
import AppKit
import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Observable
final class AppSettingsFeatureModel {
    var desktopNotificationsEnabled = true { didSet { changed() } }
    var sessionNewMessageNotificationLevel: SessionAttentionLevel = .actionable { didSet { changed() } }
    var keepScreenAwake = false { didSet { changed() } }
    var httpProxyEnabled = false { didSet { changed() } }
    var httpProxyURLString = "" { didSet { changed() } }
    var appearanceMode: ConnorAppearanceMode = .system { didSet { changed() } }
    var showProviderIcons = true { didSet { changed() } }
    var richToolDescriptionsEnabled = true { didSet { changed() } }
    var defaultSearchEngine: DefaultSearchEngine = .default { didSet { changed() } }
    @ObservationIgnored var onChanged: () -> Void = {}
    @ObservationIgnored private var isApplying = false

    func apply(_ settings: AgentRuntimeSettings) {
        isApplying = true
        defer { isApplying = false }
        desktopNotificationsEnabled = settings.app.desktopNotificationsEnabled
        sessionNewMessageNotificationLevel = settings.app.sessionNotificationSettings.newMessageLevel
        keepScreenAwake = settings.app.keepScreenAwake
        httpProxyEnabled = settings.app.httpProxyEnabled
        httpProxyURLString = settings.app.httpProxyURLString
        appearanceMode = ConnorAppearanceMode(rawValue: settings.appearance.mode) ?? .system
        showProviderIcons = settings.ui.showProviderIcons
        richToolDescriptionsEnabled = settings.ui.richToolDescriptionsEnabled
        defaultSearchEngine = settings.preferences.defaultSearchEngine
    }

    func apply(to settings: inout AgentRuntimeSettings) {
        settings.ui.showProviderIcons = showProviderIcons
        settings.ui.richToolDescriptionsEnabled = richToolDescriptionsEnabled
        settings.app.desktopNotificationsEnabled = desktopNotificationsEnabled
        settings.app.sessionNotificationSettings = SessionNotificationSettings(newMessageLevel: sessionNewMessageNotificationLevel)
        settings.app.keepScreenAwake = keepScreenAwake
        settings.app.httpProxyEnabled = httpProxyEnabled
        settings.app.httpProxyURLString = httpProxyURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.appearance.mode = appearanceMode.rawValue
        settings.preferences.defaultSearchEngine = defaultSearchEngine
    }

    func resetSessionNotificationSettings() {
        sessionNewMessageNotificationLevel = SessionNotificationSettings.default.newMessageLevel
    }

    private func changed() { if !isApplying { onChanged() } }
}

@MainActor
@Observable
final class InputSettingsFeatureModel {
    var composerSendShortcut = "return" { didSet { changed() } }
    var spellCheckEnabled = true { didSet { changed() } }
    var autoSaveDraftsEnabled = true { didSet { changed() } }
    var sessionSpeechTranscriptionEnabled = false
    var shortcutSettings = AgentRuntimeShortcutSettings()
    var recordingShortcutAction: AgentRuntimeShortcutAction?
    @ObservationIgnored var onSpeechTranscriptionDisabled: () -> Void = {}
    @ObservationIgnored var onChanged: () -> Void = {}
    @ObservationIgnored private var isApplying = false

    func apply(_ settings: AgentRuntimeSettings) {
        isApplying = true
        defer { isApplying = false }
        composerSendShortcut = settings.input.composerSendShortcut
        spellCheckEnabled = settings.input.spellCheckEnabled
        autoSaveDraftsEnabled = settings.input.autoSaveDraftsEnabled
        let wasEnabled = sessionSpeechTranscriptionEnabled
        sessionSpeechTranscriptionEnabled = settings.input.sessionSpeechTranscriptionEnabled
        shortcutSettings = settings.shortcuts
        if wasEnabled && !sessionSpeechTranscriptionEnabled { onSpeechTranscriptionDisabled() }
    }

    func apply(to settings: inout AgentRuntimeSettings) {
        settings.input.composerSendShortcut = composerSendShortcut
        settings.input.spellCheckEnabled = spellCheckEnabled
        settings.input.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        settings.input.sessionSpeechTranscriptionEnabled = sessionSpeechTranscriptionEnabled
        settings.shortcuts = shortcutSettings
    }

    func setSpeechTranscriptionEnabled(_ enabled: Bool) {
        let wasEnabled = sessionSpeechTranscriptionEnabled
        sessionSpeechTranscriptionEnabled = enabled
        if wasEnabled && !enabled { onSpeechTranscriptionDisabled() }
        onChanged()
    }

    func shortcut(for action: AgentRuntimeShortcutAction) -> AgentRuntimeKeyboardShortcut {
        shortcutSettings.shortcut(for: action)
    }

    func beginRecordingShortcut(for action: AgentRuntimeShortcutAction) { recordingShortcutAction = action }
    func updateShortcut(_ action: AgentRuntimeShortcutAction, shortcut: AgentRuntimeKeyboardShortcut) {
        shortcutSettings.bindings[action] = shortcut
        recordingShortcutAction = nil
        onChanged()
    }
    func resetShortcut(_ action: AgentRuntimeShortcutAction) {
        guard let value = AgentRuntimeShortcutSettings.defaultBindings[action] else { return }
        shortcutSettings.bindings[action] = value
        onChanged()
    }
    private func changed() { if !isApplying { onChanged() } }
}

@MainActor
@Observable
final class UserPreferencesFeatureModel {
    static let customGenderIdentitySelection = "__custom_gender_identity__"
    static let genderIdentityPresetValues: Set<String> = ["女性", "男性", "非二元", "性别流动", "无性别", "酷儿 / 性别酷儿", "不愿透露"]
    static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()

    var displayName = "" { didSet { changed() } }
    var timezone = "" { didSet { changed() } }
    var preferredLanguage = "" { didSet { changed() } }
    private(set) var genderIdentity = ""
    var genderIdentitySelection = ""
    var genderIdentityCustomText = ""
    var birthDate = "" { didSet { changed() } }
    var birthDatePickerDate = Date()
    var notes = "" { didSet { changed() } }
    private(set) var connorPersonality = ConnorPersonalitySettings.balancedDefault
    private(set) var connorPersonalityRevision = 0
    private(set) var connorVoiceGender: ConnorVoiceGender = .male
    private(set) var connorVoiceFollowsPersonalityGender = true
    private(set) var connorVoiceProfile: ConnorVoiceProfile?
    private(set) var connorVoiceRevision = 0
    var automaticallyReadsReplies = false { didSet { changed() } }
    var personalityRequest = ""
    private(set) var personalityDraft: ConnorPersonalitySettings?
    private(set) var isGeneratingPersonality = false
    private(set) var personalityErrorMessage: String?
    var voiceRequest = ""
    private(set) var voiceDraft: ConnorVoiceProfile?
    private(set) var isGeneratingVoice = false
    private(set) var voiceErrorMessage: String?
    private(set) var environmentLocationStatusMessage = "尚未检查定位权限。"

    @ObservationIgnored var onChanged: () -> Void = {}
    @ObservationIgnored var personalityGenerator: @MainActor (String) async throws -> ConnorPersonalitySettings = { _ in
        throw ConnorPersonalityError.unavailable
    }
    @ObservationIgnored var voiceGenerator: @MainActor (String, ConnorVoiceGender) async throws -> ConnorVoiceProfile = { _, _ in
        throw ConnorVoiceProfileError.unavailable
    }
    @ObservationIgnored private var isApplying = false

    var connorVoiceGenderSelection: ConnorVoiceGenderSelection {
        if connorVoiceFollowsPersonalityGender { return .followPersonality }
        return connorVoiceGender == .female ? .female : .male
    }

    var resolvedConnorVoiceGender: ConnorVoiceGender {
        connorVoiceFollowsPersonalityGender
            ? .following(personalityGender: connorPersonality.gender)
            : connorVoiceGender
    }

    func apply(_ preferences: AgentRuntimePreferenceSettings) {
        isApplying = true
        defer { isApplying = false }
        displayName = preferences.displayName
        timezone = preferences.timezone
        preferredLanguage = preferences.preferredLanguage
        applyLoadedGenderIdentity(preferences.genderIdentity)
        birthDate = preferences.birthDate
        if let date = Self.birthDateFormatter.date(from: preferences.birthDate) { birthDatePickerDate = date }
        notes = preferences.notes
        connorPersonality = preferences.connorPersonality
        connorPersonalityRevision = preferences.connorPersonalityRevision
        connorVoiceGender = preferences.connorSpeech.voiceGender
        connorVoiceFollowsPersonalityGender = preferences.connorSpeech.followsPersonalityGender
        connorVoiceProfile = preferences.connorSpeech.voiceProfile
        connorVoiceRevision = preferences.connorSpeech.voiceRevision
        automaticallyReadsReplies = preferences.connorSpeech.automaticallyReadsReplies
        personalityDraft = nil
        personalityErrorMessage = nil
        voiceDraft = nil
        voiceErrorMessage = nil
    }

    func apply(to settings: inout AgentRuntimeSettings) {
        settings.preferences.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.timezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.preferredLanguage = preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.genderIdentity = resolvedGenderIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.birthDate = birthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.connorPersonality = connorPersonality
        settings.preferences.connorPersonalityRevision = connorPersonalityRevision
        settings.preferences.connorSpeech = ConnorSpeechSettings(
            voiceGender: connorVoiceGender,
            followsPersonalityGender: connorVoiceFollowsPersonalityGender,
            voiceProfile: connorVoiceProfile,
            voiceRevision: connorVoiceRevision,
            automaticallyReadsReplies: automaticallyReadsReplies
        )
    }

    func fillEmptyFieldsFromSystem() -> Bool {
        let before = snapshotSignature
        let defaults = AgentRuntimePreferenceSystemDefaults.current()
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { displayName = defaults.displayName }
        if timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { timezone = defaults.timezone }
        if preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { preferredLanguage = defaults.preferredLanguage }
        return snapshotSignature != before
    }

    func setGenderIdentitySelection(_ selection: String) {
        genderIdentitySelection = selection
        if selection == Self.customGenderIdentitySelection { genderIdentity = genderIdentityCustomText }
        else { genderIdentityCustomText = ""; genderIdentity = selection }
        onChanged()
    }

    func setGenderIdentityCustomText(_ text: String) {
        genderIdentityCustomText = text
        if genderIdentitySelection == Self.customGenderIdentitySelection { genderIdentity = text }
        onChanged()
    }

    func setBirthDateFromPicker(_ date: Date) { birthDatePickerDate = date; birthDate = Self.birthDateFormatter.string(from: date); onChanged() }
    func clearBirthDate() { birthDate = ""; onChanged() }
    func refreshSystemDefaults() { _ = fillEmptyFieldsFromSystem(); onChanged() }

    func generatePersonalityDraft() async {
        guard !isGeneratingPersonality else { return }
        let request = personalityRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            personalityErrorMessage = ConnorPersonalityError.emptyRequest.localizedDescription
            return
        }
        isGeneratingPersonality = true
        personalityErrorMessage = nil
        defer { isGeneratingPersonality = false }
        do {
            personalityDraft = try await personalityGenerator(request)
        } catch {
            personalityDraft = nil
            personalityErrorMessage = error.localizedDescription
        }
    }

    func confirmPersonalityDraft() {
        guard let personalityDraft else { return }
        connorPersonality = personalityDraft
        connorPersonalityRevision += 1
        self.personalityDraft = nil
        personalityErrorMessage = nil
        onChanged()
    }

    func cancelPersonalityDraft() {
        personalityDraft = nil
        personalityErrorMessage = nil
    }

    func resetPersonality() {
        guard connorPersonality != .balancedDefault else { return }
        connorPersonality = .balancedDefault
        connorPersonalityRevision += 1
        personalityDraft = nil
        personalityErrorMessage = nil
        onChanged()
    }

    func generateVoiceDraft() async {
        guard !isGeneratingVoice else { return }
        let request = voiceRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            voiceErrorMessage = ConnorVoiceProfileError.emptyRequest.localizedDescription
            return
        }
        isGeneratingVoice = true
        voiceErrorMessage = nil
        defer { isGeneratingVoice = false }
        do {
            voiceDraft = try await voiceGenerator(request, resolvedConnorVoiceGender)
        } catch {
            voiceDraft = nil
            voiceErrorMessage = error.localizedDescription
        }
    }

    func confirmVoiceDraft() {
        guard let voiceDraft else { return }
        connorVoiceProfile = voiceDraft
        connorVoiceRevision += 1
        self.voiceDraft = nil
        voiceErrorMessage = nil
        onChanged()
    }

    func cancelVoiceDraft() {
        voiceDraft = nil
        voiceErrorMessage = nil
    }

    func resetVoiceToFollowPersonality() {
        guard connorVoiceProfile != nil else { return }
        connorVoiceProfile = nil
        connorVoiceRevision += 1
        voiceDraft = nil
        voiceErrorMessage = nil
        onChanged()
    }

    func setConnorVoiceGenderSelection(_ selection: ConnorVoiceGenderSelection) {
        switch selection {
        case .followPersonality:
            connorVoiceFollowsPersonalityGender = true
        case .male:
            connorVoiceFollowsPersonalityGender = false
            connorVoiceGender = .male
        case .female:
            connorVoiceFollowsPersonalityGender = false
            connorVoiceGender = .female
        }
        voiceDraft = nil
        voiceErrorMessage = nil
        changed()
    }

    func applyApprovedPersonality(_ personality: ConnorPersonalitySettings, expectedRevision: Int) throws {
        guard expectedRevision == connorPersonalityRevision else {
            throw ConnorPersonalityProposalError.revisionConflict(expected: expectedRevision, actual: connorPersonalityRevision)
        }
        connorPersonality = personality
        connorPersonalityRevision += 1
        personalityDraft = nil
        personalityErrorMessage = nil
        onChanged()
    }

    func restorePersonalityAfterFailedCommit(_ personality: ConnorPersonalitySettings, revision: Int) {
        connorPersonality = personality
        connorPersonalityRevision = revision
        onChanged()
    }

    func refreshEnvironmentPermissionStatus() {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            environmentLocationStatusMessage = "已允许。康纳会在每个用户请求回合获取一次当前位置。"
        case .notDetermined:
            environmentLocationStatusMessage = "尚未请求。首次发送消息时，macOS 会显示定位授权。"
        case .denied:
            environmentLocationStatusMessage = "已拒绝。环境快照会明确标记位置和天气不可用。"
        case .restricted:
            environmentLocationStatusMessage = "此 Mac 限制了定位访问。"
        @unknown default:
            environmentLocationStatusMessage = "无法确定定位权限状态。"
        }
    }

    func openLocationPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    func shutdown() {}

    private func changed() { if !isApplying { onChanged() } }
    private var resolvedGenderIdentity: String {
        genderIdentitySelection == Self.customGenderIdentitySelection ? genderIdentityCustomText : genderIdentitySelection
    }
    private var snapshotSignature: String { [displayName, timezone, preferredLanguage].joined(separator: "\u{1F}") }
    private func applyLoadedGenderIdentity(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines); genderIdentity = trimmed
        if trimmed.isEmpty { genderIdentitySelection = ""; genderIdentityCustomText = "" }
        else if Self.genderIdentityPresetValues.contains(trimmed) { genderIdentitySelection = trimmed; genderIdentityCustomText = "" }
        else { genderIdentitySelection = Self.customGenderIdentitySelection; genderIdentityCustomText = trimmed }
    }
}

enum ConnorVoiceGenderSelection: String, CaseIterable, Identifiable {
    case followPersonality
    case male
    case female

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .followPersonality: "跟随人格"
        case .male: "男声"
        case .female: "女声"
        }
    }
}

@MainActor
@Observable
final class WorkspaceSettingsFeatureModel {
    var defaultWorkingDirectoryPath = ""
    var roots: [WorkspaceRootDraft] = []
    var recentPaths: [String] = []
    var pathInput = ""
    @ObservationIgnored var onSaveSessionWorkspace: ([WorkspaceRootDraft], String) -> Void = { _, _ in }
    @ObservationIgnored var onChanged: () -> Void = {}

    var primaryRoot: WorkspaceRootDraft? { roots.first(where: \.isPrimary) ?? roots.first }
    func applyRecentPaths(_ values: [String]) { recentPaths = values }
    func applySessionState(_ state: AppSessionStateSnapshot?) {
        if let workspace = state?.workspace {
            roots = workspace.roots.map { WorkspaceRootDraft(id: $0.id, displayName: $0.displayName, path: $0.path, role: $0.role, isPrimary: $0.isPrimary) }
            defaultWorkingDirectoryPath = workspace.workingDirectoryPath
        } else { roots = []; defaultWorkingDirectoryPath = "" }
    }
    func addRoot(path: String, makePrimary: Bool = false) {
        guard AppWorkspaceRootDraftEditor.addRoot(path: path, to: &roots, makePrimary: makePrimary) else { pathInput = ""; return }
        defaultWorkingDirectoryPath = primaryRoot?.path ?? ""; pathInput = ""
        if makePrimary { rememberRecentPath(defaultWorkingDirectoryPath) }
        save()
    }
    func selectWorkingDirectory(path: String) {
        var selectedRoots: [WorkspaceRootDraft] = []
        guard AppWorkspaceRootDraftEditor.addRoot(path: path, to: &selectedRoots, makePrimary: true) else { return }
        roots = selectedRoots
        defaultWorkingDirectoryPath = primaryRoot?.path ?? ""
        rememberRecentPath(defaultWorkingDirectoryPath)
        save()
    }
    func addRoots(paths: [String]) { for path in paths { addRoot(path: path) } }
    func removeRoot(id: String) { AppWorkspaceRootDraftEditor.removeRoot(id: id, from: &roots); defaultWorkingDirectoryPath = primaryRoot?.path ?? ""; save() }
    func setPrimaryRoot(id: String) { AppWorkspaceRootDraftEditor.setPrimaryRoot(id: id, in: &roots); defaultWorkingDirectoryPath = primaryRoot?.path ?? ""; save() }
    func reset() { roots = []; defaultWorkingDirectoryPath = ""; pathInput = ""; save() }
    func rememberRecentPath(_ rawPath: String) {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        recentPaths.removeAll { $0 == path }; recentPaths.insert(path, at: 0)
        if recentPaths.count > 10 { recentPaths = Array(recentPaths.prefix(10)) }
        onChanged()
    }
    func clearRecentPaths() { recentPaths = []; onChanged() }
    private func save() { onSaveSessionWorkspace(roots, defaultWorkingDirectoryPath); onChanged() }
}

@MainActor
@Observable
final class PermissionSettingsFeatureModel {
    var defaultPermissionMode: AgentPermissionMode = .askToWrite { didSet { changed() } }
    var requireApprovalForNetwork = false { didSet { changed() } }
    var requireApprovalForShell = true { didSet { changed() } }
    @ObservationIgnored var onChanged: () -> Void = {}
    @ObservationIgnored private var isApplying = false
    func apply(_ settings: AgentRuntimeSettings) {
        isApplying = true
        defer { isApplying = false }
        defaultPermissionMode = settings.loop.permissionMode == .allowAll ? .askToWrite : settings.loop.permissionMode
        requireApprovalForNetwork = settings.permissions.requireApprovalForNetwork
        requireApprovalForShell = settings.permissions.requireApprovalForShell
    }
    func apply(to settings: inout AgentRuntimeSettings) {
        settings.loop.permissionMode = defaultPermissionMode == .allowAll ? .askToWrite : defaultPermissionMode
        settings.permissions.requireApprovalForNetwork = requireApprovalForNetwork
        settings.permissions.requireApprovalForShell = requireApprovalForShell
    }
    private func changed() { if !isApplying { onChanged() } }
}
