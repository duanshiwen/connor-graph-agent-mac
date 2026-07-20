import CoreLocation
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
    var city = "" { didSet { changed() } }
    var country = "" { didSet { changed() } }
    var notes = "" { didSet { changed() } }
    private(set) var locationStatusMessage: String?

    @ObservationIgnored private var locationCoordinator: UserLocationCoordinator?
    @ObservationIgnored var onChanged: () -> Void = {}
    @ObservationIgnored private var isApplying = false

    func apply(_ preferences: AgentRuntimePreferenceSettings) {
        isApplying = true
        defer { isApplying = false }
        displayName = preferences.displayName
        timezone = preferences.timezone
        preferredLanguage = preferences.preferredLanguage
        applyLoadedGenderIdentity(preferences.genderIdentity)
        birthDate = preferences.birthDate
        if let date = Self.birthDateFormatter.date(from: preferences.birthDate) { birthDatePickerDate = date }
        city = preferences.city
        country = preferences.country
        notes = preferences.notes
    }

    func apply(to settings: inout AgentRuntimeSettings) {
        settings.preferences.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.timezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.preferredLanguage = preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.genderIdentity = resolvedGenderIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.birthDate = birthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.preferences.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fillEmptyFieldsFromSystem() -> Bool {
        let before = snapshotSignature
        let defaults = AgentRuntimePreferenceSystemDefaults.current()
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { displayName = defaults.displayName }
        if timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { timezone = defaults.timezone }
        if preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { preferredLanguage = defaults.preferredLanguage }
        if country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { country = defaults.country }
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

    func requestLocation() {
        locationStatusMessage = "正在请求位置权限…"
        locationCoordinator = UserLocationCoordinator { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch result {
                    case .success(let placemark):
                        if let value = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea { self.city = value }
                        if let value = placemark.country { self.country = value }
                        self.locationStatusMessage = "位置已更新。"; self.onChanged()
                    case .failure(let error): self.locationStatusMessage = error.localizedDescription
                    }
                    self.locationCoordinator = nil
                }
            }
        }
        locationCoordinator?.requestLocation()
    }

    func shutdown() { locationCoordinator = nil }

    private func changed() { if !isApplying { onChanged() } }
    private var resolvedGenderIdentity: String {
        genderIdentitySelection == Self.customGenderIdentitySelection ? genderIdentityCustomText : genderIdentitySelection
    }
    private var snapshotSignature: String { [displayName, timezone, preferredLanguage, country].joined(separator: "\u{1F}") }
    private func applyLoadedGenderIdentity(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines); genderIdentity = trimmed
        if trimmed.isEmpty { genderIdentitySelection = ""; genderIdentityCustomText = "" }
        else if Self.genderIdentityPresetValues.contains(trimmed) { genderIdentitySelection = trimmed; genderIdentityCustomText = "" }
        else { genderIdentitySelection = Self.customGenderIdentitySelection; genderIdentityCustomText = trimmed }
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

private final class UserLocationCoordinator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager(); private let geocoder = CLGeocoder()
    private let completion: @Sendable (Result<CLPlacemark, Error>) -> Void
    init(completion: @escaping @Sendable (Result<CLPlacemark, Error>) -> Void) { self.completion = completion; super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers }
    func requestLocation() { switch manager.authorizationStatus { case .notDetermined: manager.requestWhenInUseAuthorization(); case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation(); default: completion(.failure(LocationPreferenceError.permissionDenied)) } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if manager.authorizationStatus == .authorizedAlways { manager.requestLocation() } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { completion(.failure(LocationPreferenceError.permissionDenied)) } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { guard let location = locations.last else { completion(.failure(LocationPreferenceError.locationUnavailable)); return }; geocoder.reverseGeocodeLocation(location) { [completion] placemarks, error in if let error { completion(.failure(error)) } else if let placemark = placemarks?.first { completion(.success(placemark)) } else { completion(.failure(LocationPreferenceError.locationUnavailable)) } } }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { completion(.failure(error)) }
}
private enum LocationPreferenceError: LocalizedError { case permissionDenied, locationUnavailable; var errorDescription: String? { switch self { case .permissionDenied: "定位权限未开启。请在系统设置中允许康纳同学访问位置，或手动填写城市和国家/地区。"; case .locationUnavailable: "暂时无法读取当前位置。你仍可以手动填写城市和国家/地区。" } } }
