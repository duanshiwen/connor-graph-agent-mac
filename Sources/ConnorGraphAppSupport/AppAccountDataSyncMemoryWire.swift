import Foundation
import ConnorGraphCore

// MARK: - Memory OS L2/L3/L4 账号同步载荷（wire 与 Android Room 实体逐字段一致）

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
    }

    func makeEntity() -> MemoryOSEntity {
        MemoryOSEntity(
            id: id,
            stableKey: stableKey,
            entityType: type,
            name: name,
            aliases: [],
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
    var metadataJson: String

    init(_ relation: MemoryOSEntityStatement) {
        id = relation.id
        subjectId = relation.entityID
        predicate = relation.predicate.rawValue
        objectId = relation.objectEntityID
        acceptance = "strict"
        confidence = relation.confidence
        createdAt = syncISOString(relation.committedAt)
        var metadata = relation.metadata
        metadata["text"] = relation.text
        metadata["assertion_kind"] = relation.assertionKind.rawValue
        if !relation.evidenceSpanIDs.isEmpty {
            metadata["evidence_span_ids"] = syncJSONString(relation.evidenceSpanIDs)
        }
        if let source = relation.sourceArtifactID {
            metadata["source_artifact_id"] = source
        }
        metadata["valid_at"] = syncISOString(relation.validAt)
        metadata["raw_predicate"] = relation.predicate.rawValue
        metadata["acceptance"] = "strict"
        metadataJson = syncJSONString(metadata)
    }

    func makeEntityStatement() -> MemoryOSEntityStatement {
        var metadata = syncJSONDictionary(metadataJson)
        let text = metadata.removeValue(forKey: "text") ?? ""
        let assertionKind = MemoryOSAssertionKind(rawValue: metadata.removeValue(forKey: "assertion_kind") ?? "observed") ?? .observed
        let evidenceSpanIDs = syncJSONArray(metadata.removeValue(forKey: "evidence_span_ids") ?? "[]")
        let sourceArtifactID = metadata.removeValue(forKey: "source_artifact_id")
        let validAtString = metadata.removeValue(forKey: "valid_at")
        metadata.removeValue(forKey: "raw_predicate")
        metadata.removeValue(forKey: "acceptance")
        let committedAt = syncDate(createdAt) ?? Date()
        return MemoryOSEntityStatement(
            id: id,
            entityID: subjectId,
            predicate: MemoryOSL4RelationPredicate(rawValue: predicate) ?? .relatedTo,
            objectEntityID: objectId,
            text: text,
            assertionKind: assertionKind,
            confidence: confidence,
            validAt: syncDate(validAtString) ?? committedAt,
            committedAt: committedAt,
            evidenceSpanIDs: evidenceSpanIDs,
            sourceArtifactID: sourceArtifactID,
            metadata: metadata
        )
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
