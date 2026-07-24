import Foundation
import Combine

private struct CloudKnowledgeCreatorCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

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
public struct CloudKnowledgeRevisionSummary: Codable, Sendable, Equatable, Identifiable {
    public var identityID: String
    public var revisionID: String
    public var layer: CloudKnowledgeLayer
    public var title: String?
    public var text: String
    public var revisionNumber: Int
    public var recordedAt: Date?
    public var id: String { revisionID }

    public init(identityID: String, revisionID: String, layer: CloudKnowledgeLayer, title: String? = nil, text: String, revisionNumber: Int, recordedAt: Date? = nil) {
        self.identityID = identityID
        self.revisionID = revisionID
        self.layer = layer
        self.title = title
        self.text = text
        self.revisionNumber = revisionNumber
        self.recordedAt = recordedAt
    }

    private enum CodingKeys: String, CodingKey {
        case identityID, revisionID, layer, title, text, revisionNumber, recordedAt, stableKey
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        identityID = try box.decode(String.self, forKey: .identityID)
        revisionID = try box.decode(String.self, forKey: .revisionID)
        layer = try box.decode(CloudKnowledgeLayer.self, forKey: .layer)
        title = try box.decodeIfPresent(String.self, forKey: .title)
            ?? box.decodeIfPresent(String.self, forKey: .stableKey)
        text = try box.decodeIfPresent(String.self, forKey: .text) ?? ""
        revisionNumber = try box.decode(Int.self, forKey: .revisionNumber)
        recordedAt = try box.decodeIfPresent(Date.self, forKey: .recordedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(identityID, forKey: .identityID)
        try box.encode(revisionID, forKey: .revisionID)
        try box.encode(layer, forKey: .layer)
        try box.encodeIfPresent(title, forKey: .title)
        try box.encode(text, forKey: .text)
        try box.encode(revisionNumber, forKey: .revisionNumber)
        try box.encodeIfPresent(recordedAt, forKey: .recordedAt)
    }
}
public struct CloudKnowledgePreview: Codable, Sendable, Equatable {
    public var publicationRunID: String; public var stagedSequence: Int; public var operations: [CloudKnowledgeOperation]; public var summaries: [String]
    public var runID: String { publicationRunID }
    public init(runID: String, stagedSequence: Int, operations: [CloudKnowledgeOperation], summaries: [String]) { self.publicationRunID = runID; self.stagedSequence = stagedSequence; self.operations = operations; self.summaries = summaries }
    private enum CodingKeys: String, CodingKey { case publicationRunID, runID, stagedSequence, operations, summaries }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        publicationRunID = try box.decodeIfPresent(String.self, forKey: .publicationRunID) ?? box.decode(String.self, forKey: .runID)
        stagedSequence = try box.decode(Int.self, forKey: .stagedSequence)
        operations = try box.decodeIfPresent([CloudKnowledgeOperation].self, forKey: .operations) ?? []
        if let values = try? box.decode([String].self, forKey: .summaries) {
            summaries = values
        } else {
            let counts = try box.decodeIfPresent([String: Int].self, forKey: .summaries) ?? [:]
            summaries = counts.keys.sorted().map { Self.summaryLabel(operation: $0, count: counts[$0] ?? 0) }
        }
    }
    public func encode(to encoder: Encoder) throws { var box = encoder.container(keyedBy: CodingKeys.self); try box.encode(publicationRunID, forKey: .publicationRunID); try box.encode(stagedSequence, forKey: .stagedSequence); try box.encode(operations, forKey: .operations); try box.encode(summaries, forKey: .summaries) }
    private static func summaryLabel(operation: String, count: Int) -> String {
        let label = switch operation {
        case "create": "新增"
        case "update": "更新"
        case "delete": "删除"
        default: operation
        }
        return "\(label) \(count) 项知识变更"
    }
}

public let cloudKnowledgeCreatorTermsVersion = "2026-07-13"

public struct CloudKnowledgePublishingAgreementSection: Sendable, Equatable, Identifiable {
    public var title: String
    public var body: String
    public var id: String { title }
    public init(title: String, body: String) { self.title = title; self.body = body }
}

