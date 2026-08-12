import Foundation
import ConnorGraphCore

enum PersonRelationshipPresentation {
    /// 人物详情页使用的关系行：包含类型、方向（谁 → 谁）、备注与证据。
    struct DetailRow: Equatable, Identifiable {
        var id: String { relationship.id }
        var relationship: PersonRelationship
        var kindTitle: String
        var directionText: String
        var note: String?
        var evidenceText: String?

        init(
            relationship: PersonRelationship,
            kindTitle: String,
            directionText: String,
            note: String? = nil,
            evidenceText: String? = nil
        ) {
            self.relationship = relationship
            self.kindTitle = kindTitle
            self.directionText = directionText
            self.note = note
            self.evidenceText = evidenceText
        }
    }

    static func detailRows(
        for personID: ContactID,
        personDisplayName: String,
        relationships: [PersonRelationship],
        displayTitle: (PersonRelationshipEndpoint) -> String
    ) -> [DetailRow] {
        relationships
            .filter { $0.status == .active || $0.status == .pending }
            .compactMap { relationship -> DetailRow? in
                let isSource = relationship.source.kind == .personProfile && relationship.source.personID == personID
                let isTarget = relationship.target.kind == .personProfile && relationship.target.personID == personID
                guard isSource || isTarget else { return nil }
                let counterpart = isSource ? relationship.target : relationship.source
                let directionText = isSource
                    ? "\(personDisplayName) → \(displayTitle(counterpart))"
                    : "\(displayTitle(counterpart)) → \(personDisplayName)"
                return DetailRow(
                    relationship: relationship,
                    kindTitle: relationship.displayKindTitle,
                    directionText: directionText,
                    note: relationship.note,
                    evidenceText: relationship.evidenceText
                )
            }
            .sorted { first, second in
                if first.kindTitle != second.kindTitle {
                    return first.kindTitle.localizedStandardCompare(second.kindTitle) == .orderedAscending
                }
                return first.directionText.localizedStandardCompare(second.directionText) == .orderedAscending
            }
    }
}
