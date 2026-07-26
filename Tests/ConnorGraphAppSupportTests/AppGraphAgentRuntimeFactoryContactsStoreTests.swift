import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class FactoryContactsSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class FactoryContactsCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values["\(service):\(account)"] = nil }
}

@Test func agentRuntimeFactoryUsesInjectedPersonProfileStore() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-contacts-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
    try storagePaths.ensureDirectoryHierarchy()
    let graphStore = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
    try graphStore.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: FactoryContactsSettingsStore(),
        credentialStore: FactoryContactsCredentialStore()
    )
    let injectedStore = try SQLitePersonProfileStore(databaseURL: root.appendingPathComponent("injected-people.sqlite"))
    _ = try await injectedStore.upsert(PersonProfile(
        id: ContactID(rawValue: "injected-person"),
        displayName: "Injected Person"
    ))
    let factory = AppGraphAgentRuntimeFactory(
        store: graphStore,
        settingsRepository: settings,
        storagePaths: storagePaths,
        personProfileStore: injectedStore
    )
    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)

    let result = try await controller.toolRegistry.execute(
        AgentToolCall(name: "contacts_read", argumentsJSON: #"{"operation":"list_people"}"#),
        context: AgentToolExecutionContext(
            runID: "contacts-store-run",
            sessionID: "contacts-store-session",
            groupID: "default",
            userPrompt: "list people",
            toolCallID: "contacts-read",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    #expect(result.contentJSON?.contains("injected-person") == true)
    #expect(result.contentJSON?.contains("Injected Person") == true)
    let fallbackURL = storagePaths.applicationSupportDirectory
        .appendingPathComponent("contacts", isDirectory: true)
        .appendingPathComponent("person-profiles.sqlite")
    let fallbackStore = try SQLitePersonProfileStore(databaseURL: fallbackURL)
    #expect(try await fallbackStore.loadProfiles(includeInactive: false).isEmpty)
}

@Test func contactsReadRecoversPhotosStoredOnDiskWithoutProfilePaths() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-recover-person-images-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
    try storagePaths.ensureDirectoryHierarchy()
    let graphStore = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
    try graphStore.migrate()
    let profileStore = try SQLitePersonProfileStore(databaseURL: root.appendingPathComponent("people.sqlite"))
    let personID = ContactID(rawValue: "person-recovered-images")
    _ = try await profileStore.upsert(PersonProfile(id: personID, displayName: "恢复图片的人"))
    let sourceURL = root.appendingPathComponent("recovered.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
    let recoveredPath = try PersonProfileImageStore(storagePaths: storagePaths).importImage(at: sourceURL, personID: personID)
    let factory = AppGraphAgentRuntimeFactory(
        store: graphStore,
        settingsRepository: AppLLMSettingsRepository(
            settingsStore: FactoryContactsSettingsStore(),
            credentialStore: FactoryContactsCredentialStore()
        ),
        storagePaths: storagePaths,
        personProfileStore: profileStore
    )
    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)

    let result = try await controller.toolRegistry.execute(
        AgentToolCall(name: "contacts_read", argumentsJSON: "{\"operation\":\"get_person\",\"personID\":\"\(personID.rawValue)\"}"),
        context: AgentToolExecutionContext(
            runID: "recover-person-images-run",
            sessionID: "recover-person-images-session",
            groupID: "default",
            userPrompt: "读取人物图片",
            toolCallID: "recover-person-images-read",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    let data = try #require(result.contentJSON?.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["photos"] as? [String] == [recoveredPath])
}

@Test func approvedPersonRegistryWritesBecomeGovernedMemoryEvidence() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-contacts-memory-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
    try storagePaths.ensureDirectoryHierarchy()
    let graphStore = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
    try graphStore.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: FactoryContactsSettingsStore(),
        credentialStore: FactoryContactsCredentialStore()
    )
    let profileStore = try SQLitePersonProfileStore(databaseURL: root.appendingPathComponent("injected-people.sqlite"))
    let factory = AppGraphAgentRuntimeFactory(
        store: graphStore,
        settingsRepository: settings,
        storagePaths: storagePaths,
        personProfileStore: profileStore
    )
    let controller = factory.makeAgentLoopController(permissionMode: .allowAll)

    _ = try await controller.toolRegistry.execute(
        AgentToolCall(
            name: "contacts_write",
            argumentsJSON: #"{"operation":"create_person","name":"Annie","email":"annie@example.com","organization":"Consulting","jobTitle":"Consultant","notes":"A friend invited to try Connor.","approved":true}"#
        ),
        context: AgentToolExecutionContext(
            runID: "contacts-memory-run",
            sessionID: "contacts-memory-session",
            groupID: "default",
            userPrompt: "remember Annie",
            toolCallID: "contacts-memory-write",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll),
            approvedCapabilities: [.mutateContacts]
        )
    )

    let memoryStore = try SQLiteMemoryOSStore(path: storagePaths.memoryOSDatabaseURL.path)
    let hits = try SQLiteMemoryOSUnifiedRetrievalService(store: memoryStore).search(
        MemoryOSRetrievalQuery(text: "Annie 朋友 friend", layers: [.l1], limit: 10)
    )

    #expect(hits.contains { hit in
        hit.metadata["person_registry_operation"] == "create" &&
        hit.matchedText.contains("Display name: Annie") &&
        !hit.matchedText.contains("annie@example.com")
    })
}

