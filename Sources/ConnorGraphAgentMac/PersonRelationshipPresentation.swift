import Foundation
import ConnorGraphCore

enum PersonRelationshipPresentation {
    struct Row: Equatable, Identifiable {
        var id: String { "\(label):\(value)" }
        var label: String
        var value: String
    }

    static func rows(
        for personID: ContactID,
        relationships: [PersonRelationship],
        displayTitle: (PersonRelationshipEndpoint) -> String
    ) -> [Row] {
        relationships
            .filter { $0.status == .active || $0.status == .pending }
            .compactMap { relationship -> Row? in
                if relationship.source.kind == .personProfile, relationship.source.personID == personID {
                    return Row(label: relationship.displayKindTitle, value: displayTitle(relationship.target))
                }
                if relationship.target.kind == .personProfile, relationship.target.personID == personID {
                    return Row(label: relationship.displayKindTitle, value: displayTitle(relationship.source))
                }
                return nil
            }
            .sorted { first, second in
                if first.label != second.label {
                    return first.label.localizedStandardCompare(second.label) == .orderedAscending
                }
                return first.value.localizedStandardCompare(second.value) == .orderedAscending
            }
    }
}
