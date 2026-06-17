import Foundation
import ConnorGraphCore

public enum SkillSourceReadinessState: String, Codable, Sendable, Equatable, Hashable {
    case ready
    case missing
    case disabled
    case unauthenticated
    case manual
}

public struct SkillSourceReadiness: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { sourceSlug }
    public var sourceSlug: String
    public var state: SkillSourceReadinessState
    public var message: String

    public init(sourceSlug: String, state: SkillSourceReadinessState, message: String) {
        self.sourceSlug = sourceSlug
        self.state = state
        self.message = message
    }
}

public struct SkillSourcePreenableResult: Codable, Sendable, Equatable, Hashable {
    public var enabledSources: [String]
    public var readiness: [SkillSourceReadiness]
    public var blocksInvocation: Bool

    public init(enabledSources: [String], readiness: [SkillSourceReadiness], blocksInvocation: Bool) {
        self.enabledSources = enabledSources
        self.readiness = readiness
        self.blocksInvocation = blocksInvocation
    }
}

public struct SkillSourcePreenableService: Sendable {
    public init() {}

    public func evaluate(requiredSources: [String], availableSources: Set<String>, enabledSources: Set<String>, authenticatedSources: Set<String>, policy: SkillSourcePolicy) -> SkillSourcePreenableResult {
        guard policy != .manualOnly else {
            return SkillSourcePreenableResult(enabledSources: [], readiness: requiredSources.map { SkillSourceReadiness(sourceSlug: $0, state: .manual, message: "Source requires manual enablement by skill policy.") }, blocksInvocation: false)
        }
        var toEnable: [String] = []
        var readiness: [SkillSourceReadiness] = []
        var blocks = false
        for source in requiredSources {
            if !availableSources.contains(source) {
                readiness.append(SkillSourceReadiness(sourceSlug: source, state: .missing, message: "Required source is not installed."))
                blocks = blocks || policy == .requireReady
            } else if !authenticatedSources.contains(source) {
                readiness.append(SkillSourceReadiness(sourceSlug: source, state: .unauthenticated, message: "Required source is not authenticated."))
                blocks = blocks || policy == .requireReady
            } else if enabledSources.contains(source) {
                readiness.append(SkillSourceReadiness(sourceSlug: source, state: .ready, message: "Required source is already enabled."))
            } else {
                toEnable.append(source)
                readiness.append(SkillSourceReadiness(sourceSlug: source, state: .ready, message: "Required source can be pre-enabled."))
            }
        }
        return SkillSourcePreenableResult(enabledSources: toEnable.sorted(), readiness: readiness, blocksInvocation: blocks)
    }
}

public enum SkillPermissionGrantScope: String, Codable, Sendable, Equatable, Hashable {
    case invocation
    case run
    case session
    case permanentTrust
}

public struct SkillPermissionGrant: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var skillSlug: String
    public var capability: AgentPermissionCapability
    public var toolName: String
    public var scope: SkillPermissionGrantScope
    public var requiresApproval: Bool
    public var reason: String

    public init(id: String = UUID().uuidString, skillSlug: String, capability: AgentPermissionCapability, toolName: String, scope: SkillPermissionGrantScope = .invocation, requiresApproval: Bool = true, reason: String) {
        self.id = id
        self.skillSlug = skillSlug
        self.capability = capability
        self.toolName = toolName
        self.scope = scope
        self.requiresApproval = requiresApproval
        self.reason = reason
    }
}

public struct SkillPermissionMapper: Sendable {
    public init() {}

    public func grants(for package: SkillPackage, scope: SkillPermissionGrantScope = .invocation) -> [SkillPermissionGrant] {
        let tools = Array(Set(package.manifest.alwaysAllow + package.manifest.allowedTools)).sorted()
        return tools.flatMap { tool -> [SkillPermissionGrant] in
            capabilities(forTool: tool).map { capability in
                SkillPermissionGrant(skillSlug: package.slug.rawValue, capability: capability, toolName: tool, scope: scope, requiresApproval: package.sourceTier == .project || package.sourceTier == .nestedContextual, reason: "Skill requested tool permission hint; Connor Policy Engine must still approve.")
            }
        }
    }

    public func capabilities(forTool tool: String) -> [AgentPermissionCapability] {
        let lowered = tool.lowercased()
        if lowered.contains("bash") || lowered.contains("shell") { return [.runWorkspaceShellCommand] }
        if lowered.contains("write") || lowered.contains("edit") { return [.writeWorkspaceFile, .editWorkspaceFile] }
        if lowered.contains("delete") { return [.deleteWorkspaceFile] }
        if lowered.contains("web") || lowered.contains("fetch") { return [.externalNetwork] }
        return [.readSession]
    }
}

public struct SkillTrustDecision: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var packageID: String
    public var slug: String
    public var state: SkillTrustState
    public var reason: String
    public var decidedAt: Date

    public init(id: String = UUID().uuidString, packageID: String, slug: String, state: SkillTrustState, reason: String, decidedAt: Date = Date()) {
        self.id = id
        self.packageID = packageID
        self.slug = slug
        self.state = state
        self.reason = reason
        self.decidedAt = decidedAt
    }
}

public struct SkillTrustStore: Sendable {
    public init() {}

    public func requiredTrustState(for package: SkillPackage, existingDecision: SkillTrustDecision? = nil) -> SkillTrustState {
        if let existingDecision { return existingDecision.state }
        switch package.sourceTier {
        case .bundled: return .bundledTrusted
        case .global, .user: return .userTrusted
        case .project, .nestedContextual: return .projectRequiresTrust
        case .teamManaged, .enterprise: return .trusted
        case .marketplace: return .unknown
        }
    }
}
