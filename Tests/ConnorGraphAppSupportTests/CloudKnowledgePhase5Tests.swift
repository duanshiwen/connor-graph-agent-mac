import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Cloud Knowledge Phase 5 Tests")
struct CloudKnowledgePhase5Tests {
    @Test @MainActor func creatorWorkflowPersistsAndRestoresSelectedConversationsAndProgress() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-creator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CloudKnowledgeCreatorSnapshotRepository(fileURL: root.appendingPathComponent("snapshot.json"))
        let store = CloudKnowledgeCreatorStore(repository: repository)
        store.updateDraft(.init(name: "Connor 知识", slug: "connor", description: "desc"))
        store.advance(to: .conversations); store.toggleConversation("local-session-1"); store.toggleConversation("local-session-2"); store.advance(to: .generating)
        store.noteProcessed(conversationID: "local-session-1", summary: "检索并 staged L3 知识")
        store.pause()

        let restored = CloudKnowledgeCreatorStore(repository: repository)
        #expect(restored.snapshot.stage == .paused)
        #expect(restored.snapshot.selectedConversationIDs == ["local-session-1", "local-session-2"])
        #expect(restored.snapshot.processedConversationIDs == ["local-session-1"])
        #expect(restored.snapshot.summaries == ["检索并 staged L3 知识"])
        #expect(restored.snapshot.draft.name == "Connor 知识")
    }

    @Test @MainActor func creatorWorkflowRestoresValidationPreviewConflictAndCancelStates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-creator-state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CloudKnowledgeCreatorSnapshotRepository(fileURL: root.appendingPathComponent("snapshot.json"))
        let store = CloudKnowledgeCreatorStore(repository: repository)
        store.applyValidation(.init(valid: false, issues: [.init(code: "missing_alias", message: "缺少别名", repairable: true)], stagedSequence: 2))
        #expect(store.snapshot.stage == .validating)
        store.setPreview(.init(runID: "run", stagedSequence: 2, operations: [], summaries: ["新增 L4 实体 Connor"]))
        #expect(store.snapshot.stage == .preview)
        store.markConflict(); #expect(store.snapshot.stage == .conflict)
        store.cancel(); #expect(store.snapshot.stage == .cancelled)
        #expect(CloudKnowledgeCreatorStore(repository: repository).snapshot.stage == .cancelled)
    }

    @Test func creatorApiRoutesMatchBackendContract() async throws {
        let transport = CloudKnowledgeCreatorAPITransportRecorder()
        let api = CloudKnowledgeCreatorAPIClient(baseURL: URL(string: "http://localhost:8080")!, transport: transport, credentials: StaticCloudKnowledgeCredentialProvider(token: "token"))
        let publishKey = UUID()
        let unpublishKey = UUID()
        _ = try await api.publishKnowledgeBase(id: "kb-1", request: .init(expectedGovernanceVersion: 6, idempotencyKey: publishKey, termsAccepted: true))
        _ = try await api.unpublishKnowledgeBase(id: "kb-1", request: .init(expectedGovernanceVersion: 7, idempotencyKey: unpublishKey))
        _ = try await api.appealKnowledgeBase(id: "kb-1", statement: "test appeal", governanceActionID: "ga-1")
        #expect(transport.requests.map(\.path) == ["/api/v2/knowledge-bases/kb-1/publish", "/api/v2/knowledge-bases/kb-1/publish", "/api/v2/knowledge-bases/kb-1/appeals"])
        #expect(transport.requests.map(\.method) == ["POST", "DELETE", "POST"])
        #expect(transport.requests.allSatisfy { $0.path.hasPrefix("/api/v2/") })
        let publishBody = transport.requests[0].bodyObject as? [String: Any]
        #expect(publishBody?["expected_governance_version"] as? Int == 6)
        #expect(publishBody?["idempotency_key"] as? String == publishKey.uuidString)
        #expect(publishBody?["terms_version"] as? String == cloudKnowledgeCreatorTermsVersion)
        #expect(publishBody?["terms_accepted"] as? Bool == true)
        let unpublishBody = transport.requests[1].bodyObject as? [String: Any]
        #expect(unpublishBody?["expected_governance_version"] as? Int == 7)
        #expect(unpublishBody?["idempotency_key"] as? String == unpublishKey.uuidString)
        let appealBody = transport.requests.last?.bodyObject as? [String: Any]
        #expect(appealBody?["statement"] as? String == "test appeal")
        #expect(appealBody?["governance_action_id"] as? String == "ga-1")
        #expect(appealBody?.keys.sorted() == ["governance_action_id", "statement"])
    }

    @Test func creatorApiMapsCanonicalSnakeCaseErrors() async throws {
        let transport = CloudKnowledgeCreatorAPIErrorTransport()
        let api = CloudKnowledgeCreatorAPIClient(baseURL: URL(string: "http://localhost:8080")!, transport: transport, credentials: StaticCloudKnowledgeCredentialProvider(token: "token"))
        await #expect(throws: CloudKnowledgeError.takenDown) { try await api.publishKnowledgeBase(id: "kb-1", request: .init(expectedGovernanceVersion: 1, termsAccepted: true)) }
        await #expect(throws: CloudKnowledgeError.deleting) { try await api.unpublishKnowledgeBase(id: "kb-1", request: .init(expectedGovernanceVersion: 1)) }
        await #expect(throws: CloudKnowledgeError.deleted) { try await api.appealKnowledgeBase(id: "kb-1", statement: "test appeal", governanceActionID: "ga-1") }
    }

    @Test func detailGovernanceStatesPersistAndDecode() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = #"{"id":"kb-1","name":"Connor","slug":"connor","visibility":"public","current_sequence":10,"lifecycle_status":"active","publication_status":"published","enforcement_status":"taken_down","governance_version":3,"latest_takedown_action_id":"ga-1","appeal_count":2}"#
        let detail = try decoder.decode(CloudKnowledgeBaseDetail.self, from: Data(json.utf8))
        #expect(detail.publicationStatus == "published")
        #expect(detail.enforcementStatus == "taken_down")
        #expect(detail.governanceVersion == 3)
        #expect(detail.latestTakedownActionID == "ga-1")
        #expect(detail.appealCount == 2)
        let encoded = try encoder.encode(detail)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["enforcement_status"] as? String == "taken_down")
        #expect(object["governance_version"] as? Int == 3)
    }

    @Test @MainActor func latestDetailPersistsAndRefreshesThreeAxisGovernanceState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-detail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CloudKnowledgeCreatorSnapshotRepository(fileURL: root.appendingPathComponent("snapshot.json"))
        let api = DetailTrackingCreatorAPI()
        let store = CloudKnowledgeCreatorStore(repository: repository, creatorAPI: api)
        store.updateDraft(.init(name: "Connor", slug: "connor", description: "desc"))
        await store.saveKnowledgeBase()
        #expect(store.currentPublicationStatusLabel == "unpublished")
        #expect(store.currentEnforcementStatusLabel == "clear")
        #expect(store.currentGovernanceVersion == 1)
        await store.publishKnowledgeBase(termsAccepted: true)
        #expect(store.currentPublicationStatusLabel == "published")
        #expect(store.currentGovernanceVersion == 2)
        await store.unpublishKnowledgeBase()
        #expect(store.currentPublicationStatusLabel == "unpublished")
        #expect(store.currentGovernanceVersion == 3)
        await store.refreshLatestKnowledgeBaseDetail()
        #expect(store.currentEnforcementStatusLabel == "taken_down")
        #expect(store.currentGovernanceVersion == 4)
        let restored = CloudKnowledgeCreatorStore(repository: repository, creatorAPI: api)
        #expect(restored.snapshot.latestKnowledgeBaseDetail?.enforcementStatus == "taken_down")
        #expect(restored.snapshot.latestKnowledgeBaseDetail?.governanceVersion == 4)
    }

    @Test @MainActor func generationTaskPausesCheckpointsAndResumesOnlyRemainingLocalConversations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-generation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudKnowledgeCreatorStore(repository: .init(fileURL: root.appendingPathComponent("snapshot.json")))
        store.toggleConversation("one"); store.toggleConversation("two"); store.toggleConversation("three")
        let recorder = LocalGenerationRecorder()
        store.startGeneration { id in try await recorder.process(id) }
        for _ in 0..<100 where store.snapshot.processedConversationIDs.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        store.pause()
        let checkpoint = store.snapshot.processedConversationIDs.count
        #expect(checkpoint >= 1 && checkpoint < 3)
        store.resume()
        await store.waitForGenerationCompletion()
        #expect(store.snapshot.processedConversationIDs == ["one", "two", "three"])
        #expect(await recorder.ids == ["one", "two", "three"])
    }

    @Test @MainActor func conflictRecoveryRebasesAndCommitUsesPublicationAPI() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-conflict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let publication = CreatorPublicationFakeAPI()
        let store = CloudKnowledgeCreatorStore(repository: .init(fileURL: root.appendingPathComponent("snapshot.json")), publicationAPI: publication)
        store.attachRun(id: "run"); store.markConflict()
        await store.recoverConflict { _ in 9 }
        #expect(await publication.rebasedSequence == 9)
        await store.commitPublication()
        #expect(await publication.commitCount == 1)
        #expect(store.snapshot.stage == .completed)
    }

    @Test @MainActor func resetRemovesPersistedWorkflowWithoutTouchingMemoryOS() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-creator-reset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("snapshot.json")
        let repository = CloudKnowledgeCreatorSnapshotRepository(fileURL: file)
        let store = CloudKnowledgeCreatorStore(repository: repository)
        store.toggleConversation("local-only-id")
        #expect(FileManager.default.fileExists(atPath: file.path))
        store.reset()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.snapshot.selectedConversationIDs.isEmpty)
    }

}

