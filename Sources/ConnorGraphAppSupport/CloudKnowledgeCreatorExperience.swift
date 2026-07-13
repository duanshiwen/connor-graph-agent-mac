import Foundation
import Combine

public struct CloudKnowledgeBaseDraft: Codable, Sendable, Equatable {
    public var name: String; public var slug: String; public var description: String; public var visibility: String; public var defaultLocale: String
    public init(name: String = "", slug: String = "", description: String = "", visibility: String = "private", defaultLocale: String = "zh-CN") { self.name = name; self.slug = slug; self.description = description; self.visibility = visibility; self.defaultLocale = defaultLocale }
}
public struct CloudKnowledgeBaseDetail: Codable, Sendable, Equatable, Identifiable {
    public var id: String; public var name: String; public var slug: String; public var description: String?; public var visibility: String; public var currentSequence: Int; public var lifecycleStatus: String; public var publicationStatus: String; public var enforcementStatus: String; public var governanceVersion: Int; public var latestTakedownActionID: String?; public var appealCount: Int
    public init(id: String, name: String, slug: String, description: String? = nil, visibility: String, currentSequence: Int, lifecycleStatus: String, publicationStatus: String, enforcementStatus: String = "clear", governanceVersion: Int = 1, latestTakedownActionID: String? = nil, appealCount: Int = 0) { self.id = id; self.name = name; self.slug = slug; self.description = description; self.visibility = visibility; self.currentSequence = currentSequence; self.lifecycleStatus = lifecycleStatus; self.publicationStatus = publicationStatus; self.enforcementStatus = enforcementStatus; self.governanceVersion = governanceVersion; self.latestTakedownActionID = latestTakedownActionID; self.appealCount = appealCount }
    private enum CodingKeys: String, CodingKey { case id, kbID, name, slug, description, visibility, currentSequence, lifecycleStatus, publicationStatus, enforcementStatus, governanceVersion, governance_version, latestTakedownActionId, appealCount, appeal_count }
    public init(from decoder: Decoder) throws { let box = try decoder.container(keyedBy: CodingKeys.self); id = try box.decodeIfPresent(String.self, forKey: .id) ?? box.decode(String.self, forKey: .kbID); name = try box.decode(String.self, forKey: .name); slug = try box.decode(String.self, forKey: .slug); description = try box.decodeIfPresent(String.self, forKey: .description); visibility = try box.decode(String.self, forKey: .visibility); currentSequence = try box.decodeIfPresent(Int.self, forKey: .currentSequence) ?? 0; lifecycleStatus = try box.decodeIfPresent(String.self, forKey: .lifecycleStatus) ?? "active"; publicationStatus = try box.decodeIfPresent(String.self, forKey: .publicationStatus) ?? "unpublished"; enforcementStatus = try box.decodeIfPresent(String.self, forKey: .enforcementStatus) ?? "clear"; governanceVersion = try box.decodeIfPresent(Int.self, forKey: .governanceVersion) ?? box.decodeIfPresent(Int.self, forKey: .governance_version) ?? 1; latestTakedownActionID = try box.decodeIfPresent(String.self, forKey: .latestTakedownActionId); appealCount = try box.decodeIfPresent(Int.self, forKey: .appealCount) ?? box.decodeIfPresent(Int.self, forKey: .appeal_count) ?? 0 }
    public func encode(to encoder: Encoder) throws { var box = encoder.container(keyedBy: CodingKeys.self); try box.encode(id, forKey: .id); try box.encode(name, forKey: .name); try box.encode(slug, forKey: .slug); try box.encodeIfPresent(description, forKey: .description); try box.encode(visibility, forKey: .visibility); try box.encode(currentSequence, forKey: .currentSequence); try box.encode(lifecycleStatus, forKey: .lifecycleStatus); try box.encode(publicationStatus, forKey: .publicationStatus); try box.encode(enforcementStatus, forKey: .enforcementStatus); try box.encode(governanceVersion, forKey: .governanceVersion); try box.encode(governanceVersion, forKey: .governance_version); try box.encodeIfPresent(latestTakedownActionID, forKey: .latestTakedownActionId); try box.encode(appealCount, forKey: .appealCount); try box.encode(appealCount, forKey: .appeal_count) }
}
public struct CloudKnowledgeRevisionSummary: Codable, Sendable, Equatable, Identifiable { public var identityID: String; public var revisionID: String; public var layer: CloudKnowledgeLayer; public var title: String?; public var text: String; public var revisionNumber: Int; public var recordedAt: Date?; public var id: String { revisionID }; public init(identityID: String, revisionID: String, layer: CloudKnowledgeLayer, title: String? = nil, text: String, revisionNumber: Int, recordedAt: Date? = nil) { self.identityID = identityID; self.revisionID = revisionID; self.layer = layer; self.title = title; self.text = text; self.revisionNumber = revisionNumber; self.recordedAt = recordedAt } }
public struct CloudKnowledgePreview: Codable, Sendable, Equatable {
    public var publicationRunID: String; public var stagedSequence: Int; public var operations: [CloudKnowledgeOperation]; public var summaries: [String]
    public var runID: String { publicationRunID }
    public init(runID: String, stagedSequence: Int, operations: [CloudKnowledgeOperation], summaries: [String]) { self.publicationRunID = runID; self.stagedSequence = stagedSequence; self.operations = operations; self.summaries = summaries }
    private enum CodingKeys: String, CodingKey { case publicationRunID, runID, stagedSequence, operations, summaries }
    public init(from decoder: Decoder) throws { let box = try decoder.container(keyedBy: CodingKeys.self); publicationRunID = try box.decodeIfPresent(String.self, forKey: .publicationRunID) ?? box.decode(String.self, forKey: .runID); stagedSequence = try box.decode(Int.self, forKey: .stagedSequence); operations = try box.decodeIfPresent([CloudKnowledgeOperation].self, forKey: .operations) ?? []; summaries = try box.decodeIfPresent([String].self, forKey: .summaries) ?? [] }
    public func encode(to encoder: Encoder) throws { var box = encoder.container(keyedBy: CodingKeys.self); try box.encode(publicationRunID, forKey: .publicationRunID); try box.encode(stagedSequence, forKey: .stagedSequence); try box.encode(operations, forKey: .operations); try box.encode(summaries, forKey: .summaries) }
}