@Test func conversationCanSetOptionalPersonImageFromCurrentAttachment() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-person-image-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
    try storagePaths.ensureDirectoryHierarchy()
    let graphStore = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
    try graphStore.migrate()
    let profileStore = try SQLitePersonProfileStore(databaseURL: root.appendingPathComponent("people.sqlite"))
    let personID = ContactID(rawValue: "person-with-image")
    _ = try await profileStore.upsert(PersonProfile(id: personID, displayName: "图片人物"))

    let firstSourceURL = root.appendingPathComponent("portrait-1.png")
    let secondSourceURL = root.appendingPathComponent("portrait-2.jpg")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: firstSourceURL)
    try Data([0xFF, 0xD8, 0xFF]).write(to: secondSourceURL)
    let sessionID = "person-image-session"
    let attachmentStore = AppSessionAttachmentStore(paths: storagePaths)
    let firstAttachment = try attachmentStore.importFile(at: firstSourceURL, sessionID: sessionID)
    let secondAttachment = try attachmentStore.importFile(at: secondSourceURL, sessionID: sessionID)
    let factory = AppGraphAgentRuntimeFactory(
        store: graphStore,
        settingsRepository: AppLLMSettingsRepository(
            settingsStore: FactoryContactsSettingsStore(),
            credentialStore: FactoryContactsCredentialStore()
        ),
        storagePaths: storagePaths,
        personProfileStore: profileStore
    )
    let controller = factory.makeAgentLoopController(permissionMode: .allowAll)

    let result = try await controller.toolRegistry.execute(
        AgentToolCall(
            name: "contacts_write",
            argumentsJSON: "{\"operation\":\"add_person_images\",\"personID\":\"\(personID.rawValue)\",\"attachmentIDs\":[\"\(firstAttachment.id)\",\"\(secondAttachment.id)\"],\"approved\":true}"
        ),
        context: AgentToolExecutionContext(
            runID: "person-image-run",
            sessionID: sessionID,
            groupID: "default",
            userPrompt: "把我上传的图片设置成这个人的头像",
            toolCallID: "person-image-write",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll),
            approvedCapabilities: [.mutateContacts]
        )
    )

    let updated = try #require(try await profileStore.profile(id: personID))
    let imageStore = PersonProfileImageStore(storagePaths: storagePaths)
    let storedURLs = (updated.imageRelativePaths ?? []).compactMap { imageStore.imageURL(for: $0) }
    #expect(result.contentText.contains("Added 2 image(s) for person"))
    #expect(storedURLs.count == 2)
    #expect(storedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    #expect(storedURLs.allSatisfy { $0.deletingLastPathComponent().lastPathComponent == personID.rawValue })
}
