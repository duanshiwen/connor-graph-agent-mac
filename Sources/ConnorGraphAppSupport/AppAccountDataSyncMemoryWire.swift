import Foundation
import ConnorGraphCore

// MARK: - Memory OS L2/L3/L4 账号同步载荷（wire 与 Android Room 实体逐字段一致）

// MARK: - 康纳同学的性格（settings|personality，与 Android PersonalityState 逐字段一致）

struct SyncPersonality: Codable, Sendable {
    struct Profile: Codable, Sendable {
        var gender: String
        var summary: String
        var traits: [String]
        var communicationStyle: String
        var reasoningStyle: String
        var initiativeStyle: String
        var emotionalTone: String
        var boundaries: [String]
    }

    var name: String?
    var persona: String?
    var profile: Profile?
    var revision: Int?
    /// 人格“最后设置时间”（epoch 毫秒）；旧载荷可能缺失，按 0（从未设置）处理。
    var updatedAt: Int64?

    init(_ settings: AgentRuntimeSettings) {
        let p = settings.preferences.connorPersonality
        name = "康纳同学"
        persona = ""
        profile = Profile(
            gender: p.gender,
            summary: p.summary,
            traits: p.traits,
            communicationStyle: p.communicationStyle,
            reasoningStyle: p.reasoningStyle,
            initiativeStyle: p.initiativeStyle,
            emotionalTone: p.emotionalTone,
            boundaries: p.boundaries
        )
        revision = settings.preferences.connorPersonalityRevision
        updatedAt = Int64(settings.preferences.connorPersonalityUpdatedAt.timeIntervalSince1970 * 1_000)
    }

    func connorPersonality() -> ConnorPersonalitySettings {
        let p = profile ?? Profile(gender: "", summary: "", traits: [], communicationStyle: "", reasoningStyle: "", initiativeStyle: "", emotionalTone: "", boundaries: [])
        return ConnorPersonalitySettings(
            gender: p.gender,
            summary: p.summary,
            traits: p.traits,
            communicationStyle: p.communicationStyle,
            reasoningStyle: p.reasoningStyle,
            initiativeStyle: p.initiativeStyle,
            emotionalTone: p.emotionalTone,
            boundaries: p.boundaries
        )
    }
}

struct SyncMemoryL2Node: Codable, Sendable {
    var id: String
    var stableKey: String
    var nodeType: String
    var name: String
    var summary: String
    var createdAt: String
    var updatedAt: String
    var metadataJson: String

    init(_ node: MemoryOSNode) {
        id = node.id
        stableKey = node.stableKey
        nodeType = node.nodeType
        name = node.name
        summary = node.summary
        createdAt = syncISOString(node.createdAt)
        updatedAt = syncISOString(node.updatedAt)
        metadataJson = syncJSONString(node.metadata)
    }

    func makeNode() -> MemoryOSNode {
        MemoryOSNode(
            id: id,
            stableKey: stableKey,
            nodeType: nodeType,
            name: name,
            summary: summary,
            createdAt: syncDate(createdAt) ?? Date(),
            updatedAt: syncDate(updatedAt) ?? Date(),
            metadata: syncJSONDictionary(metadataJson)
        )
    }
}

struct SyncMemoryL2Statement: Codable, Sendable {
    var id: String
    var subjectId: String
    var predicate: String
    var objectId: String?
    var text: String
    var factType: String?
    var assertionKind: String
    var confidence: Double
    var validAt: String?
    var committedAt: String
    var evidenceSpanIdsJson: String
    var sourceArtifactId: String?
    var metadataJson: String

    enum CodingKeys: String, CodingKey {
        case id, subjectId, predicate, objectId, text, factType, assertionKind, confidence
        case validAt, committedAt, evidenceSpanIdsJson, sourceArtifactId, metadataJson
    }

