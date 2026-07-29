import Foundation

public struct MemoryOSPreferenceWatermark: Codable, Sendable, Equatable {
    public var committedAt: Date
    public var statementID: String

    public init(committedAt: Date, statementID: String) {
        self.committedAt = committedAt
        self.statementID = statementID
    }
}

public struct MemoryOSPreferenceCompactionSourceRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var statement: String
    public var predicate: String
    public var confidence: Double
    public var committedAt: Date
    public var metadata: [String: String]

    public init(id: String, statement: String, predicate: String, confidence: Double, committedAt: Date, metadata: [String: String] = [:]) {
        self.id = id
        self.statement = statement
        self.predicate = predicate
        self.confidence = confidence
        self.committedAt = committedAt
        self.metadata = metadata
    }
}

public struct MemoryOSCanonicalPreferenceItem: Codable, Sendable, Equatable {
    public var key: String
    public var statement: String
    public var scope: String
    public var confidence: Double
    public var effectiveAt: String?
    public var supportingRecordIDs: [String]
    public var supersededRecordIDs: [String]
    public var exactLiterals: [String]

    public init(key: String, statement: String, scope: String = "general", confidence: Double = 0.9, effectiveAt: String? = nil, supportingRecordIDs: [String] = [], supersededRecordIDs: [String] = [], exactLiterals: [String] = []) {
        self.key = key
        self.statement = statement
        self.scope = scope
        self.confidence = confidence
        self.effectiveAt = effectiveAt
        self.supportingRecordIDs = supportingRecordIDs
        self.supersededRecordIDs = supersededRecordIDs
        self.exactLiterals = exactLiterals
    }
}

public enum MemoryOSPreferenceSourceDispositionAction: String, Codable, Sendable, Equatable, CaseIterable {
    case active
    case merged
    case superseded
    case rejected
}

public struct MemoryOSPreferenceSourceDisposition: Codable, Sendable, Equatable {
    public var recordID: String
    public var action: MemoryOSPreferenceSourceDispositionAction
    public var itemKey: String?
    public var reason: String

    public init(recordID: String, action: MemoryOSPreferenceSourceDispositionAction, itemKey: String? = nil, reason: String = "") {
        self.recordID = recordID
        self.action = action
        self.itemKey = itemKey
        self.reason = reason
    }
}

public struct MemoryOSPreferenceCompactionOutput: Codable, Sendable, Equatable {
    public var items: [MemoryOSCanonicalPreferenceItem]
    public var sourceDispositions: [MemoryOSPreferenceSourceDisposition]
    public var retiredItemKeys: [String]

    public init(items: [MemoryOSCanonicalPreferenceItem], sourceDispositions: [MemoryOSPreferenceSourceDisposition], retiredItemKeys: [String] = []) {
        self.items = items
        self.sourceDispositions = sourceDispositions
        self.retiredItemKeys = retiredItemKeys
    }
}

public struct MemoryOSPreferenceCompactionSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var baseSnapshotID: String?
    public var watermark: MemoryOSPreferenceWatermark
    public var profile: MemoryOSPreferenceCompactionOutput
    public var renderedText: String
    public var sourceRecordCount: Int
    public var modelID: String?
    public var createdAt: Date
    public var publishedAt: Date?
    public var metadata: [String: String]

    public init(id: String, baseSnapshotID: String? = nil, watermark: MemoryOSPreferenceWatermark, profile: MemoryOSPreferenceCompactionOutput, renderedText: String, sourceRecordCount: Int, modelID: String? = nil, createdAt: Date = Date(), publishedAt: Date? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.baseSnapshotID = baseSnapshotID
        self.watermark = watermark
        self.profile = profile
        self.renderedText = renderedText
        self.sourceRecordCount = sourceRecordCount
        self.modelID = modelID
        self.createdAt = createdAt
        self.publishedAt = publishedAt
        self.metadata = metadata
    }
}

public enum MemoryOSCurrentUserProfileView: String, Codable, Sendable, Equatable, CaseIterable {
    case compressed
    case raw
}

public enum MemoryOSPreferenceCompactionRenderer {
    public static func render(_ output: MemoryOSPreferenceCompactionOutput) -> String {
        let text = output.items
            .sorted { lhs, rhs in
                if lhs.scope != rhs.scope { return lhs.scope < rhs.scope }
                return lhs.key < rhs.key
            }
            .map { item in
                let scope = item.scope == "general" || item.scope.isEmpty ? "" : " [\(item.scope)]"
                return "- \(item.statement)\(scope)"
            }
            .joined(separator: "\n")
        return text.isEmpty ? "No active user preferences are currently recorded." : text
    }
}

public struct MemoryOSPreferenceCompactionJobDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var baseSnapshotID: String?
    public var previousProfile: MemoryOSPreferenceCompactionOutput
    public var previousSourceRecordCount: Int
    public var records: [MemoryOSPreferenceCompactionSourceRecord]
    public var targetWatermark: MemoryOSPreferenceWatermark
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, baseSnapshotID: String? = nil, previousProfile: MemoryOSPreferenceCompactionOutput = .init(items: [], sourceDispositions: []), previousSourceRecordCount: Int = 0, records: [MemoryOSPreferenceCompactionSourceRecord], targetWatermark: MemoryOSPreferenceWatermark, createdAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id
        self.kind = MemoryOSBackgroundJobKind.preferenceCompaction.rawValue
        self.baseSnapshotID = baseSnapshotID
        self.previousProfile = previousProfile
        self.previousSourceRecordCount = previousSourceRecordCount
        self.records = records
        self.targetWatermark = targetWatermark
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public enum MemoryOSPreferenceCompactionValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidJSON
    case emptyItem(String)
    case duplicateItemKey(String)
    case invalidSourceDisposition
    case missingSourceDisposition(String)
    case unknownSourceRecord(String)
    case missingPreviousItemDisposition(String)
    case unknownRetiredItem(String)

    public var description: String {
        switch self {
        case .invalidJSON: "Preference compaction output is not valid JSON."
        case .emptyItem(let key): "Preference item is incomplete: \(key)"
        case .duplicateItemKey(let key): "Duplicate preference item key: \(key)"
        case .invalidSourceDisposition: "Every new source record must have exactly one disposition."
        case .missingSourceDisposition(let id): "Missing disposition for source record: \(id)"
        case .unknownSourceRecord(let id): "Unknown source record referenced by compaction output: \(id)"
        case .missingPreviousItemDisposition(let key): "Previous preference item was neither retained nor retired: \(key)"
        case .unknownRetiredItem(let key): "Unknown retired preference item: \(key)"
        }
    }
}

public struct MemoryOSPreferenceCompactionValidator: Sendable {
    public init() {}

    public func decodeAndValidate(rawJSON: String, draft: MemoryOSPreferenceCompactionJobDraft) throws -> MemoryOSPreferenceCompactionOutput {
        let json = Self.extractJSONObject(rawJSON)
        guard let data = json.data(using: .utf8),
              let output = try? JSONDecoder().decode(MemoryOSPreferenceCompactionOutput.self, from: data)
        else { throw MemoryOSPreferenceCompactionValidationError.invalidJSON }
        try validate(output, draft: draft)
        return output
    }

    public func validate(_ output: MemoryOSPreferenceCompactionOutput, draft: MemoryOSPreferenceCompactionJobDraft) throws {
        let outputKeys = output.items.map(\.key)
        guard Set(outputKeys).count == outputKeys.count else {
            let duplicate = outputKeys.first { key in outputKeys.filter { $0 == key }.count > 1 } ?? "unknown"
            throw MemoryOSPreferenceCompactionValidationError.duplicateItemKey(duplicate)
        }
        for item in output.items {
            let isRetainedPreviousItem = draft.previousProfile.items.contains { $0.key == item.key }
            guard !item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  isRetainedPreviousItem || !(item.supportingRecordIDs + item.supersededRecordIDs).isEmpty
            else { throw MemoryOSPreferenceCompactionValidationError.emptyItem(item.key) }
        }

        let newIDs = Set(draft.records.map(\.id))
        let dispositionIDs = output.sourceDispositions.map(\.recordID)
        guard Set(dispositionIDs).count == dispositionIDs.count else {
            throw MemoryOSPreferenceCompactionValidationError.invalidSourceDisposition
        }
        for id in newIDs where !dispositionIDs.contains(id) {
            throw MemoryOSPreferenceCompactionValidationError.missingSourceDisposition(id)
        }
        guard Set(dispositionIDs) == newIDs else {
            let unknown = Set(dispositionIDs).subtracting(newIDs).first ?? "unknown"
            throw MemoryOSPreferenceCompactionValidationError.unknownSourceRecord(unknown)
        }

        let previousIDs = Set(draft.previousProfile.items.flatMap { $0.supportingRecordIDs + $0.supersededRecordIDs })
        let knownIDs = newIDs.union(previousIDs)
        for id in output.items.flatMap({ $0.supportingRecordIDs + $0.supersededRecordIDs }) where !knownIDs.contains(id) {
            throw MemoryOSPreferenceCompactionValidationError.unknownSourceRecord(id)
        }

        let previousKeys = Set(draft.previousProfile.items.map(\.key))
        let retainedKeys = Set(outputKeys)
        let retiredKeys = Set(output.retiredItemKeys)
        for key in retiredKeys where !previousKeys.contains(key) {
            throw MemoryOSPreferenceCompactionValidationError.unknownRetiredItem(key)
        }
        for key in previousKeys where !retainedKeys.contains(key) && !retiredKeys.contains(key) {
            throw MemoryOSPreferenceCompactionValidationError.missingPreviousItemDisposition(key)
        }
    }

