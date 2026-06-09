import Foundation

public enum NodeType: String, Codable, Sendable, CaseIterable, Equatable {
    case episode
    case entity
    case workObject = "work_object"
    case question
    case answer
    case decision
    case procedure
    case person
    case document
    case preference
    case observation
}

public enum RelationType: String, Codable, Sendable, CaseIterable, Equatable {
    case belongsTo = "BELONGS_TO"
    case about = "ABOUT"
    case mentions = "MENTIONS"
    case answers = "ANSWERS"
    case answeredBy = "ANSWERED_BY"
    case derivedFrom = "DERIVED_FROM"
    case supportedBy = "SUPPORTED_BY"
    case supersedes = "SUPERSEDES"
    case implements = "IMPLEMENTS"
    case appliesTo = "APPLIES_TO"
    case hasPreference = "HAS_PREFERENCE"
    case worksOn = "WORKS_ON"
    case relatedTo = "RELATED_TO"
    case observedIn = "OBSERVED_IN"
    case promotedFrom = "PROMOTED_FROM"
}
