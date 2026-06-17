import Foundation

public struct SkillPackageID: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public var rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }
}

public struct SkillSlug: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public var rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }

    public var isValid: Bool {
        rawValue.range(of: #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#, options: .regularExpression) != nil
    }
}

public enum SkillSourceTier: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case bundled
    case global
    case user
    case teamManaged
    case project
    case nestedContextual
    case marketplace
    case enterprise

    public var legacyScope: ProductOSSkillScope {
        switch self {
        case .global, .bundled, .marketplace, .enterprise: .global
        case .user, .teamManaged: .home
        case .project, .nestedContextual: .project
        }
    }
}

public enum SkillVisibilityState: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case on
    case nameOnly = "name-only"
    case userInvocableOnly = "user-invocable-only"
    case off
}

public enum SkillInvocationMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case manual
    case model
    case automatic
    case automation
}

public enum SkillExecutionContext: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case inline
    case fork
}

public enum SkillTrustState: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case bundledTrusted
    case userTrusted
    case projectRequiresTrust
    case trusted
    case denied
    case unknown
}

public enum SkillRiskLevel: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case critical

    public static func < (lhs: SkillRiskLevel, rhs: SkillRiskLevel) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ value: SkillRiskLevel) -> Int {
        switch value {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}

public enum SkillLifecycleState: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case stable
    case beta
    case deprecated
}

public enum SkillSourcePolicy: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case preenableIfReady
    case requireReady
    case manualOnly
}

public enum SkillAuditLevel: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case minimal
    case standard
    case strict
}

public struct ConnorSkillExtension: Codable, Sendable, Equatable, Hashable {
    public var requiredCapabilities: [AgentPermissionCapability]
    public var graphContextPolicy: AgentPermissionMode
    public var sourcePolicy: SkillSourcePolicy
    public var trustPolicy: String?
    public var auditLevel: SkillAuditLevel
    public var riskLevel: SkillRiskLevel
    public var lifecycle: SkillLifecycleState
    public var commercialTier: String?

    public init(
        requiredCapabilities: [AgentPermissionCapability] = [.readSession],
        graphContextPolicy: AgentPermissionMode = .readOnly,
        sourcePolicy: SkillSourcePolicy = .preenableIfReady,
        trustPolicy: String? = nil,
        auditLevel: SkillAuditLevel = .standard,
        riskLevel: SkillRiskLevel = .low,
        lifecycle: SkillLifecycleState = .stable,
        commercialTier: String? = nil
    ) {
        self.requiredCapabilities = requiredCapabilities
        self.graphContextPolicy = graphContextPolicy
        self.sourcePolicy = sourcePolicy
        self.trustPolicy = trustPolicy
        self.auditLevel = auditLevel
        self.riskLevel = riskLevel
        self.lifecycle = lifecycle
        self.commercialTier = commercialTier
    }
}

public struct SkillManifest: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var description: String
    public var whenToUse: String?
    public var argumentHint: String?
    public var arguments: [String]
    public var globs: [String]
    public var paths: [String]
    public var requiredSources: [String]
    public var alwaysAllow: [String]
    public var allowedTools: [String]
    public var disallowedTools: [String]
    public var disableModelInvocation: Bool
    public var userInvocable: Bool
    public var model: String?
    public var effort: String?
    public var context: SkillExecutionContext
    public var agent: String?
    public var shell: String?
    public var icon: String?
    public var tags: [String]
    public var version: String?
    public var publisher: String?
    public var connor: ConnorSkillExtension
    public var unsupportedFields: [String]
    public var warnings: [String]

    public init(
        name: String,
        description: String,
        whenToUse: String? = nil,
        argumentHint: String? = nil,
        arguments: [String] = [],
        globs: [String] = [],
        paths: [String] = [],
        requiredSources: [String] = [],
        alwaysAllow: [String] = [],
        allowedTools: [String] = [],
        disallowedTools: [String] = [],
        disableModelInvocation: Bool = false,
        userInvocable: Bool = true,
        model: String? = nil,
        effort: String? = nil,
        context: SkillExecutionContext = .inline,
        agent: String? = nil,
        shell: String? = nil,
        icon: String? = nil,
        tags: [String] = [],
        version: String? = nil,
        publisher: String? = nil,
        connor: ConnorSkillExtension = ConnorSkillExtension(),
        unsupportedFields: [String] = [],
        warnings: [String] = []
    ) {
        self.name = name
        self.description = description
        self.whenToUse = whenToUse
        self.argumentHint = argumentHint
        self.arguments = arguments
        self.globs = globs
        self.paths = paths
        self.requiredSources = requiredSources
        self.alwaysAllow = alwaysAllow
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.disableModelInvocation = disableModelInvocation
        self.userInvocable = userInvocable
        self.model = model
        self.effort = effort
        self.context = context
        self.agent = agent
        self.shell = shell
        self.icon = icon
        self.tags = tags
        self.version = version
        self.publisher = publisher
        self.connor = connor
        self.unsupportedFields = unsupportedFields
        self.warnings = warnings
    }
}