public let cloudKnowledgeCreatorTermsVersion = "2026-07-13"

public struct CloudKnowledgePublishRequest: Codable, Sendable, Equatable {
    public var expectedGovernanceVersion: Int; public var idempotencyKey: UUID; public var termsVersion: String; public var termsAccepted: Bool
    public init(expectedGovernanceVersion: Int, idempotencyKey: UUID = UUID(), termsVersion: String = cloudKnowledgeCreatorTermsVersion, termsAccepted: Bool) { self.expectedGovernanceVersion = expectedGovernanceVersion; self.idempotencyKey = idempotencyKey; self.termsVersion = termsVersion; self.termsAccepted = termsAccepted }
}
public struct CloudKnowledgeUnpublishRequest: Codable, Sendable, Equatable {
    public var expectedGovernanceVersion: Int; public var idempotencyKey: UUID
    public init(expectedGovernanceVersion: Int, idempotencyKey: UUID = UUID()) { self.expectedGovernanceVersion = expectedGovernanceVersion; self.idempotencyKey = idempotencyKey }
}

public protocol CloudKnowledgeCreatorAPI: Sendable {
    func createKnowledgeBase(_ draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail
    func updateKnowledgeBase(id: String, draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail
    func knowledgeBase(id: String) async throws -> CloudKnowledgeBaseDetail
    func publishKnowledgeBase(id: String, request: CloudKnowledgePublishRequest) async throws -> CloudKnowledgeBaseDetail
    func unpublishKnowledgeBase(id: String, request: CloudKnowledgeUnpublishRequest) async throws -> CloudKnowledgeBaseDetail
    func appealKnowledgeBase(id: String, statement: String, governanceActionID: String) async throws -> CloudKnowledgeBaseDetail
    func preview(runID: String) async throws -> CloudKnowledgePreview
    func revisions(knowledgeBaseID: String, limit: Int) async throws -> [CloudKnowledgeRevisionSummary]
}

public struct CloudKnowledgeCreatorAPIClient: CloudKnowledgeCreatorAPI, Sendable {
    private let baseURL: URL; private let transport: any ConnorBackendHTTPTransport; private let credentials: any CloudKnowledgeCredentialProvider
    private let encoder: JSONEncoder; private let decoder: JSONDecoder
    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared, credentials: any CloudKnowledgeCredentialProvider = StoredCloudKnowledgeCredentialProvider()) {
        self.baseURL = baseURL; self.transport = transport; self.credentials = credentials
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601; self.encoder = encoder
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .iso8601; self.decoder = decoder
    }
    public func createKnowledgeBase(_ draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases", method: "POST", body: draft) }
    public func updateKnowledgeBase(id: String, draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)", method: "PATCH", body: draft) }
    public func knowledgeBase(id: String) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)") }
    public func publishKnowledgeBase(id: String, request: CloudKnowledgePublishRequest) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)/publish", method: "POST", body: request) }
    public func unpublishKnowledgeBase(id: String, request: CloudKnowledgeUnpublishRequest) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)/publish", method: "DELETE", body: request) }
    public func appealKnowledgeBase(id: String, statement: String, governanceActionID: String) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)/appeals", method: "POST", body: AppealRequest(statement: statement, governanceActionID: governanceActionID)) }
    public func preview(runID: String) async throws -> CloudKnowledgePreview { try await send("publication-runs/\(runID)/preview") }
    public func revisions(knowledgeBaseID: String, limit: Int = 100) async throws -> [CloudKnowledgeRevisionSummary] { try await send("knowledge-bases/\(knowledgeBaseID)/revisions?limit=\(max(1, min(limit, 200)))") }
    private struct Envelope<T: Decodable>: Decodable { var data: T }
    private struct AppealRequest: Encodable { let statement: String; let governanceActionID: String }
    private func send<T: Decodable>(_ path: String, method: String = "GET") async throws -> T { try await send(path, method: method, bodyData: nil) }
    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T { try await send(path, method: method, bodyData: try encoder.encode(body)) }
    private func send<T: Decodable>(_ path: String, method: String, bodyData: Data?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("api/v2/", isDirectory: true))?.absoluteURL else { throw CloudKnowledgeError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = bodyData; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request); guard let http = response as? HTTPURLResponse else { throw CloudKnowledgeError.invalidResponse }; if http.statusCode == 401 { throw CloudKnowledgeError.unauthorized }; guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data) }
        if let envelope = try? decoder.decode(Envelope<T>.self, from: data) { return envelope.data }; guard let value = try? decoder.decode(T.self, from: data) else { throw CloudKnowledgeError.invalidResponse }; return value
    }
    private static func error(status: Int, data: Data) -> CloudKnowledgeError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = object?["code"] as? String ?? (object?["error"] as? [String: Any])?["code"] as? String
        let message = object?["message"] as? String ?? object?["msg"] as? String ?? (object?["error"] as? [String: Any])?["message"] as? String ?? "请求失败（\(status)）"
        switch code {
        case "taken_down", "knowledge_base_taken_down": return .takenDown
        case "deleting", "knowledge_base_deleting": return .deleting
        case "deleted", "knowledge_base_deleted": return .deleted
        case "stale_governance_version": return .staleGovernanceVersion
        case "publication_conflict": return .publicationConflict(currentSequence: (object?["current_sequence"] as? Int) ?? (object?["error"] as? [String: Any])?["current_sequence"] as? Int)
        case "search_before_write_required": return .searchBeforeWriteRequired
        case "search_context_not_relevant": return .searchContextNotRelevant
        case "search_context_stale": return .searchContextStale
        default: return status == 409 ? .publicationConflict(currentSequence: (object?["current_sequence"] as? Int) ?? (object?["error"] as? [String: Any])?["current_sequence"] as? Int) : .server(status: status, code: code, message: message)
        }
    }
}

