import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class ContactsFeatureModel {
    enum Event {
        case operationSucceeded
        case operationFailed(String)
        case settingsMessageChanged(String?)
    }

    typealias SystemContactsLoader = @Sendable () async throws -> [ContactRecord]

    private(set) var presentation: NativeContactsBrowserPresentation = .empty
    private(set) var contactRecords: [ContactRecord] = []
    private(set) var profiles: [PersonProfile] = []
    private(set) var relationships: [PersonRelationship] = []
    var selectedContactID: ContactID?
    var editingRelationshipDraft: PersonRelationshipDraft?
    var isPresentingRelationshipEditor = false
    var isPresentingProfileEditor = false
    var editingProfileDraft: PersonProfileDraft?
    var pendingProfileDeletionID: ContactID?
    private(set) var isSyncingSystemContacts = false
    private(set) var syncMessage: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private let profileStore: (any PersonProfileStore)?
    @ObservationIgnored private let relationshipStore: (any PersonRelationshipStore)?
    @ObservationIgnored private let systemContactsLoader: SystemContactsLoader
    @ObservationIgnored private var reloadGeneration: UInt64 = 0
    @ObservationIgnored private var ownedTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(
        profileStore: (any PersonProfileStore)?,
        relationshipStore: (any PersonRelationshipStore)?,
        systemContactsLoader: @escaping SystemContactsLoader = {
            try await ContactsSystemAdapter.fetchSystemContacts()
        }
    ) {
        self.profileStore = profileStore
        self.relationshipStore = relationshipStore
        self.systemContactsLoader = systemContactsLoader
    }

    var agentProfileStore: (any PersonProfileStore)? { profileStore }

    func reload() async {
        guard !isShutdown else { return }
        reloadGeneration &+= 1
        let generation = reloadGeneration
        do {
            async let loadedProfiles = profileStore?.loadProfiles(includeInactive: false)
            async let loadedRelationships = relationshipStore?.loadRelationships(includeInactive: false)
            let (profiles, relationships) = try await (loadedProfiles, loadedRelationships)
            guard !Task.isCancelled, !isShutdown, generation == reloadGeneration else { return }
            if let profiles { self.profiles = profiles }
            if let relationships { self.relationships = relationships }
            rebuildPresentation()
            reportSuccess()
        } catch is CancellationError {
            return
        } catch {
            guard !isShutdown, generation == reloadGeneration else { return }
            reportFailure("无法加载联系人/邮件缓存：\(error.localizedDescription)")
        }
    }

    func reloadRelationships() async {
        guard !isShutdown else { return }
        do {
            relationships = try await relationshipStore?.loadRelationships(includeInactive: false) ?? relationships
            reportSuccess()
        } catch {
            reportFailure("无法加载人物关系：\(error.localizedDescription)")
        }
    }

    func relationships(for personID: ContactID) -> [PersonRelationship] {
        relationships.filter {
            $0.source.personID == personID || $0.target.personID == personID
        }
    }

    func currentUserRelationships() -> [PersonRelationship] {
        relationships.filter { $0.source.isCurrentUser || $0.target.isCurrentUser }
    }

    func displayTitle(for endpoint: PersonRelationshipEndpoint) -> String {
        if endpoint.isCurrentUser { return "我（当前用户）" }
        guard let personID = endpoint.personID else { return endpoint.fallbackDisplayTitle }
        if let profile = profiles.first(where: { $0.id == personID }) {
            return profile.displayName
        }
        return "未知人物（\(personID.rawValue)）"
    }

    func presentNewRelationshipEditor(sourcePersonID: ContactID) {
        editingRelationshipDraft = PersonRelationshipDraft(sourcePersonID: sourcePersonID)
        isPresentingRelationshipEditor = true
    }

    func saveRelationshipDraft(_ draft: PersonRelationshipDraft) async {
        do {
            let relationship = try draft.makeRelationship(now: Date())
            guard await saveRelationship(relationship) else { return }
            editingRelationshipDraft = nil
            isPresentingRelationshipEditor = false
        } catch PersonRelationshipDraftError.missingTargetPerson {
            reportFailure("请选择关系目标人物")
        } catch PersonRelationshipDraftError.selfRelationship {
            reportFailure("不能将人物关系指向自己")
        } catch {
            reportFailure("无法保存人物关系：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func saveRelationship(_ relationship: PersonRelationship) async -> Bool {
        do {
            _ = try await relationshipStore?.upsert(relationship)
            relationships = try await relationshipStore?.loadRelationships(includeInactive: false)
                ?? relationships.upserting(relationship)
            reportSuccess()
            return true
        } catch {
            reportFailure("无法保存人物关系：\(error.localizedDescription)")
            return false
        }
    }

    func deleteRelationship(_ id: String) async {
        do {
            try await relationshipStore?.markDeleted(id: id, now: Date())
            relationships = try await relationshipStore?.loadRelationships(includeInactive: false)
                ?? relationships.filter { $0.id != id }
            reportSuccess()
        } catch {
            reportFailure("无法删除人物关系：\(error.localizedDescription)")
        }
    }

    func presentNewProfileEditor() {
        editingProfileDraft = PersonProfileDraft(displayName: "")
        isPresentingProfileEditor = true
    }

    func presentEditProfile(_ id: ContactID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        editingProfileDraft = PersonProfileDraft(profile: profile)
        isPresentingProfileEditor = true
    }

    func saveProfileDraft(_ draft: PersonProfileDraft) async {
        do {
            let displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else {
                reportFailure("人物名称不能为空")
                return
            }
            let existing = draft.id.flatMap { id in profiles.first(where: { $0.id == id }) }
            let profile = draft.makeProfile(existing: existing, now: Date())
            _ = try await profileStore?.upsert(profile)
            profiles = try await profileStore?.loadProfiles(includeInactive: false) ?? profiles.upserting(profile)
            rebuildPresentation()
            selectedContactID = profile.id
            editingProfileDraft = nil
            isPresentingProfileEditor = false
            reportSuccess()
        } catch {
            reportFailure("无法保存人物档案：\(error.localizedDescription)")
        }
    }

    func deleteProfile(_ id: ContactID) async {
        do {
            try await profileStore?.markDeleted(id: id, now: Date())
            profiles = try await profileStore?.loadProfiles(includeInactive: false) ?? profiles.filter { $0.id != id }
            if selectedContactID == id { selectedContactID = profiles.first?.id }
            rebuildPresentation()
            pendingProfileDeletionID = nil
            reportSuccess()
        } catch {
            reportFailure("无法删除人物档案：\(error.localizedDescription)")
        }
    }

    func mergeProfile(sourceID: ContactID, targetID: ContactID) async {
        do {
            let now = Date()
            _ = try await profileStore?.merge(sourceID: sourceID, targetID: targetID, now: now)
            try await relationshipStore?.reassignPersonIDForMerge(sourceID: sourceID, targetID: targetID, now: now)
            profiles = try await profileStore?.loadProfiles(includeInactive: false) ?? profiles.filter { $0.id != sourceID }
            relationships = try await relationshipStore?.loadRelationships(includeInactive: false) ?? relationships
            selectedContactID = targetID
            rebuildPresentation()
            reportSuccess()
        } catch {
            reportFailure("无法合并人物档案：\(error.localizedDescription)")
        }
    }

    func syncSystemContacts() {
        guard !isShutdown, !isSyncingSystemContacts else { return }
        isSyncingSystemContacts = true
        syncMessage = "正在请求通讯录权限并同步…"
        startOwnedTask { [weak self] in
            await self?.syncSystemContactsNow()
        }
    }

    @discardableResult
    func syncSystemContactsNow() async -> Bool {
        guard !isShutdown else { return false }
        let ownsLoadingState = !isSyncingSystemContacts
        if ownsLoadingState {
            isSyncingSystemContacts = true
            syncMessage = "正在请求通讯录权限并同步…"
        }
        defer { isSyncingSystemContacts = false }
        do {
            let records = try await systemContactsLoader()
            guard !Task.isCancelled, !isShutdown else { return false }
            profiles = records.map { PersonProfile(contactRecord: $0) }
            rebuildPresentation()
            await persistProfilesPreservingLegacySemantics()
            guard !Task.isCancelled, !isShutdown else { return false }
            syncMessage = "已同步系统通讯录：\(records.count) 个人物档案"
            onEvent?(.settingsMessageChanged(syncMessage))
            reportSuccess()
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !isShutdown else { return false }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            syncMessage = message
            onEvent?(.settingsMessageChanged(message))
            reportFailure(message)
            return false
        }
    }

    func waitForPendingOperations() async {
        while !ownedTasks.isEmpty {
            for task in Array(ownedTasks.values) { await task.value }
        }
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        reloadGeneration &+= 1
        for task in ownedTasks.values { task.cancel() }
        ownedTasks.removeAll()
    }

    private func persistProfilesPreservingLegacySemantics() async {
        do {
            for profile in profiles { _ = try await profileStore?.upsert(profile) }
        } catch {
            reportFailure("无法保存人物档案：\(error.localizedDescription)")
        }
    }

    private func rebuildPresentation() {
        presentation = NativeContactsBrowserPresentation.build(profiles: profiles)
        contactRecords = profiles.map(\.contactRecord)
        if let selectedContactID,
           !profiles.contains(where: { $0.id == selectedContactID && $0.isActiveForDefaultContext }) {
            self.selectedContactID = nil
        }
    }

    private func startOwnedTask(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        ownedTasks[id] = Task { @MainActor [weak self] in
            await operation()
            self?.ownedTasks[id] = nil
        }
    }

    private func reportSuccess() {
        errorMessage = nil
        onEvent?(.operationSucceeded)
    }

    private func reportFailure(_ message: String) {
        errorMessage = message
        onEvent?(.operationFailed(message))
    }
}
