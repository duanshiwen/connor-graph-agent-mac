import Foundation

public struct NativeSourceReference: Codable, Sendable, Equatable, Identifiable {
    public enum SourceKind: String, Codable, Sendable, Equatable, CaseIterable {
        case mail
        case calendar
        case rss
        case browserHistory = "browser_history"
    }

    public enum ReferenceStrength: String, Codable, Sendable, Equatable, CaseIterable {
        case summaryCandidate = "summary_candidate"
        case detailRead = "detail_read"
        case fullEventResult = "full_event_result"
    }

    public var id: String { deduplicationKey }
    public var sourceKind: SourceKind
    public var sourceRecordID: String
    public var title: String
    public var content: String
    public var occurredAt: Date
    public var accountID: String?
    public var sessionID: String?
    public var url: String?
    public var referenceStrength: ReferenceStrength
    public var toolName: String
    public var toolCallID: String
    public var runID: String
    public var query: String?
    public var metadata: [String: String]

    public init(
        sourceKind: SourceKind,
        sourceRecordID: String,
        title: String,
        content: String,
        occurredAt: Date,
        accountID: String? = nil,
        sessionID: String? = nil,
        url: String? = nil,
        referenceStrength: ReferenceStrength,
        toolName: String,
        toolCallID: String,
        runID: String,
        query: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sourceKind = sourceKind
        self.sourceRecordID = sourceRecordID
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.accountID = accountID
        self.sessionID = sessionID
        self.url = url
        self.referenceStrength = referenceStrength
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.runID = runID
        self.query = query
        self.metadata = metadata
    }

    public var deduplicationKey: String {
        [
            "native-ref",
            sourceKind.rawValue,
            sourceRecordID,
            referenceStrength.rawValue,
            stableContentFingerprint
        ].map(Self.sanitizeKeyComponent).joined(separator: ":")
    }

    public var baseMetadata: [String: String] {
        var values = metadata
        values["native_source_kind"] = sourceKind.rawValue
        values["native_source_record_id"] = sourceRecordID
        values["reference_strength"] = referenceStrength.rawValue
        values["tool_name"] = toolName
        values["tool_call_id"] = toolCallID
        values["run_id"] = runID
        values["deduplication_key"] = deduplicationKey
        if let query { values["query"] = query }
        if let url { values["url"] = url }
        return values
    }

    private var stableContentFingerprint: String {
        Self.fnv1a64Hex([
            title,
            content,
            url ?? "",
            query ?? ""
        ].joined(separator: "\n"))
    }

    private static func sanitizeKeyComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}

public protocol NativeSourceReferenceRecording: Sendable {
    func record(_ references: [NativeSourceReference]) async
}

public struct NoopNativeSourceReferenceRecorder: NativeSourceReferenceRecording {
    public init() {}
    public func record(_ references: [NativeSourceReference]) async {}
}