public enum CloudKnowledgePublishingAgreement {
    public static let title = "知识库发布协议"
    public static let operatorName = "杭州康纳快跑科技有限公司"
    public static let version = cloudKnowledgeCreatorTermsVersion
    public static let effectiveDate = "2026年7月13日"
    public static let sections: [CloudKnowledgePublishingAgreementSection] = [
        .init(
            title: "一、协议范围",
            body: "本协议是知识库创作者与杭州康纳快跑科技有限公司（以下简称“平台”）之间关于创建、提交、公开发布和治理远端知识库的约定。创作者勾选同意并点击发布，即表示已阅读并接受本协议当前版本。"
        ),
        .init(
            title: "二、远端知识库的数据范围",
            body: "远端知识库仅承载 Memory OS 的 L2 动态运行上下文、L3 可复用知识与 L4 稳定实体及关系，不接收 L0 原始私密上下文或 L1 会话工作记忆。平台可以对提交内容执行与本地 Memory OS 一致的结构校验、安全检查、去重、索引和版本管理；正常内容自动处理，发现异常时可以阻止发布或要求创作者处理。"
        ),
        .init(
            title: "三、创作者保证",
            body: "创作者保证对发布内容拥有合法权利或已取得充分授权，内容真实、合法且不侵犯他人的知识产权、隐私权、商业秘密及其他权益。创作者不得提交密码、密钥、访问令牌、未获授权的个人敏感信息、依法不得公开的信息，或通过内容诱导系统实施违法、有害行为。"
        ),
        .init(
            title: "四、发布授权与订阅使用",
            body: "知识库公开发布后，其他用户可以在知识市场查看、订阅，并在康纳同学中检索和使用其中的结构化知识。为提供上述服务，创作者授予平台一项非独占、全球范围、免许可费的必要许可，用于存储、复制、格式转换、索引、展示、分发和安全治理相关内容。该许可仅限于运营知识库及改进相关服务所必需的范围。"
        ),
        .init(
            title: "五、版本、下架与治理",
            body: "平台记录知识变更、发布状态和治理版本。创作者可以下架知识库；下架后平台停止新的公开展示和订阅，但不影响用户在下架前已经基于该知识生成的合法输出。对于涉嫌违法、侵权、泄密、安全风险或严重降低服务质量的内容，平台可以限制展示、暂停订阅或下架，并向创作者提供适用的申诉渠道。"
        ),
        .init(
            title: "六、服务边界与责任",
            body: "结构校验、安全检查及自动生成不能替代创作者对内容的最终审查。创作者对其发布内容及由此引发的第三方主张承担相应责任。平台会采取合理措施保护数据和维持服务，但不保证知识内容绝对准确、完整或持续可用；法律另有强制规定的除外。"
        ),
        .init(
            title: "七、协议更新与争议处理",
            body: "平台可以因法律、产品或治理规则变化更新本协议，并以新的版本号和生效日期展示；需要再次确认时，平台会在发布前提示。协议的订立、履行与解释适用中华人民共和国法律。争议应先友好协商；协商不成的，任何一方可向平台所在地有管辖权的人民法院提起诉讼。相关通知与联系可通过康纳同学内的账号或支持渠道进行。"
        )
    ]
}

public struct CloudKnowledgePublishRequest: Codable, Sendable, Equatable {
    public var expectedGovernanceVersion: Int; public var idempotencyKey: UUID; public var termsVersion: String; public var termsAccepted: Bool
    public init(expectedGovernanceVersion: Int, idempotencyKey: UUID = UUID(), termsVersion: String = cloudKnowledgeCreatorTermsVersion, termsAccepted: Bool) { self.expectedGovernanceVersion = expectedGovernanceVersion; self.idempotencyKey = idempotencyKey; self.termsVersion = termsVersion; self.termsAccepted = termsAccepted }
}
public struct CloudKnowledgeUnpublishRequest: Codable, Sendable, Equatable {
    public var expectedGovernanceVersion: Int; public var idempotencyKey: UUID
    public init(expectedGovernanceVersion: Int, idempotencyKey: UUID = UUID()) { self.expectedGovernanceVersion = expectedGovernanceVersion; self.idempotencyKey = idempotencyKey }
}

public struct CloudKnowledgeRevisionPage: Sendable, Equatable {
    public var revisions: [CloudKnowledgeRevisionSummary]
    public var nextPage: Int?

    public init(revisions: [CloudKnowledgeRevisionSummary], nextPage: Int?) {
        self.revisions = revisions
        self.nextPage = nextPage
    }
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
    func revisionPage(knowledgeBaseID: String, page: Int, pageSize: Int) async throws -> CloudKnowledgeRevisionPage
}

public extension CloudKnowledgeCreatorAPI {
    func revisionPage(knowledgeBaseID: String, page: Int, pageSize: Int) async throws -> CloudKnowledgeRevisionPage {
        guard page == 1 else { return CloudKnowledgeRevisionPage(revisions: [], nextPage: nil) }
        return CloudKnowledgeRevisionPage(
            revisions: try await revisions(knowledgeBaseID: knowledgeBaseID, limit: pageSize),
            nextPage: nil
        )
    }
}

