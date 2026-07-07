import Foundation

public enum PersonRelationshipEndpointKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case personProfile
    case currentUser
}

public struct PersonRelationshipEndpoint: Codable, Sendable, Equatable, Hashable {
    public static let currentUserProtectedIdentityAnchor = "current_user"
    public static let currentUserMemoryEntityID = "l4-entity:current_user"
    public static let currentUserMemoryStableKey = "current_user"

    public var kind: PersonRelationshipEndpointKind
    public var personID: ContactID?
    public var protectedIdentityAnchor: String?
    public var memoryEntityID: String?
    public var memoryStableKey: String?

    public init(
        kind: PersonRelationshipEndpointKind,
        personID: ContactID? = nil,
        protectedIdentityAnchor: String? = nil,
        memoryEntityID: String? = nil,
        memoryStableKey: String? = nil
    ) {
        self.kind = kind
        self.personID = personID
        self.protectedIdentityAnchor = protectedIdentityAnchor
        self.memoryEntityID = memoryEntityID
        self.memoryStableKey = memoryStableKey
    }

    public static func personProfile(
        _ personID: ContactID,
        memoryEntityID: String? = nil,
        memoryStableKey: String? = nil
    ) -> PersonRelationshipEndpoint {
        PersonRelationshipEndpoint(
            kind: .personProfile,
            personID: personID,
            protectedIdentityAnchor: nil,
            memoryEntityID: memoryEntityID,
            memoryStableKey: memoryStableKey
        )
    }

    public static func currentUser() -> PersonRelationshipEndpoint {
        PersonRelationshipEndpoint(
            kind: .currentUser,
            personID: nil,
            protectedIdentityAnchor: currentUserProtectedIdentityAnchor,
            memoryEntityID: currentUserMemoryEntityID,
            memoryStableKey: currentUserMemoryStableKey
        )
    }

    public var isCurrentUser: Bool {
        kind == .currentUser
            || protectedIdentityAnchor == Self.currentUserProtectedIdentityAnchor
            || memoryStableKey == Self.currentUserMemoryStableKey
            || memoryEntityID == Self.currentUserMemoryEntityID
    }

    public var fallbackDisplayTitle: String {
        if isCurrentUser { return "我（当前用户）" }
        if let personID { return personID.rawValue }
        return "未知人物"
    }
}

public enum PersonRelationshipKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case parentOf
    case childOf
    case spouseOf
    case partnerOf
    case siblingOf
    case friendOf
    case colleagueOf
    case managerOf
    case reportsTo
    case relativeOf
    case knows
    case custom

    public var displayTitle: String {
        switch self {
        case .parentOf: return "父母"
        case .childOf: return "子女"
        case .spouseOf: return "配偶"
        case .partnerOf: return "伴侣"
        case .siblingOf: return "兄弟姐妹"
        case .friendOf: return "朋友"
        case .colleagueOf: return "同事"
        case .managerOf: return "上级"
        case .reportsTo: return "汇报给"
        case .relativeOf: return "亲属"
        case .knows: return "认识"
        case .custom: return "关系"
        }
    }
}

public enum PersonRelationshipStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case active
    case pending
    case archived
    case deleted
}

public struct PersonRelationship: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var source: PersonRelationshipEndpoint
    public var target: PersonRelationshipEndpoint
    public var kind: PersonRelationshipKind
    public var customKindLabel: String?
    public var note: String?
    public var evidenceText: String?
    public var confidence: Double?
    public var status: PersonRelationshipStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = "relationship-\(UUID().uuidString)",
        source: PersonRelationshipEndpoint,
        target: PersonRelationshipEndpoint,
        kind: PersonRelationshipKind,
        customKindLabel: String? = nil,
        note: String? = nil,
        evidenceText: String? = nil,
        confidence: Double? = nil,
        status: PersonRelationshipStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.kind = kind
        self.customKindLabel = customKindLabel
        self.note = note
        self.evidenceText = evidenceText
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayKindTitle: String {
        let trimmedCustomLabel = customKindLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedCustomLabel.isEmpty ? kind.displayTitle : trimmedCustomLabel
    }
}

public extension Array where Element == PersonRelationship {
    func upserting(_ relationship: PersonRelationship) -> [PersonRelationship] {
        var copy = filter { $0.id != relationship.id }
        copy.append(relationship)
        return copy.sorted { first, second in
            if first.updatedAt != second.updatedAt { return first.updatedAt > second.updatedAt }
            return first.id.localizedStandardCompare(second.id) == .orderedAscending
        }
    }
}
