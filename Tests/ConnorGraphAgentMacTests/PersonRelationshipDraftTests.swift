import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@MainActor
struct PersonRelationshipDraftTests {
    @Test func draftBuildsRelationshipToCurrentUser() throws {
        let sourceID = ContactID(rawValue: "person-zhang-xia")
        var draft = PersonRelationshipDraft(sourcePersonID: sourceID)
        draft.targetMode = .currentUser
        draft.kind = .parentOf
        draft.customKindLabel = "妈妈"
        draft.note = "家庭关系"

        let relationship = try draft.makeRelationship(now: Date(timeIntervalSince1970: 100))

        #expect(relationship.source == .personProfile(sourceID))
        #expect(relationship.target == .currentUser())
        #expect(relationship.kind == .parentOf)
        #expect(relationship.customKindLabel == "妈妈")
        #expect(relationship.note == "家庭关系")
        #expect(relationship.createdAt == Date(timeIntervalSince1970: 100))
    }

    @Test func draftBuildsRelationshipToSelectedPerson() throws {
        let sourceID = ContactID(rawValue: "person-zhang-xia")
        let targetID = ContactID(rawValue: "person-duan-fuqiang")
        var draft = PersonRelationshipDraft(sourcePersonID: sourceID)
        draft.targetMode = .personProfile
        draft.targetPersonID = targetID
        draft.kind = .parentOf

        let relationship = try draft.makeRelationship(now: Date(timeIntervalSince1970: 100))

        #expect(relationship.source == .personProfile(sourceID))
        #expect(relationship.target == .personProfile(targetID))
    }

    @Test func draftRejectsMissingTargetPerson() {
        var draft = PersonRelationshipDraft(sourcePersonID: ContactID(rawValue: "person-zhang-xia"))
        draft.targetMode = .personProfile
        draft.targetPersonID = nil

        #expect(throws: PersonRelationshipDraftError.missingTargetPerson) {
            _ = try draft.makeRelationship(now: Date())
        }
    }

    @Test func draftRejectsSelfRelationship() {
        let personID = ContactID(rawValue: "person-zhang-xia")
        var draft = PersonRelationshipDraft(sourcePersonID: personID)
        draft.targetMode = .personProfile
        draft.targetPersonID = personID

        #expect(throws: PersonRelationshipDraftError.selfRelationship) {
            _ = try draft.makeRelationship(now: Date())
        }
    }
}