public struct SkillPackage: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: SkillPackageID
    public var slug: SkillSlug
    public var sourceTier: SkillSourceTier
    public var manifest: SkillManifest
    public var instructions: String
    public var packagePath: String
    public var skillFilePath: String
    public var supportingFiles: [String]
    public var trustState: SkillTrustState
    public var riskLevel: SkillRiskLevel
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: SkillPackageID,
        slug: SkillSlug,
        sourceTier: SkillSourceTier,
        manifest: SkillManifest,
        instructions: String,
        packagePath: String,
        skillFilePath: String,
        supportingFiles: [String] = [],
        trustState: SkillTrustState = .unknown,
        riskLevel: SkillRiskLevel = .low,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.slug = slug
        self.sourceTier = sourceTier
        self.manifest = manifest
        self.instructions = instructions
        self.packagePath = packagePath
        self.skillFilePath = skillFilePath
        self.supportingFiles = supportingFiles
        self.trustState = trustState
        self.riskLevel = riskLevel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SkillResolution: Codable, Sendable, Equatable, Hashable {
    public var slug: SkillSlug
    public var selected: SkillPackage?
    public var candidates: [SkillPackage]
    public var warnings: [String]

    public init(slug: SkillSlug, selected: SkillPackage?, candidates: [SkillPackage], warnings: [String] = []) {
        self.slug = slug
        self.selected = selected
        self.candidates = candidates
        self.warnings = warnings
    }
}

public struct SkillInvocationRequest: Codable, Sendable, Equatable, Hashable {
    public var slug: SkillSlug
    public var rawInvocation: String
    public var arguments: String
    public var mode: SkillInvocationMode
    public var sessionID: String
    public var runID: String?

    public init(slug: SkillSlug, rawInvocation: String, arguments: String = "", mode: SkillInvocationMode = .manual, sessionID: String, runID: String? = nil) {
        self.slug = slug
        self.rawInvocation = rawInvocation
        self.arguments = arguments
        self.mode = mode
        self.sessionID = sessionID
        self.runID = runID
    }
}

public struct SkillInvocationPlan: Codable, Sendable, Equatable {
    public var request: SkillInvocationRequest
    public var package: SkillPackage
    public var renderedInstructions: String
    public var requiredSources: [String]
    public var permissionRequests: [AgentPermissionRequest]
    public var warnings: [String]

    public init(request: SkillInvocationRequest, package: SkillPackage, renderedInstructions: String, requiredSources: [String], permissionRequests: [AgentPermissionRequest] = [], warnings: [String] = []) {
        self.request = request
        self.package = package
        self.renderedInstructions = renderedInstructions
        self.requiredSources = requiredSources
        self.permissionRequests = permissionRequests
        self.warnings = warnings
    }
}

public enum SkillInvocationOutcome: String, Codable, Sendable, Equatable, Hashable {
    case planned
    case injected
    case skipped
    case failed
}

public struct SkillInvocationResult: Codable, Sendable, Equatable {
    public var plan: SkillInvocationPlan
    public var outcome: SkillInvocationOutcome
    public var message: String

    public init(plan: SkillInvocationPlan, outcome: SkillInvocationOutcome, message: String) {
        self.plan = plan
        self.outcome = outcome
        self.message = message
    }
}

public struct SkillAuditEvent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var sessionID: String
    public var runID: String?
    public var slug: String
    public var event: String
    public var sourceTier: SkillSourceTier
    public var riskLevel: SkillRiskLevel
    public var message: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, sessionID: String, runID: String? = nil, slug: String, event: String, sourceTier: SkillSourceTier, riskLevel: SkillRiskLevel, message: String, createdAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.runID = runID
        self.slug = slug
        self.event = event
        self.sourceTier = sourceTier
        self.riskLevel = riskLevel
        self.message = message
        self.createdAt = createdAt
    }
}