public struct CloudKnowledgeCreatorAPIClient: CloudKnowledgeCreatorAPI, Sendable {
    private let baseURL: URL; private let transport: any ConnorBackendHTTPTransport; private let credentials: any CloudKnowledgeCredentialProvider
    private let refreshRejectedToken: (@Sendable (String) async throws -> String)?
    private let encoder: JSONEncoder; private let decoder: JSONDecoder
    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared, credentials: any CloudKnowledgeCredentialProvider = StoredCloudKnowledgeCredentialProvider(), refreshRejectedToken: (@Sendable (String) async throws -> String)? = nil) {
        self.baseURL = baseURL; self.transport = transport; self.credentials = credentials; self.refreshRejectedToken = refreshRejectedToken
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601; self.encoder = encoder
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .custom { codingPath in
            let raw = codingPath.last?.stringValue ?? ""
            let parts = raw.split(separator: "_")
            let transformed = parts.enumerated().map { index, part -> String in
                if index == 0 { return String(part) }
                if part.lowercased() == "id" { return "ID" }
                if part.lowercased() == "ids" { return "IDs" }
                return part.prefix(1).uppercased() + part.dropFirst()
            }.joined()
            return CloudKnowledgeCreatorCodingKey(stringValue: transformed)!
        }
        self.decoder = decoder
    }
    public func createKnowledgeBase(_ draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases", method: "POST", body: draft) }
    public func updateKnowledgeBase(id: String, draft: CloudKnowledgeBaseDraft) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)", method: "PATCH", body: draft) }
    public func knowledgeBase(id: String) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)") }
    public func publishKnowledgeBase(id: String, request: CloudKnowledgePublishRequest) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)/publish", method: "POST", body: request) }
    public func unpublishKnowledgeBase(id: String, request: CloudKnowledgeUnpublishRequest) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)/publish", method: "DELETE", body: request) }
    public func appealKnowledgeBase(id: String, statement: String, governanceActionID: String) async throws -> CloudKnowledgeBaseDetail { try await send("knowledge-bases/\(id)/appeals", method: "POST", body: AppealRequest(statement: statement, governanceActionID: governanceActionID)) }
    public func preview(runID: String) async throws -> CloudKnowledgePreview { try await send("publication-runs/\(runID)/preview") }
    public func revisions(knowledgeBaseID: String, limit: Int = 100) async throws -> [CloudKnowledgeRevisionSummary] {
        try await revisionPage(knowledgeBaseID: knowledgeBaseID, page: 1, pageSize: limit).revisions
    }
    public func revisionPage(knowledgeBaseID: String, page: Int, pageSize: Int) async throws -> CloudKnowledgeRevisionPage {
        let resolvedPage = max(1, page)
        let resolvedPageSize = max(1, min(pageSize, 200))
        let revisions: [CloudKnowledgeRevisionSummary] = try await send("knowledge-bases/\(knowledgeBaseID)/revisions?page=\(resolvedPage)&limit=\(resolvedPageSize)")
        return CloudKnowledgeRevisionPage(
            revisions: revisions,
            nextPage: revisions.count == resolvedPageSize ? resolvedPage + 1 : nil
        )
    }
    private struct Envelope<T: Decodable>: Decodable { var data: T }
    private struct AppealRequest: Encodable { let statement: String; let governanceActionID: String }
    private func send<T: Decodable>(_ path: String, method: String = "GET") async throws -> T { try await send(path, method: method, bodyData: nil) }
    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T { try await send(path, method: method, bodyData: try encoder.encode(body)) }
    private func send<T: Decodable>(_ path: String, method: String, bodyData: Data?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("api/v2/", isDirectory: true))?.absoluteURL else { throw CloudKnowledgeError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = bodyData; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let initialToken = try await credentials.accessToken()
        request.setValue("Bearer \(initialToken)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await transport.data(for: request)
        guard var http = response as? HTTPURLResponse else { throw CloudKnowledgeError.invalidResponse }
        if http.statusCode == 401, let refreshRejectedToken {
            let refreshedToken = try await refreshRejectedToken(initialToken)
            request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await transport.data(for: request)
            guard let retriedHTTP = response as? HTTPURLResponse else { throw CloudKnowledgeError.invalidResponse }
            http = retriedHTTP
        }
        if http.statusCode == 401 { throw CloudKnowledgeError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data) }
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

public struct CloudKnowledgePublicationHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { snapshot.clientRunID }
    public var snapshot: CloudKnowledgeCreatorSnapshot
    public var createdAt: Date
    public var updatedAt: Date

    public init(snapshot: CloudKnowledgeCreatorSnapshot, createdAt: Date? = nil) {
        self.snapshot = snapshot
        self.createdAt = createdAt ?? snapshot.updatedAt
        self.updatedAt = snapshot.updatedAt
    }
}