private actor LocalGenerationRecorder {
    var ids: [String] = []
    func process(_ id: String) async throws -> CloudKnowledgeLocalGenerationResult { try await Task.sleep(nanoseconds: 60_000_000); try Task.checkCancellation(); ids.append(id); return .init(summary: id) }
}

private struct StaticCloudKnowledgeCredentialProvider: CloudKnowledgeCredentialProvider { let token: String; func accessToken() async throws -> String { token } }

private final class CloudKnowledgeCreatorAPITransportRecorder: @unchecked Sendable, ConnorBackendHTTPTransport {
    struct Request { let method: String; let path: String; let bodyObject: Any? }
    private(set) var requests: [Request] = []
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let bodyObject: Any? = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        requests.append(.init(method: request.httpMethod ?? "", path: request.url?.path ?? "", bodyObject: bodyObject))
        let json = #"{"data":{"id":"kb-1","name":"Connor","slug":"connor","visibility":"public","current_sequence":0,"lifecycle_status":"active","publication_status":"published","enforcement_status":"clear","governance_version":7,"appeal_count":0}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"] )!
        return (Data(json.utf8), response)
    }
}

private final class CloudKnowledgeCreatorAPIErrorTransport: @unchecked Sendable, ConnorBackendHTTPTransport {
    private var count = 0
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        count += 1
        let (code, body): (Int, String) = switch count {
        case 1: (409, #"{"code":"taken_down","message":"taken down"}"#)
        case 2: (409, #"{"error":{"code":"deleting","message":"deleting"}}"#)
        default: (410, #"{"code":"deleted","message":"deleted"}"#)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"] )!
        return (Data(body.utf8), response)
    }
}

private actor DetailTrackingCreatorAPI: CloudKnowledgeCreatorAPI {
    private var detail = CloudKnowledgeBaseDetail(id: "kb-1", name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "unpublished", enforcementStatus: "clear", governanceVersion: 1)
    func createKnowledgeBase(_ draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { detail }
    func updateKnowledgeBase(id: String, draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { detail }
    func knowledgeBase(id: String) async throws -> CloudKnowledgeBaseDetail { detail = .init(id: id, name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "published", enforcementStatus: "taken_down", governanceVersion: 4); return detail }
    func publishKnowledgeBase(id: String, request: CloudKnowledgePublishRequest) async throws -> CloudKnowledgeBaseDetail { detail = .init(id: id, name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "published", enforcementStatus: "clear", governanceVersion: request.expectedGovernanceVersion + 1); return detail }
    func unpublishKnowledgeBase(id: String, request: CloudKnowledgeUnpublishRequest) async throws -> CloudKnowledgeBaseDetail { detail = .init(id: id, name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "unpublished", enforcementStatus: "clear", governanceVersion: request.expectedGovernanceVersion + 1); return detail }
    func appealKnowledgeBase(id: String, statement: String, governanceActionID: String) async throws -> CloudKnowledgeBaseDetail { detail }
    func preview(runID: String) async throws -> CloudKnowledgePreview { .init(runID: runID, stagedSequence: 0, operations: [], summaries: []) }
    func revisions(knowledgeBaseID: String, limit: Int) async throws -> [CloudKnowledgeRevisionSummary] { [] }
}

private actor CreatorPublicationFakeAPI: CloudKnowledgeAPI {
    var rebasedSequence: Int?; var commitCount = 0
    func createPublicationRun(knowledgeBaseID: String, request: CloudKnowledgeCreateRunRequest) async throws -> CloudKnowledgePublicationRun { .init(id: "run", knowledgeBaseID: knowledgeBaseID, clientRunID: request.clientRunID, expectedBaseSequence: request.expectedBaseSequence) }
    func publicationRun(id: String) async throws -> CloudKnowledgePublicationRun { .init(id: id, knowledgeBaseID: "kb", clientRunID: "client", expectedBaseSequence: 0) }
    func appendOperations(runID: String, request: CloudKnowledgeOperationBatchRequest) async throws -> CloudKnowledgeOperationBatchResponse { .init(acceptedOperationIDs: [], stagedSequence: 0) }
    func validate(runID: String) async throws -> CloudKnowledgeValidationResult { .init(valid: true, issues: [], stagedSequence: 0) }
    func rebase(runID: String, request: CloudKnowledgeRebaseRequest) async throws -> CloudKnowledgePublicationRun { rebasedSequence = request.expectedBaseSequence; return .init(id: runID, knowledgeBaseID: "kb", clientRunID: "client", expectedBaseSequence: request.expectedBaseSequence) }
    func commit(runID: String) async throws -> CloudKnowledgeCommitResult { commitCount += 1; return .init(publicationRunID: runID, knowledgeSequence: 10) }
    func abandon(runID: String) async throws {}
    func search(knowledgeBaseID: String, channel: CloudKnowledgeSearchChannel, request: CloudKnowledgeSearchRequest) async throws -> CloudKnowledgeSearchResponse { .init(searchContextID: "s", channel: channel, baseSequence: 0, stagedSequence: 0) }
    func createKnowledgeBase(_ draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { .init(id: "kb-1", name: draft.name, slug: draft.slug, description: draft.description, visibility: draft.visibility, currentSequence: 0, lifecycleStatus: "active", publicationStatus: "unpublished") }
    func updateKnowledgeBase(id: String, draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { .init(id: id, name: draft.name, slug: draft.slug, description: draft.description, visibility: draft.visibility, currentSequence: 0, lifecycleStatus: "active", publicationStatus: "unpublished") }
    func knowledgeBase(id: String) async throws -> CloudKnowledgeBaseDetail { .init(id: id, name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "unpublished", enforcementStatus: "clear", governanceVersion: 6) }
    func publishKnowledgeBase(id: String, request: CloudKnowledgePublishRequest) async throws -> CloudKnowledgeBaseDetail { .init(id: id, name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "published", enforcementStatus: "clear", governanceVersion: request.expectedGovernanceVersion + 1) }
    func unpublishKnowledgeBase(id: String, request: CloudKnowledgeUnpublishRequest) async throws -> CloudKnowledgeBaseDetail { .init(id: id, name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "unpublished", enforcementStatus: "clear", governanceVersion: request.expectedGovernanceVersion + 1) }
    func appealKnowledgeBase(id: String, statement: String, governanceActionID: String) async throws -> CloudKnowledgeBaseDetail { .init(id: id, name: "Connor", slug: "connor", visibility: "public", currentSequence: 0, lifecycleStatus: "active", publicationStatus: "published", enforcementStatus: "clear", governanceVersion: 9, appealCount: 1) }
    func preview(runID: String) async throws -> CloudKnowledgePreview { .init(runID: runID, stagedSequence: 0, operations: [], summaries: []) }
    func revisions(knowledgeBaseID: String, limit: Int) async throws -> [CloudKnowledgeRevisionSummary] { [] }
}