public enum CloudKnowledgeCreatorStage: String, Codable, Sendable, CaseIterable { case configure, conversations, confirm, generating, paused, validating, preview, conflict, completed, cancelled }
public struct CloudKnowledgeCreatorSnapshot: Codable, Sendable, Equatable {
    public var stage: CloudKnowledgeCreatorStage; public var knowledgeBaseID: String?; public var draft: CloudKnowledgeBaseDraft; public var selectedConversationIDs: [String]
    public var runID: String?; public var clientRunID: String; public var processedConversationIDs: [String]; public var summaries: [String]
    public var validationIssues: [CloudKnowledgeValidationIssue]; public var preview: CloudKnowledgePreview?; public var latestKnowledgeBaseDetail: CloudKnowledgeBaseDetail?; public var updatedAt: Date
    public init(stage: CloudKnowledgeCreatorStage = .configure, knowledgeBaseID: String? = nil, draft: CloudKnowledgeBaseDraft = .init(), selectedConversationIDs: [String] = [], runID: String? = nil, clientRunID: String = UUID().uuidString, processedConversationIDs: [String] = [], summaries: [String] = [], validationIssues: [CloudKnowledgeValidationIssue] = [], preview: CloudKnowledgePreview? = nil, latestKnowledgeBaseDetail: CloudKnowledgeBaseDetail? = nil, updatedAt: Date = Date()) { self.stage = stage; self.knowledgeBaseID = knowledgeBaseID; self.draft = draft; self.selectedConversationIDs = selectedConversationIDs; self.runID = runID; self.clientRunID = clientRunID; self.processedConversationIDs = processedConversationIDs; self.summaries = summaries; self.validationIssues = validationIssues; self.preview = preview; self.latestKnowledgeBaseDetail = latestKnowledgeBaseDetail; self.updatedAt = updatedAt }
}