public struct CloudKnowledgePublicationHistoryRepository: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> [CloudKnowledgePublicationHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CloudKnowledgePublicationHistoryEntry].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ entries: [CloudKnowledgePublicationHistoryEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
    }
}

public struct CloudKnowledgeLocalGenerationResult: Sendable, Equatable { public var summary: String; public init(summary: String) { self.summary = summary } }
public typealias CloudKnowledgeLocalGenerationCallback = @Sendable (_ localConversationID: String) async throws -> CloudKnowledgeLocalGenerationResult
public typealias CloudKnowledgeConflictRecoveryCallback = @Sendable (_ publicationRunID: String) async throws -> Int

@MainActor public final class CloudKnowledgeCreatorStore: ObservableObject {
    @Published public private(set) var snapshot: CloudKnowledgeCreatorSnapshot; @Published public private(set) var history: [CloudKnowledgeRevisionSummary] = []; @Published public private(set) var isWorking = false; @Published public private(set) var errorMessage: String?
    @Published public private(set) var publicationHistory: [CloudKnowledgePublicationHistoryEntry]
    @Published public private(set) var currentConversationID: String?
    private let repository: CloudKnowledgeCreatorSnapshotRepository; private let publicationHistoryRepository: CloudKnowledgePublicationHistoryRepository; private let creatorAPI: (any CloudKnowledgeCreatorAPI)?; private let publicationAPI: (any CloudKnowledgeAPI)?; private var generationTask: Task<Void, Never>?; private var generationDriverID: UUID?; private var localGeneration: CloudKnowledgeLocalGenerationCallback?; private var nextHistoryPage: Int?
    private static let historyPageSize = 50
    public init(repository: CloudKnowledgeCreatorSnapshotRepository = .init(), historyRepository: CloudKnowledgePublicationHistoryRepository? = nil, creatorAPI: (any CloudKnowledgeCreatorAPI)? = nil, publicationAPI: (any CloudKnowledgeAPI)? = nil) {
        self.repository = repository
        self.publicationHistoryRepository = historyRepository ?? .init(fileURL: repository.fileURL.deletingLastPathComponent().appendingPathComponent("publication-history.json"))
        self.creatorAPI = creatorAPI
        self.publicationAPI = publicationAPI
        self.snapshot = (try? repository.load()) ?? .init()
        self.publicationHistory = (try? self.publicationHistoryRepository.load()) ?? []
        recordCurrentSnapshotInHistory()
    }
    public func updateDraft(_ draft: CloudKnowledgeBaseDraft) { snapshot.draft = draft; persist() }
    public func toggleConversation(_ id: String) { if snapshot.selectedConversationIDs.contains(id) { snapshot.selectedConversationIDs.removeAll { $0 == id } } else { snapshot.selectedConversationIDs.append(id) }; persist() }
    public func advance(to stage: CloudKnowledgeCreatorStage) { snapshot.stage = stage; persist() }
    public func attachRun(id: String) { snapshot.runID = id; snapshot.stage = .generating; persist() }
    public func installGeneration(_ callback: @escaping CloudKnowledgeLocalGenerationCallback) {
        localGeneration = callback
        if snapshot.stage == .generating, snapshot.runID != nil { runRemainingGeneration() }
    }
    public var currentPublicationStatusLabel: String { snapshot.latestKnowledgeBaseDetail?.publicationStatus ?? (snapshot.knowledgeBaseID == nil ? "草稿" : "未发布") }
    public var currentEnforcementStatusLabel: String { snapshot.latestKnowledgeBaseDetail?.enforcementStatus ?? "clear" }
    public var currentGovernanceVersion: Int { snapshot.latestKnowledgeBaseDetail?.governanceVersion ?? 0 }
    @discardableResult
    public func publishKnowledgeBase(termsAccepted: Bool) async -> String? {
        guard let id = snapshot.knowledgeBaseID, let creatorAPI, let current = snapshot.latestKnowledgeBaseDetail else { return nil }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let request = CloudKnowledgePublishRequest(expectedGovernanceVersion: current.governanceVersion, termsAccepted: termsAccepted)
            let detail = try await creatorAPI.publishKnowledgeBase(id: id, request: request)
            self.snapshot.latestKnowledgeBaseDetail = detail
            self.snapshot.knowledgeBaseID = detail.id
            self.persist()
            return detail.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
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
            self.runRemainingGeneration()
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
                    self.currentConversationID = id
                    let result = try await callback(id)
                    // A successful local callback may already have durable side effects.
                    // Always checkpoint it before honoring cancellation.
                    self.noteProcessed(conversationID: id, summary: result.summary)
                    guard !Task.isCancelled else { return }
                } catch is CancellationError { self.currentConversationID = nil; return }
                catch { self.currentConversationID = nil; self.errorMessage = error.localizedDescription; self.snapshot.stage = .paused; self.persist(); return }
            }
            guard self.generationDriverID == driverID else { return }
            self.snapshot.stage = .validating
            self.currentConversationID = nil
            self.persist()
            await self.finalizePublication()
            self.generationTask = nil
            self.generationDriverID = nil
        }
    }
    public func pause() { generationTask?.cancel(); currentConversationID = nil; snapshot.stage = .paused; persist() }
    public func resume() { snapshot.stage = .generating; persist(); runRemainingGeneration() }
    public func waitForGenerationCompletion() async { await generationTask?.value }
    public func cancel() { generationTask?.cancel(); currentConversationID = nil; snapshot.stage = .cancelled; persist(); if let runID = snapshot.runID, let publicationAPI { Task { try? await publicationAPI.abandon(runID: runID) } } }
    public func validatePublication() async {
        guard let runID = snapshot.runID, let publicationAPI else { snapshot.stage = .validating; persist(); return }
        await perform { self.applyValidation(try await publicationAPI.validate(runID: runID)) }
    }
    public func finalizePublication() async {
        guard !isWorking else { return }
        await validatePublication()
        guard errorMessage == nil, snapshot.stage == .preview else { return }
        await loadPreview()
        guard errorMessage == nil, snapshot.preview != nil else { return }
        await commitPublication()
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
    public func loadHistory() async {
        guard let id = snapshot.knowledgeBaseID, let creatorAPI else { return }
        await perform {
            let page = try await creatorAPI.revisionPage(knowledgeBaseID: id, page: 1, pageSize: Self.historyPageSize)
            self.history = page.revisions
            self.nextHistoryPage = page.nextPage
        }
    }
    public func loadMoreHistoryIfNeeded(currentRevisionID: String) async {
        guard currentRevisionID == history.last?.id,
              let id = snapshot.knowledgeBaseID,
              let pageNumber = nextHistoryPage,
              let creatorAPI,
              !isWorking else { return }
        await perform {
            let page = try await creatorAPI.revisionPage(knowledgeBaseID: id, page: pageNumber, pageSize: Self.historyPageSize)
            let existingIDs = Set(self.history.map(\.id))
            self.history.append(contentsOf: page.revisions.filter { !existingIDs.contains($0.id) })
            self.nextHistoryPage = page.nextPage
        }
    }
    public func prepareForNewKnowledgeBase() {
        guard snapshot.stage == .cancelled || snapshot.stage == .completed else { return }
        reset()
    }
    public func canRemovePublicationHistory(id: String) -> Bool {
        snapshot.clientRunID != id || snapshot.stage == .cancelled || snapshot.stage == .completed
    }
    public func removePublicationHistory(id: String) {
        guard canRemovePublicationHistory(id: id) else { return }
        publicationHistory.removeAll { $0.id == id }
        try? publicationHistoryRepository.save(publicationHistory)
        if snapshot.clientRunID == id { reset() }
    }
    public func reset() { generationTask?.cancel(); currentConversationID = nil; snapshot = .init(); history = []; nextHistoryPage = nil; errorMessage = nil; try? repository.clear() }
    private func persist() { snapshot.updatedAt = Date(); try? repository.save(snapshot); recordCurrentSnapshotInHistory() }
    private func recordCurrentSnapshotInHistory() {
        let hasMeaningfulState = snapshot.knowledgeBaseID != nil || snapshot.runID != nil || !snapshot.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasMeaningfulState else { return }
        let createdAt = publicationHistory.first(where: { $0.id == snapshot.clientRunID })?.createdAt
        let entry = CloudKnowledgePublicationHistoryEntry(snapshot: snapshot, createdAt: createdAt)
        publicationHistory.removeAll { $0.id == entry.id }
        publicationHistory.append(entry)
        publicationHistory.sort { $0.updatedAt > $1.updatedAt }
        try? publicationHistoryRepository.save(publicationHistory)
    }
    private func perform(_ action: @escaping () async throws -> Void) async { isWorking = true; errorMessage = nil; defer { isWorking = false }; do { try await action() } catch { errorMessage = error.localizedDescription } }
}