    init(_ statement: MemoryOSStatement) {
        id = statement.id
        subjectId = statement.subjectID
        predicate = statement.predicate
        objectId = statement.objectID
        text = statement.text
        factType = "other"
        assertionKind = statement.assertionKind.rawValue
        confidence = statement.confidence
        validAt = syncISOString(statement.validAt)
        committedAt = syncISOString(statement.committedAt)
        evidenceSpanIdsJson = syncJSONString(statement.evidenceSpanIDs)
        sourceArtifactId = statement.sourceArtifactID
        metadataJson = syncJSONString(statement.metadata)
    }

    func makeStatement() -> MemoryOSStatement {
        let committedAt = syncDate(committedAt) ?? Date()
        return MemoryOSStatement(
            id: id,
            subjectID: subjectId,
            predicate: predicate,
            objectID: objectId,
            text: text,
            assertionKind: MemoryOSAssertionKind(rawValue: assertionKind) ?? .observed,
            confidence: confidence,
            validAt: syncDate(validAt) ?? committedAt,
            committedAt: committedAt,
            evidenceSpanIDs: syncJSONArray(evidenceSpanIdsJson),
            sourceArtifactID: sourceArtifactId,
            metadata: syncJSONDictionary(metadataJson)
        )
    }

    /// JSONEncoder 默认会省略 nil 可选字段，导致安卓端把缺字段当成“必填缺失”报错。
    /// 这里把可选字段显式编码为 null，保证两端 wire 载荷字段齐全。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subjectId, forKey: .subjectId)
        try container.encode(predicate, forKey: .predicate)
        try syncEncodeOptional(objectId, forKey: .objectId, in: &container)
        try container.encode(text, forKey: .text)
        try syncEncodeOptional(factType, forKey: .factType, in: &container)
        try container.encode(assertionKind, forKey: .assertionKind)
        try container.encode(confidence, forKey: .confidence)
        try syncEncodeOptional(validAt, forKey: .validAt, in: &container)
        try container.encode(committedAt, forKey: .committedAt)
        try container.encode(evidenceSpanIdsJson, forKey: .evidenceSpanIdsJson)
        try syncEncodeOptional(sourceArtifactId, forKey: .sourceArtifactId, in: &container)
        try container.encode(metadataJson, forKey: .metadataJson)
    }
}

struct SyncMemoryL3Belief: Codable, Sendable {
    var id: String
    var statement: String
    var domain: String
    var relatedObjectNamesJson: String
    var createdAt: String
    var updatedAt: String

    init(_ belief: MemoryOSBelief) {
        id = belief.id
        statement = belief.statement
        domain = belief.domain
        relatedObjectNamesJson = syncJSONString(
            belief.relatedObjectNames
                .components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        createdAt = syncISOString(belief.createdAt)
        updatedAt = syncISOString(belief.updatedAt)
    }

    func makeBelief() -> MemoryOSBelief {
        MemoryOSBelief(
            id: id,
            statement: statement,
            domain: domain,
            relatedObjectNames: syncJSONArray(relatedObjectNamesJson).joined(separator: ", "),
            createdAt: syncDate(createdAt) ?? Date(),
            updatedAt: syncDate(updatedAt) ?? Date()
        )
    }
}

struct SyncMemoryL4Entity: Codable, Sendable {
    var id: String
    var stableKey: String
    var type: String
    var name: String
    var summary: String
    var confidence: Double
    var createdAt: String
    var updatedAt: String
    var metadataJson: String
    var aliasesJson: String?

    init(_ entity: MemoryOSEntity) {
        id = entity.id
        stableKey = entity.stableKey
        type = entity.entityType
        name = entity.name
        summary = entity.summary
        confidence = entity.confidence
        createdAt = syncISOString(entity.createdAt)
        updatedAt = syncISOString(entity.updatedAt)
        metadataJson = syncJSONString(entity.metadata)
        aliasesJson = syncJSONString(entity.aliases)
    }