    private static func extractJSONObject(_ raw: String) -> String {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start <= end else { return raw }
        return String(raw[start...end])
    }
}

public struct MemoryOSPreferenceCompactionWorker<Executor: MemoryOSBackgroundModelExecutor>: Sendable {
    public var executor: Executor

    public init(executor: Executor) {
        self.executor = executor
    }

    public func run(_ draft: MemoryOSPreferenceCompactionJobDraft) throws -> MemoryOSBackgroundJobExecutionResult {
        let request = MemoryOSBackgroundModelRequest(
            jobID: draft.id,
            kind: draft.kind,
            schemaName: "MemoryOSPreferenceCompactionOutput",
            artifactType: "memory_os_preference_compaction",
            prompt: try prompt(for: draft),
            sourceRecordIDs: draft.records.map(\.id),
            metadata: draft.metadata,
            availableTools: []
        )
        let response = try executor.execute(request)
        return MemoryOSBackgroundJobExecutionResult(
            jobID: draft.id,
            kind: draft.kind,
            rawArtifactJSON: response.rawArtifactJSON,
            schemaName: request.schemaName,
            artifactType: request.artifactType,
            metadata: draft.metadata.merging(response.metadata) { _, new in new }
        )
    }

    private func prompt(for draft: MemoryOSPreferenceCompactionJobDraft) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let promptProfile = MemoryOSPreferenceCompactionOutput(
            items: draft.previousProfile.items.map { item in
                var compactItem = item
                compactItem.supportingRecordIDs = []
                compactItem.supersededRecordIDs = []
                return compactItem
            },
            sourceDispositions: [],
            retiredItemKeys: []
        )
        let previous = String(decoding: try encoder.encode(promptProfile), as: UTF8.self)
        let records = String(decoding: try encoder.encode(draft.records), as: UTF8.self)
        return """
        Compact the current user's preference memory into one canonical structured profile.

        Requirements:
        - Preserve every operationally meaningful preference, constraint, scope, exception, exact number, date, name, path, URL, language choice, and explicit negation.
        - Deduplicate semantically equivalent records.
        - A newer record supersedes an older preference only when it explicitly denies, replaces, or is incompatible in the same scope. Different scopes may coexist.
        - Explicit user statements outrank behavioral inferences. Do not invent preferences.
        - Keep statements concise without changing their meaning.
        - Every new source record must appear exactly once in sourceDispositions.
        - Every previous item key must either remain in items or appear in retiredItemKeys.
        - New or changed items must cite real IDs from the new records. Unchanged previous items may keep both source ID arrays empty; the runtime restores their historical provenance after validation.
        - Return only one JSON object. Do not use Markdown fences and do not add commentary.

        Output schema:
        {
          "items": [{
            "key": "stable.domain.key",
            "statement": "canonical preference statement",
            "scope": "general or a specific scope",
            "confidence": 0.9,
            "effectiveAt": null,
            "supportingRecordIDs": ["record-id"],
            "supersededRecordIDs": [],
            "exactLiterals": []
          }],
          "sourceDispositions": [{
            "recordID": "new-record-id",
            "action": "active|merged|superseded|rejected",
            "itemKey": "stable.domain.key or null",
            "reason": "brief reason"
          }],
          "retiredItemKeys": []
        }

        Previous canonical profile:
        \(previous)

        New immutable preference records, in chronological order:
        \(records)
        """
    }
}
