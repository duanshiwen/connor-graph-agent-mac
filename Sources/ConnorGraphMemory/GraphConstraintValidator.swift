import Foundation
import ConnorGraphCore

public enum GraphConstraintValidationError: String, Codable, Sendable, CaseIterable, Equatable {
    case invalidTemporalRange
    case selfTaxonomyLoop
    case missingJustification
    case missingSourceEpisode
    case instanceOfObjectIsNotClass
    case subclassSubjectIsNotClass
    case subclassObjectIsNotClass
    case graphIDMismatch
}

public struct GraphConstraintValidationResult: Sendable, Equatable {
    public var errors: [GraphConstraintValidationError]

    public init(errors: [GraphConstraintValidationError] = []) {
        self.errors = errors
    }

    public var isValid: Bool { errors.isEmpty }
}

public struct GraphConstraintValidator: Sendable, Equatable {
    public init() {}

    public func validate(statement: GraphStatement, subject: GraphEntity?, object: GraphEntity?) -> GraphConstraintValidationResult {
        var errors: [GraphConstraintValidationError] = []

        if let invalidAt = statement.invalidAt, statement.validAt > invalidAt {
            errors.append(.invalidTemporalRange)
        }
        if statement.justifications.isEmpty {
            errors.append(.missingJustification)
        }
        if statement.sourceEpisodeIDs.isEmpty {
            errors.append(.missingSourceEpisode)
        }
        if statement.predicate == .subclassOf, statement.subjectEntityID == statement.objectEntityID {
            errors.append(.selfTaxonomyLoop)
        }
        if let subject, subject.graphID != statement.graphID {
            errors.append(.graphIDMismatch)
        }
        if let object, object.graphID != statement.graphID {
            errors.append(.graphIDMismatch)
        }
        if statement.predicate == .instanceOf, let object, object.entityKind != .classNode {
            errors.append(.instanceOfObjectIsNotClass)
        }
        if statement.predicate == .subclassOf {
            if let subject, subject.entityKind != .classNode { errors.append(.subclassSubjectIsNotClass) }
            if let object, object.entityKind != .classNode { errors.append(.subclassObjectIsNotClass) }
        }

        return GraphConstraintValidationResult(errors: unique(errors))
    }

    private func unique(_ errors: [GraphConstraintValidationError]) -> [GraphConstraintValidationError] {
        var seen: Set<GraphConstraintValidationError> = []
        var output: [GraphConstraintValidationError] = []
        for error in errors where !seen.contains(error) {
            seen.insert(error)
            output.append(error)
        }
        return output
    }
}
