import Foundation
import ConnorGraphCore

enum PersonRelationshipTargetMode: String, CaseIterable, Identifiable {
    case personProfile
    case currentUser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personProfile: "现有人物"
        case .currentUser: "当前用户"
        }
    }
}

enum PersonRelationshipDraftError: Error, Equatable {
    case missingTargetPerson
    case selfRelationship
}

struct PersonRelationshipDraft: Equatable {
    var id: String?
    var sourcePersonID: ContactID
    var targetMode: PersonRelationshipTargetMode = .personProfile
    var targetPersonID: ContactID?
    var kind: PersonRelationshipKind = .knows
    var customKindLabel: String = ""
    var note: String = ""
    var evidenceText: String = ""

    init(sourcePersonID: ContactID) {
        self.sourcePersonID = sourcePersonID
    }

    func makeRelationship(now: Date = Date()) throws -> PersonRelationship {
        let target: PersonRelationshipEndpoint
        switch targetMode {
        case .personProfile:
            guard let targetPersonID else { throw PersonRelationshipDraftError.missingTargetPerson }
            guard targetPersonID != sourcePersonID else { throw PersonRelationshipDraftError.selfRelationship }
            target = .personProfile(targetPersonID)
        case .currentUser:
            target = .currentUser()
        }

        return PersonRelationship(
            id: id ?? "relationship-\(UUID().uuidString)",
            source: .personProfile(sourcePersonID),
            target: target,
            kind: kind,
            customKindLabel: trimmedOptional(customKindLabel),
            note: trimmedOptional(note),
            evidenceText: trimmedOptional(evidenceText),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