    func makeEntity() -> MemoryOSEntity {
        MemoryOSEntity(
            id: id,
            stableKey: stableKey,
            entityType: type,
            name: name,
            aliases: syncJSONArray(aliasesJson ?? "[]"),
            summary: summary,
            confidence: confidence,
            createdAt: syncDate(createdAt) ?? Date(),
            updatedAt: syncDate(updatedAt) ?? Date(),
            validFrom: nil,
            metadata: syncJSONDictionary(metadataJson)
        )
    }
}

struct SyncMemoryL4Relation: Codable, Sendable {
    var id: String
    var subjectId: String
    var predicate: String
    var objectId: String?
    var acceptance: String?
    var confidence: Double
    var createdAt: String
    var text: String?
    var assertionKind: String?
    var validAt: String?
    var committedAt: String?
    var evidenceSpanIdsJson: String?
    var sourceArtifactId: String?
    var metadataJson: String

    enum CodingKeys: String, CodingKey {
        case id, subjectId, predicate, objectId, acceptance, confidence, createdAt
        case text, assertionKind, validAt, committedAt, evidenceSpanIdsJson, sourceArtifactId, metadataJson
    }

    init(_ relation: MemoryOSEntityStatement) {
        id = relation.id
        subjectId = relation.entityID
        predicate = relation.predicate.rawValue
        objectId = relation.objectEntityID
        acceptance = "strict"
        confidence = relation.confidence
        createdAt = syncISOString(relation.committedAt)
        text = relation.text
        assertionKind = relation.assertionKind.rawValue
        validAt = syncISOString(relation.validAt)
        committedAt = syncISOString(relation.committedAt)
        evidenceSpanIdsJson = syncJSONString(relation.evidenceSpanIDs)
        sourceArtifactId = relation.sourceArtifactID
        metadataJson = syncJSONString(relation.metadata)
    }

    func makeEntityStatement() -> MemoryOSEntityStatement {
        let committedAt = syncDate(committedAt) ?? syncDate(createdAt) ?? Date()
        return MemoryOSEntityStatement(
            id: id,
            entityID: subjectId,
            predicate: MemoryOSL4RelationPredicate(rawValue: predicate) ?? .relatedTo,
            objectEntityID: objectId,
            text: text ?? "",
            assertionKind: MemoryOSAssertionKind(rawValue: assertionKind ?? "observed") ?? .observed,
            confidence: confidence,
            validAt: syncDate(validAt) ?? committedAt,
            committedAt: committedAt,
            evidenceSpanIDs: syncJSONArray(evidenceSpanIdsJson ?? "[]"),
            sourceArtifactID: sourceArtifactId,
            metadata: syncJSONDictionary(metadataJson)
        )
    }

    /// 同上：nil 可选字段显式编码为 null，避免安卓端缺字段报错。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subjectId, forKey: .subjectId)
        try container.encode(predicate, forKey: .predicate)
        try syncEncodeOptional(objectId, forKey: .objectId, in: &container)
        try syncEncodeOptional(acceptance, forKey: .acceptance, in: &container)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(createdAt, forKey: .createdAt)
        try syncEncodeOptional(text, forKey: .text, in: &container)
        try syncEncodeOptional(assertionKind, forKey: .assertionKind, in: &container)
        try syncEncodeOptional(validAt, forKey: .validAt, in: &container)
        try syncEncodeOptional(committedAt, forKey: .committedAt, in: &container)
        try syncEncodeOptional(evidenceSpanIdsJson, forKey: .evidenceSpanIdsJson, in: &container)
        try syncEncodeOptional(sourceArtifactId, forKey: .sourceArtifactId, in: &container)
        try container.encode(metadataJson, forKey: .metadataJson)
    }
}

private func syncEncodeOptional<T: Encodable, Key: CodingKey>(
    _ value: T?,
    forKey key: Key,
    in container: inout KeyedEncodingContainer<Key>
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}

func syncISOString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func syncDate(_ string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) { return date }
    return ISO8601DateFormatter().date(from: string)
}

func syncJSONString(_ values: [String]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return "[]" }
    return String(data: data, encoding: .utf8) ?? "[]"
}

func syncJSONString(_ values: [String: String]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return "{}" }
    return String(data: data, encoding: .utf8) ?? "{}"
}

func syncJSONArray(_ string: String) -> [String] {
    guard let data = string.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
    return array
}

func syncJSONDictionary(_ string: String) -> [String: String] {
    guard let data = string.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
    return object
}
