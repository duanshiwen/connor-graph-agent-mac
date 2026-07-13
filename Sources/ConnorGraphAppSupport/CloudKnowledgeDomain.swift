import Foundation

public enum CloudKnowledgeLayer: String, Codable, Sendable, CaseIterable { case l2 = "L2", l3 = "L3", l4 = "L4" }
public enum CloudKnowledgeSearchChannel: String, Codable, Sendable { case recentContext = "recent_context", knowledgeContext = "knowledge_context", writeAssist = "write_assist", answer }
public enum CloudKnowledgeSearchView: String, Codable, Sendable { case committed, staged, combined }
public enum CloudKnowledgeRunStatus: String, Codable, Sendable { case open, staging, validating, ready, conflict, committed, abandoned }
public enum CloudKnowledgeDecision: String, Codable, Sendable, CaseIterable { case skipDuplicate = "skip_duplicate", reviseExisting = "revise_existing", reuseIdentity = "reuse_identity", recordTemporalChange = "record_temporal_change", recordConflict = "record_conflict", createNew = "create_new" }

public enum CloudKnowledgeJSONValue: Codable, Sendable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool), object([String: CloudKnowledgeJSONValue]), array([CloudKnowledgeJSONValue]), null
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Int.self) { self = .int(value) }
        else if let value = try? box.decode(Double.self) { self = .double(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: Self].self) { self = .object(value) }
        else { self = .array(try box.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .int(let value): try box.encode(value)
        case .double(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
}

public struct CloudKnowledgePublicationRun: Codable, Sendable, Equatable, Identifiable {
    public var id: String; public var knowledgeBaseID: String; public var clientRunID: String
    public var expectedBaseSequence: Int; public var currentStagedSequence: Int; public var status: CloudKnowledgeRunStatus
    public var schemaVersion: String; public var createdAt: Date?; public var updatedAt: Date?
    public init(id: String, knowledgeBaseID: String, clientRunID: String, expectedBaseSequence: Int, currentStagedSequence: Int = 0, status: CloudKnowledgeRunStatus = .open, schemaVersion: String = "v2", createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id; self.knowledgeBaseID = knowledgeBaseID; self.clientRunID = clientRunID; self.expectedBaseSequence = expectedBaseSequence; self.currentStagedSequence = currentStagedSequence; self.status = status; self.schemaVersion = schemaVersion; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct CloudKnowledgeCreateRunRequest: Codable, Sendable, Equatable {
    public var clientRunID: String; public var expectedBaseSequence: Int; public var schemaVersion: String
    public init(clientRunID: String, expectedBaseSequence: Int, schemaVersion: String = "v2") { self.clientRunID = clientRunID; self.expectedBaseSequence = expectedBaseSequence; self.schemaVersion = schemaVersion }
}

public struct CloudKnowledgeSearchRequest: Codable, Sendable, Equatable {
    public var query: String; public var view: CloudKnowledgeSearchView; public var publicationRunID: String?
    public var layers: [CloudKnowledgeLayer]; public var kinds: [String]; public var domain: String?; public var limit: Int
    public var minSequence: Int?; public var referenceValidTime: Date?; public var asRecordedAt: Date?
    public init(query: String, view: CloudKnowledgeSearchView = .combined, publicationRunID: String? = nil, layers: [CloudKnowledgeLayer], kinds: [String] = [], domain: String? = nil, limit: Int = 20, minSequence: Int? = nil, referenceValidTime: Date? = nil, asRecordedAt: Date? = nil) {
        self.query = query; self.view = view; self.publicationRunID = publicationRunID; self.layers = layers; self.kinds = kinds; self.domain = domain; self.limit = max(1, min(limit, 100)); self.minSequence = minSequence; self.referenceValidTime = referenceValidTime; self.asRecordedAt = asRecordedAt
    }
}

public struct CloudKnowledgeSearchHit: Codable, Sendable, Equatable, Identifiable {
    public var source: String?; public var identityID: String?; public var revisionID: String?; public var layer: CloudKnowledgeLayer; public var kind: String
    public var stableKey: String?; public var payload: CloudKnowledgeJSONValue?; public var score: Double?; public var stagedSequence: Int?
    public var title: String?; public var text: String; public var staged: Bool; public var hints: [String]
    public var id: String { revisionID ?? identityID ?? stableKey ?? "\(layer.rawValue):\(kind):\(text)" }
    public init(identityID: String?, revisionID: String? = nil, layer: CloudKnowledgeLayer, kind: String, title: String? = nil, text: String, score: Double? = nil, staged: Bool = false, hints: [String] = [], source: String? = nil, stableKey: String? = nil, payload: CloudKnowledgeJSONValue? = nil, stagedSequence: Int? = nil) {
        self.source = source; self.identityID = identityID; self.revisionID = revisionID; self.layer = layer; self.kind = kind; self.stableKey = stableKey; self.payload = payload; self.score = score; self.stagedSequence = stagedSequence; self.title = title; self.text = text; self.staged = staged; self.hints = hints
    }
    private enum CodingKeys: String, CodingKey { case source, identityID, revisionID, layer, kind, stableKey, payload, score, stagedSequence, title, text, staged, hints }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        source = try box.decodeIfPresent(String.self, forKey: .source)
        identityID = try box.decodeIfPresent(String.self, forKey: .identityID)
        revisionID = try box.decodeIfPresent(String.self, forKey: .revisionID)
        layer = try box.decode(CloudKnowledgeLayer.self, forKey: .layer)
        kind = try box.decode(String.self, forKey: .kind)
        stableKey = try box.decodeIfPresent(String.self, forKey: .stableKey)
        payload = try box.decodeIfPresent(CloudKnowledgeJSONValue.self, forKey: .payload)
        score = try box.decodeIfPresent(Double.self, forKey: .score)
        stagedSequence = try box.decodeIfPresent(Int.self, forKey: .stagedSequence)
        let explicitTitle = try box.decodeIfPresent(String.self, forKey: .title)
        let explicitText = try box.decodeIfPresent(String.self, forKey: .text)
        title = explicitTitle ?? Self.string(in: payload, keys: ["title", "name", "summary"]) ?? stableKey
        text = explicitText ?? Self.string(in: payload, keys: ["summary", "content", "text", "title"]) ?? Self.canonicalText(payload) ?? stableKey ?? kind
        let explicitStaged = try box.decodeIfPresent(Bool.self, forKey: .staged)
        staged = explicitStaged ?? ((source?.lowercased() == "staged") || stagedSequence != nil)
        hints = try box.decodeIfPresent([String].self, forKey: .hints) ?? []
    }
    private static func string(in payload: CloudKnowledgeJSONValue?, keys: [String]) -> String? {
        guard case .object(let object)? = payload else { return nil }
        for key in keys { if case .string(let value)? = object[key], !value.isEmpty { return value } }
        return nil
    }
    private static func canonicalText(_ payload: CloudKnowledgeJSONValue?) -> String? {
        guard let payload, let data = try? JSONEncoder().encode(payload), let object = try? JSONSerialization.jsonObject(with: data), let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: canonical, encoding: .utf8)
    }
}

public struct CloudKnowledgeSearchResponse: Codable, Sendable, Equatable {
    public var searchContextID: String; public var channel: CloudKnowledgeSearchChannel; public var baseSequence: Int; public var stagedSequence: Int
    public var expiresAt: Date?; public var results: [CloudKnowledgeSearchHit]
    public init(searchContextID: String, channel: CloudKnowledgeSearchChannel, baseSequence: Int, stagedSequence: Int, expiresAt: Date? = nil, results: [CloudKnowledgeSearchHit] = []) { self.searchContextID = searchContextID; self.channel = channel; self.baseSequence = baseSequence; self.stagedSequence = stagedSequence; self.expiresAt = expiresAt; self.results = results }
}

public struct CloudKnowledgeOperation: Codable, Sendable, Equatable, Identifiable {
    public var operationID: String; public var operationType: String; public var layer: CloudKnowledgeLayer
    public var targetIdentityID: String?; public var expectedRevisionID: String?; public var decision: CloudKnowledgeDecision
    public var searchContextID: String; public var semanticTerms: [String]; public var payload: [String: CloudKnowledgeJSONValue]
    public var id: String { operationID }
    public init(operationID: String = UUID().uuidString, operationType: String, layer: CloudKnowledgeLayer, targetIdentityID: String? = nil, expectedRevisionID: String? = nil, decision: CloudKnowledgeDecision, searchContextID: String, semanticTerms: [String], payload: [String: CloudKnowledgeJSONValue]) {
        self.operationID = operationID; self.operationType = operationType; self.layer = layer; self.targetIdentityID = targetIdentityID; self.expectedRevisionID = expectedRevisionID; self.decision = decision; self.searchContextID = searchContextID; self.semanticTerms = semanticTerms; self.payload = payload
    }
}

public struct CloudKnowledgeOperationBatchRequest: Codable, Sendable, Equatable { public var operations: [CloudKnowledgeOperation]; public init(operations: [CloudKnowledgeOperation]) { self.operations = operations } }
public struct CloudKnowledgeOperationBatchResponse: Codable, Sendable, Equatable { public var acceptedOperationIDs: [String]; public var stagedSequence: Int; public init(acceptedOperationIDs: [String], stagedSequence: Int) { self.acceptedOperationIDs = acceptedOperationIDs; self.stagedSequence = stagedSequence } }
public struct CloudKnowledgeValidationIssue: Codable, Sendable, Equatable, Identifiable {
    public var code: String; public var message: String; public var operationID: String?; public var repairable: Bool; public var id: String { "\(code):\(operationID ?? "run")" }
    public init(code: String, message: String, operationID: String? = nil, repairable: Bool) { self.code = code; self.message = message; self.operationID = operationID; self.repairable = repairable }
}
public struct CloudKnowledgeValidationResult: Codable, Sendable, Equatable {
    public var valid: Bool; public var issues: [CloudKnowledgeValidationIssue]; public var stagedSequence: Int
    public init(valid: Bool, issues: [CloudKnowledgeValidationIssue], stagedSequence: Int) { self.valid = valid; self.issues = issues; self.stagedSequence = stagedSequence }
}
public struct CloudKnowledgeCommitResult: Codable, Sendable, Equatable {
    public var publicationRunID: String; public var knowledgeSequence: Int; public var indexedSequence: Int?
    public init(publicationRunID: String, knowledgeSequence: Int, indexedSequence: Int? = nil) { self.publicationRunID = publicationRunID; self.knowledgeSequence = knowledgeSequence; self.indexedSequence = indexedSequence }
}
public struct CloudKnowledgeRebaseRequest: Codable, Sendable, Equatable { public var expectedBaseSequence: Int; public init(expectedBaseSequence: Int) { self.expectedBaseSequence = expectedBaseSequence } }

public struct CloudKnowledgePublishingContext: Sendable, Equatable {
    public var knowledgeBaseID: String; public var publicationRunID: String; public var ownerUserID: String; public var clientRunID: String; public var schemaVersion: String
    public init(knowledgeBaseID: String, publicationRunID: String, ownerUserID: String, clientRunID: String, schemaVersion: String = "v2") { self.knowledgeBaseID = knowledgeBaseID; self.publicationRunID = publicationRunID; self.ownerUserID = ownerUserID; self.clientRunID = clientRunID; self.schemaVersion = schemaVersion }
}

public enum CloudKnowledgeError: Error, Sendable, Equatable, LocalizedError {
    case invalidResponse, unauthorized, server(status: Int, code: String?, message: String), publicationConflict(currentSequence: Int?), searchBeforeWriteRequired, searchContextNotRelevant, searchContextStale, cancelled
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "云端知识服务返回了无法识别的数据。"
        case .unauthorized: "登录已失效，请重新登录。"
        case .server(_, _, let message): message
        case .publicationConflict: "知识库已发生变化，需要重新检索并 rebase。"
        case .searchBeforeWriteRequired: "写入前必须先搜索目标知识层。"
        case .searchContextNotRelevant: "搜索上下文没有覆盖本次知识写入。"
        case .searchContextStale: "搜索上下文已过期，请重新搜索。"
        case .cancelled: "发布已取消。"
        }
    }
}
