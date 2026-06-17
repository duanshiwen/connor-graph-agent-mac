import Foundation
import ConnorGraphCore

public enum SkillEvaluationOutcome: String, Codable, Sendable, Equatable, Hashable {
    case pass
    case warning
    case fail
}

public struct SkillEvaluationCase: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var skillSlug: String
    public var prompt: String
    public var expectedInvocation: Bool

    public init(id: String = UUID().uuidString, skillSlug: String, prompt: String, expectedInvocation: Bool) {
        self.id = id
        self.skillSlug = skillSlug
        self.prompt = prompt
        self.expectedInvocation = expectedInvocation
    }
}

public struct SkillEvaluationResult: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var caseID: String
    public var outcome: SkillEvaluationOutcome
    public var message: String

    public init(id: String = UUID().uuidString, caseID: String, outcome: SkillEvaluationOutcome, message: String) {
        self.id = id
        self.caseID = caseID
        self.outcome = outcome
        self.message = message
    }
}

public struct SkillObservabilitySnapshot: Codable, Sendable, Equatable, Hashable {
    public var discoveredSkills: Int
    public var invalidSkills: Int
    public var riskySkills: Int
    public var untrustedProjectSkills: Int
    public var sourceBlockedSkills: Int
    public var failedEvaluations: Int

    public init(discoveredSkills: Int, invalidSkills: Int, riskySkills: Int, untrustedProjectSkills: Int, sourceBlockedSkills: Int, failedEvaluations: Int) {
        self.discoveredSkills = discoveredSkills
        self.invalidSkills = invalidSkills
        self.riskySkills = riskySkills
        self.untrustedProjectSkills = untrustedProjectSkills
        self.sourceBlockedSkills = sourceBlockedSkills
        self.failedEvaluations = failedEvaluations
    }

    public var isCommerciallyReady: Bool {
        invalidSkills == 0 && untrustedProjectSkills == 0 && sourceBlockedSkills == 0 && failedEvaluations == 0
    }
}

public struct SkillObservabilityService: Sendable {
    public init() {}

    public func evaluate(cases: [SkillEvaluationCase], parser: SkillInvocationParser = SkillInvocationParser()) -> [SkillEvaluationResult] {
        cases.map { evaluationCase in
            let invocations = parser.parse(evaluationCase.prompt, availableSlugs: [evaluationCase.skillSlug])
            let didInvoke = invocations.contains { $0.slug.rawValue == evaluationCase.skillSlug }
            if didInvoke == evaluationCase.expectedInvocation {
                return SkillEvaluationResult(caseID: evaluationCase.id, outcome: .pass, message: "Invocation behavior matched expectation.")
            }
            return SkillEvaluationResult(caseID: evaluationCase.id, outcome: .fail, message: "Expected invocation=\(evaluationCase.expectedInvocation), got \(didInvoke).")
        }
    }

    public func readiness(snapshot: SkillPackageScanSnapshot, sourceReadiness: [String: [SkillSourceReadiness]] = [:], evaluations: [SkillEvaluationResult] = []) -> SkillObservabilitySnapshot {
        let selected = snapshot.resolutions.compactMap(\.selected)
        return SkillObservabilitySnapshot(
            discoveredSkills: selected.count,
            invalidSkills: snapshot.warnings.count,
            riskySkills: selected.filter { $0.riskLevel >= .high }.count,
            untrustedProjectSkills: selected.filter { ($0.sourceTier == .project || $0.sourceTier == .nestedContextual) && $0.trustState == .projectRequiresTrust }.count,
            sourceBlockedSkills: sourceReadiness.values.flatMap { $0 }.filter { $0.state == .missing || $0.state == .unauthenticated }.count,
            failedEvaluations: evaluations.filter { $0.outcome == .fail }.count
        )
    }
}