public struct CloudKnowledgeCreatorSnapshotRepository: Sendable {
    public var fileURL: URL
    public init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Connor/cloud-knowledge/creator-snapshot.json")) { self.fileURL = fileURL }
    public func load() throws -> CloudKnowledgeCreatorSnapshot? { guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(CloudKnowledgeCreatorSnapshot.self, from: Data(contentsOf: fileURL)) }
    public func save(_ snapshot: CloudKnowledgeCreatorSnapshot) throws { try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(snapshot).write(to: fileURL, options: .atomic) }
    public func clear() throws { if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) } }
}

public struct CloudKnowledgeLocalGenerationResult: Sendable, Equatable { public var summary: String; public init(summary: String) { self.summary = summary } }
public typealias CloudKnowledgeLocalGenerationCallback = @Sendable (_ localConversationID: String) async throws -> CloudKnowledgeLocalGenerationResult
public typealias CloudKnowledgeConflictRecoveryCallback = @Sendable (_ publicationRunID: String) async throws -> Int

@MainActor public final class CloudKnowledgeCreatorStore: ObservableObject {
    @Published public private(set) var snapshot: CloudKnowledgeCreatorSnapshot; @Published public private(set) var history: [CloudKnowledgeRevisionSummary] = []; @Published public private(set) var isWorking = false; @Published public private(set) var errorMessage: String?
    private let repository: CloudKnowledgeCreatorSnapshotRepository; private let creatorAPI: (any CloudKnowledgeCreatorAPI)?; private let publicationAPI: (any CloudKnowledgeAPI)?; private var generationTask: Task<Void, Never>?; private var generationDriverID: UUID?; private var localGeneration: CloudKnowledgeLocalGenerationCallback?
    public init(repository: CloudKnowledgeCreatorSnapshotRepository = .init(), creatorAPI: (any CloudKnowledgeCreatorAPI)? = nil, publicationAPI: (any CloudKnowledgeAPI)? = nil) { self.repository = repository; self.creatorAPI = creatorAPI; self.publicationAPI = publicationAPI; self.snapshot = (try? repository.load()) ?? .init() }
    public func updateDraft(_ draft: CloudKnowledgeBaseDraft) { snapshot.draft = draft; persist() }
    public func toggleConversation(_ id: String) { if snapshot.selectedConversationIDs.contains(id) { snapshot.selectedConversationIDs.removeAll { $0 == id } } else { snapshot.selectedConversationIDs.append(id) }; persist() }
    public func advance(to stage: CloudKnowledgeCreatorStage) { snapshot.stage = stage; persist() }
    public func attachRun(id: String) { snapshot.runID = id; snapshot.stage = .generating; persist() }
    public var currentPublicationStatusLabel: String { snapshot.latestKnowledgeBaseDetail?.publicationStatus ?? (snapshot.knowledgeBaseID == nil ? "草稿" : "未发布") }
    public var currentEnforcementStatusLabel: String { snapshot.latestKnowledgeBaseDetail?.enforcementStatus ?? "clear" }
    public var currentGovernanceVersion: Int { snapshot.latestKnowledgeBaseDetail?.governanceVersion ?? 0 }
    public func publishKnowledgeBase(termsAccepted: Bool) async {
        guard let id = snapshot.knowledgeBaseID, let creatorAPI, let current = snapshot.latestKnowledgeBaseDetail else { return }
        await perform {
            let request = CloudKnowledgePublishRequest(expectedGovernanceVersion: current.governanceVersion, termsAccepted: termsAccepted)
            let detail = try await creatorAPI.publishKnowledgeBase(id: id, request: request)
            self.snapshot.latestKnowledgeBaseDetail = detail
            self.snapshot.knowledgeBaseID = detail.id
            self.persist()
        }
    }
    public func unpublishKnowledgeBase() async {
        guard let id = snapshot.knowledgeBaseID, let creatorAPI, let current = snapshot.latestKnowledgeBaseDetail else { return }
        await perform {
            let detail = try await creatorAPI.unpublishKnowledgeBase(id: id, request: .init(expectedGovernanceVersion: current.governanceVersion))
            self.snapshot.latestKnowledgeBaseDetail = detail
            self.snapshot.knowledgeBaseID = detail.id
            self.persist()
        }
    }
    public func appealKnowledgeBase(statement: String) async {
        guard let id = snapshot.knowledgeBaseID, let creatorAPI, let governanceActionID = snapshot.latestKnowledgeBaseDetail?.latestTakedownActionID else { return }
        await perform {
            let detail = try await creatorAPI.appealKnowledgeBase(id: id, statement: statement, governanceActionID: governanceActionID)
            self.snapshot.latestKnowledgeBaseDetail = detail
            self.snapshot.knowledgeBaseID = detail.id
            self.persist()
        }
    }
    public func saveKnowledgeBase() async {
        guard let creatorAPI else { snapshot.stage = .conversations; persist(); return }
        await perform {
            let detail: CloudKnowledgeBaseDetail
            if let id = self.snapshot.knowledgeBaseID { detail = try await creatorAPI.updateKnowledgeBase(id: id, draft: self.snapshot.draft) }
            else { detail = try await creatorAPI.createKnowledgeBase(self.snapshot.draft) }
            self.snapshot.knowledgeBaseID = detail.id; self.snapshot.latestKnowledgeBaseDetail = detail; self.snapshot.stage = .conversations; self.persist()
        }
    }
    public func beginPublication() async {
        guard let knowledgeBaseID = snapshot.knowledgeBaseID, let publicationAPI else { snapshot.stage = .generating; persist(); return }
        await perform {
            let detail = try await self.creatorAPI?.knowledgeBase(id: knowledgeBaseID)
            if let detail { self.snapshot.latestKnowledgeBaseDetail = detail; self.persist() }
            let run = try await publicationAPI.createPublicationRun(knowledgeBaseID: knowledgeBaseID, request: .init(clientRunID: self.snapshot.clientRunID, expectedBaseSequence: detail?.currentSequence ?? 0))
            self.attachRun(id: run.id)
        }
    }
    public func noteProcessed(conversationID: String, summary: String) { if !snapshot.processedConversationIDs.contains(conversationID) { snapshot.processedConversationIDs.append(conversationID) }; snapshot.summaries.append(summary); persist() }
    public func startGeneration(using callback: @escaping CloudKnowledgeLocalGenerationCallback) {
        guard !snapshot.selectedConversationIDs.isEmpty else { errorMessage = "请至少选择一个本地对话。"; return }
        localGeneration = callback; snapshot.stage = .generating; persist(); runRemainingGeneration()
    }
    private func runRemainingGeneration() {
        let previousTask = generationTask
        previousTask?.cancel()
        guard let callback = localGeneration else { return }
        let driverID = UUID()
        generationDriverID = driverID
        generationTask = Task { [weak self] in
            await previousTask?.value
            guard let self, self.generationDriverID == driverID, !Task.isCancelled else { return }
            let remaining = self.snapshot.selectedConversationIDs.filter { !self.snapshot.processedConversationIDs.contains($0) }
            for id in remaining {
                guard !Task.isCancelled else { return }
                do {
                    let result = try await callback(id)
                    // A successful local callback may already have durable side effects.
                    // Always checkpoint it before honoring cancellation.
                    self.noteProcessed(conversationID: id, summary: result.summary)
                    guard !Task.isCancelled else { return }
                } catch is CancellationError { return }
                catch { self.errorMessage = error.localizedDescription; self.snapshot.stage = .paused; self.persist(); return }
            }
            guard self.generationDriverID == driverID else { return }
            self.snapshot.stage = .validating
            self.persist()
            self.generationTask = nil
            self.generationDriverID = nil
        }
    }
    public func pause() { generationTask?.cancel(); snapshot.stage = .paused; persist() }
    public func resume() { snapshot.stage = .generating; persist(); runRemainingGeneration() }
    public func waitForGenerationCompletion() async { await generationTask?.value }
    public func cancel() { generationTask?.cancel(); snapshot.stage = .cancelled; persist(); if let runID = snapshot.runID, let publicationAPI { Task { try? await publicationAPI.abandon(runID: runID) } } }
    public func validatePublication() async {
        guard let runID = snapshot.runID, let publicationAPI else { snapshot.stage = .validating; persist(); return }
        await perform { self.applyValidation(try await publicationAPI.validate(runID: runID)) }
    }
    public func applyValidation(_ result: CloudKnowledgeValidationResult) { snapshot.validationIssues = result.issues; snapshot.stage = result.valid ? .preview : .validating; persist() }
    public func markConflict() { snapshot.stage = .conflict; persist() }
    public func recoverConflict(using callback: @escaping CloudKnowledgeConflictRecoveryCallback) async {
        guard let runID = snapshot.runID, let publicationAPI else { return }
        await perform {
            let newBaseSequence = try await callback(runID)
            _ = try await publicationAPI.rebase(runID: runID, request: .init(expectedBaseSequence: newBaseSequence))
            self.snapshot.stage = .generating; self.persist(); self.runRemainingGeneration()
        }
    }
    public func setPreview(_ preview: CloudKnowledgePreview) { snapshot.preview = preview; snapshot.stage = .preview; persist() }
    public func commitPublication() async {
        guard let runID = snapshot.runID, let publicationAPI else { snapshot.stage = .completed; persist(); return }
        await perform { _ = try await publicationAPI.commit(runID: runID); self.snapshot.stage = .completed; self.persist(); await self.loadHistory() }
    }
    public func complete() { snapshot.stage = .completed; persist() }
    public func loadPreview() async { guard let runID = snapshot.runID, let creatorAPI else { return }; await perform { self.setPreview(try await creatorAPI.preview(runID: runID)) } }
    public func refreshLatestKnowledgeBaseDetail() async {
        guard let id = snapshot.knowledgeBaseID, let creatorAPI else { return }
        await perform {
            let detail = try await creatorAPI.knowledgeBase(id: id)
            self.snapshot.latestKnowledgeBaseDetail = detail
            self.persist()
        }
    }
    public func loadHistory() async { guard let id = snapshot.knowledgeBaseID, let creatorAPI else { return }; await perform { self.history = try await creatorAPI.revisions(knowledgeBaseID: id, limit: 100) } }
    public func reset() { generationTask?.cancel(); snapshot = .init(); history = []; errorMessage = nil; try? repository.clear() }
    private func persist() { snapshot.updatedAt = Date(); try? repository.save(snapshot) }
    private func perform(_ action: @escaping () async throws -> Void) async { isWorking = true; errorMessage = nil; defer { isWorking = false }; do { try await action() } catch { errorMessage = error.localizedDescription } }
}
