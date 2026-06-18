import Foundation
import ConnorGraphCore

public enum SkillInvocationRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case skillNotFound(String)
    case skillDisabled(String)
    case modelInvocationDisabled(String)
    case userInvocationDisabled(String)

    public var description: String {
        switch self {
        case .skillNotFound(let slug): "skillNotFound: \(slug)"
        case .skillDisabled(let slug): "skillDisabled: \(slug)"
        case .modelInvocationDisabled(let slug): "modelInvocationDisabled: \(slug)"
        case .userInvocationDisabled(let slug): "userInvocationDisabled: \(slug)"
        }
    }
}

public struct SkillInvocationRuntime: Sendable {
    public var argumentParser: SkillInvocationParser

    public init(argumentParser: SkillInvocationParser = SkillInvocationParser()) {
        self.argumentParser = argumentParser
    }

    public func buildPlan(request: SkillInvocationRequest, resolution: SkillResolution, visibility: SkillVisibilityState = .on) throws -> SkillInvocationPlan {
        guard visibility != .off else { throw SkillInvocationRuntimeError.skillDisabled(request.slug.rawValue) }
        guard let package = resolution.selected else { throw SkillInvocationRuntimeError.skillNotFound(request.slug.rawValue) }
        if request.mode == .model && package.manifest.disableModelInvocation {
            throw SkillInvocationRuntimeError.modelInvocationDisabled(package.slug.rawValue)
        }
        if request.mode == .manual && !package.manifest.userInvocable {
            throw SkillInvocationRuntimeError.userInvocationDisabled(package.slug.rawValue)
        }
        let parsed = ParsedSkillInvocation(slug: request.slug, rawInvocation: request.rawInvocation, arguments: request.arguments, mode: request.mode)
        let renderedBody = argumentParser.substituteArguments(in: package.instructions, invocation: parsed, declaredArguments: package.manifest.arguments)
        let rendered = renderInstructions(package: package, body: renderedBody, request: request)
        let permissionRequests = package.manifest.connor.requiredCapabilities.map { capability in
            AgentPermissionRequest(
                runID: request.runID ?? "skill-runtime",
                sessionID: request.sessionID,
                capability: capability,
                toolName: "skill:\(package.slug.rawValue)",
                payloadJSON: "{\"skillID\":\"\(package.slug.rawValue)\",\"sourceTier\":\"\(package.sourceTier.rawValue)\"}"
            )
        }
        return SkillInvocationPlan(
            request: request,
            package: package,
            renderedInstructions: rendered,
            requiredSources: package.manifest.requiredSources,
            permissionRequests: permissionRequests,
            warnings: package.manifest.warnings + resolution.warnings
        )
    }

    public func buildPlans(invocations: [ParsedSkillInvocation], snapshot: SkillPackageScanSnapshot, sessionID: String, runID: String? = nil) -> [Result<SkillInvocationPlan, Error>] {
        invocations.map { invocation in
            do {
                guard let resolution = snapshot.resolution(slug: invocation.slug.rawValue) else { throw SkillInvocationRuntimeError.skillNotFound(invocation.slug.rawValue) }
                let request = SkillInvocationRequest(slug: invocation.slug, rawInvocation: invocation.rawInvocation, arguments: invocation.arguments, mode: invocation.mode, sessionID: sessionID, runID: runID)
                return .success(try buildPlan(request: request, resolution: resolution))
            } catch {
                return .failure(error)
            }
        }
    }

    public func renderInstructions(package: SkillPackage, body: String, request: SkillInvocationRequest) -> String {
        """
        <connor-skill-invocation slug=\"\(package.slug.rawValue)\" sourceTier=\"\(package.sourceTier.rawValue)\" risk=\"\(package.riskLevel.rawValue)\">
        # \(package.manifest.name)

        Description: \(package.manifest.description)
        Skill ID: \(package.slug.rawValue)
        Source tier: \(package.sourceTier.rawValue)
        Trust state: \(package.trustState.rawValue)
        Graph context policy: \(package.manifest.connor.graphContextPolicy.rawValue)
        Required sources: \(package.manifest.requiredSources.joined(separator: ", "))
        Arguments: \(request.arguments)

        \(body)
        </connor-skill-invocation>
        """
    }
}

public struct SkillInvocationAuditWriter: Sendable {
    public var storagePaths: AppStoragePaths

    public init(storagePaths: AppStoragePaths) {
        self.storagePaths = storagePaths
    }

    public func skillInvocationsURL(sessionID: String) -> URL {
        storagePaths.sessionArtifactDirectories(sessionID: sessionID).state.appendingPathComponent("skill-invocations.jsonl")
    }

    public func skillAuditURL(sessionID: String) -> URL {
        storagePaths.sessionArtifactDirectories(sessionID: sessionID).logs.appendingPathComponent("skill-audit.jsonl")
    }

    public func append(plan: SkillInvocationPlan, outcome: SkillInvocationOutcome = .planned, message: String = "Skill invocation planned") throws {
        _ = try storagePaths.ensureSessionArtifactDirectories(sessionID: plan.request.sessionID)
        let event = SkillAuditEvent(
            sessionID: plan.request.sessionID,
            runID: plan.request.runID,
            slug: plan.package.slug.rawValue,
            event: outcome.rawValue,
            sourceTier: plan.package.sourceTier,
            riskLevel: plan.package.riskLevel,
            message: message
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = String(data: try encoder.encode(event), encoding: .utf8)! + "\n"
        try appendLine(line, to: skillInvocationsURL(sessionID: plan.request.sessionID))
        try appendLine(line, to: skillAuditURL(sessionID: plan.request.sessionID))
    }

    private func appendLine(_ line: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
