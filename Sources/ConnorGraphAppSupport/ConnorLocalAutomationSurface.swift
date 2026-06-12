import Foundation
import ConnorGraphCore

public enum ConnorLocalAPIMethod: String, Codable, Sendable, Equatable, Hashable {
    case get = "GET"
    case post = "POST"
}

public enum ConnorLocalAPIRiskLevel: String, Codable, Sendable, Equatable, Hashable {
    case readOnly = "read_only"
    case reviewRequired = "review_required"
    case stateChanging = "state_changing"
    case blocked
}

public enum ConnorLocalAPIAuthMode: String, Codable, Sendable, Equatable, Hashable {
    case localProcess = "local_process"
    case loopbackTokenRequired = "loopback_token_required"
}

public enum ConnorLocalAPIRouteID: String, Codable, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case readiness
    case sessions
    case sessionDetail
    case automations
    case automationEvaluate
    case automationExecuteReviewed
    case sourceHealth
    case graphMemoryReview

    public var id: String { rawValue }
}

public struct ConnorLocalAPIEndpointPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorLocalAPIRouteID
    public var method: ConnorLocalAPIMethod
    public var path: String
    public var summary: String
    public var riskLevel: ConnorLocalAPIRiskLevel
    public var authMode: ConnorLocalAPIAuthMode
    public var requiredCapabilities: [AgentPermissionCapability]
    public var requiresReview: Bool
    public var auditCategory: String
    public var cliEquivalent: String

    public init(
        id: ConnorLocalAPIRouteID,
        method: ConnorLocalAPIMethod,
        path: String,
        summary: String,
        riskLevel: ConnorLocalAPIRiskLevel = .readOnly,
        authMode: ConnorLocalAPIAuthMode = .localProcess,
        requiredCapabilities: [AgentPermissionCapability] = [.readSession],
        requiresReview: Bool = false,
        auditCategory: String,
        cliEquivalent: String
    ) {
        self.id = id
        self.method = method
        self.path = path
        self.summary = summary
        self.riskLevel = riskLevel
        self.authMode = authMode
        self.requiredCapabilities = requiredCapabilities
        self.requiresReview = requiresReview
        self.auditCategory = auditCategory
        self.cliEquivalent = cliEquivalent
    }
}

public enum ConnorCLICommandID: String, Codable, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case commands
    case readiness
    case sessionList
    case sessionShow
    case automationList
    case automationEvaluate
    case automationExecuteReviewed
    case sourceHealth
    case graphMemoryReview
    case openAppRoute

    public var id: String { rawValue }
}

public struct ConnorCLICommandPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorCLICommandID
    public var name: String
    public var usage: String
    public var summary: String
    public var riskLevel: ConnorLocalAPIRiskLevel
    public var requiresReview: Bool
    public var examples: [String]
    public var outputFormat: String
    public var apiRoute: ConnorLocalAPIRouteID?

    public init(
        id: ConnorCLICommandID,
        name: String,
        usage: String,
        summary: String,
        riskLevel: ConnorLocalAPIRiskLevel = .readOnly,
        requiresReview: Bool = false,
        examples: [String] = [],
        outputFormat: String = "json",
        apiRoute: ConnorLocalAPIRouteID? = nil
    ) {
        self.id = id
        self.name = name
        self.usage = usage
        self.summary = summary
        self.riskLevel = riskLevel
        self.requiresReview = requiresReview
        self.examples = examples
        self.outputFormat = outputFormat
        self.apiRoute = apiRoute
    }
}

public struct ConnorAutomationSurfaceTriggerRequest: Codable, Sendable, Equatable {
    public var triggerKind: ProductOSAutomationTriggerKind
    public var sessionID: String
    public var status: AgentSessionStatus?
    public var labelID: String?
    public var registryEntryID: String?
    public var dryRun: Bool
    public var reviewed: Bool

    public init(
        triggerKind: ProductOSAutomationTriggerKind,
        sessionID: String,
        status: AgentSessionStatus? = nil,
        labelID: String? = nil,
        registryEntryID: String? = nil,
        dryRun: Bool = true,
        reviewed: Bool = false
    ) {
        self.triggerKind = triggerKind
        self.sessionID = sessionID
        self.status = status
        self.labelID = labelID
        self.registryEntryID = registryEntryID
        self.dryRun = dryRun
        self.reviewed = reviewed
    }

    public var context: ProductOSAutomationEventContext {
        ProductOSAutomationEventContext(
            triggerKind: triggerKind,
            sessionID: sessionID,
            status: status,
            labelID: labelID,
            registryEntryID: registryEntryID
        )
    }
}

public struct ConnorAutomationSurfaceEvaluation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var request: ConnorAutomationSurfaceTriggerRequest
    public var matchedRuleIDs: [String]
    public var actionPlans: [AutomationActionPlan]
    public var readyActionCount: Int
    public var pendingReviewActionCount: Int
    public var blockedActionCount: Int
    public var auditSummary: String
    public var canExecuteWithoutReview: Bool

    public init(
        id: String = UUID().uuidString,
        request: ConnorAutomationSurfaceTriggerRequest,
        matchedRuleIDs: [String],
        actionPlans: [AutomationActionPlan],
        auditSummary: String
    ) {
        self.id = id
        self.request = request
        self.matchedRuleIDs = matchedRuleIDs
        self.actionPlans = actionPlans
        self.readyActionCount = actionPlans.filter { $0.disposition == .ready }.count
        self.pendingReviewActionCount = actionPlans.filter { $0.disposition == .pendingReview }.count
        self.blockedActionCount = actionPlans.filter { $0.disposition == .blocked }.count
        self.auditSummary = auditSummary
        self.canExecuteWithoutReview = pendingReviewActionCount == 0 && blockedActionCount == 0
    }
}

public struct ConnorAutomationSurfaceExecutionGate: Codable, Sendable, Equatable {
    public var status: ConnorLocalAPIRiskLevel
    public var executablePlanIDs: [String]
    public var blockedPlanIDs: [String]
    public var reason: String

    public init(status: ConnorLocalAPIRiskLevel, executablePlanIDs: [String], blockedPlanIDs: [String], reason: String) {
        self.status = status
        self.executablePlanIDs = executablePlanIDs
        self.blockedPlanIDs = blockedPlanIDs
        self.reason = reason
    }
}

public struct ConnorLocalAutomationSurfacePresentation: Codable, Sendable, Equatable {
    public var endpoints: [ConnorLocalAPIEndpointPresentation]
    public var cliCommands: [ConnorCLICommandPresentation]
    public var supportedTriggers: [ProductOSAutomationTriggerKind]
    public var dryRunEvaluationReady: Bool
    public var reviewedExecutionGateReady: Bool
    public var auditSurfaceReady: Bool
    public var localOnly: Bool

    public init(
        endpoints: [ConnorLocalAPIEndpointPresentation] = ConnorLocalAutomationSurfaceCatalog.defaultEndpoints,
        cliCommands: [ConnorCLICommandPresentation] = ConnorLocalAutomationSurfaceCatalog.defaultCommands,
        supportedTriggers: [ProductOSAutomationTriggerKind] = ProductOSAutomationTriggerKind.allCases,
        dryRunEvaluationReady: Bool = true,
        reviewedExecutionGateReady: Bool = true,
        auditSurfaceReady: Bool = true,
        localOnly: Bool = true
    ) {
        self.endpoints = endpoints
        self.cliCommands = cliCommands
        self.supportedTriggers = supportedTriggers
        self.dryRunEvaluationReady = dryRunEvaluationReady
        self.reviewedExecutionGateReady = reviewedExecutionGateReady
        self.auditSurfaceReady = auditSurfaceReady
        self.localOnly = localOnly
    }

    public static let `default` = ConnorLocalAutomationSurfacePresentation()
}

public enum ConnorLocalAutomationSurfaceCatalog {
    public static let defaultEndpoints: [ConnorLocalAPIEndpointPresentation] = [
        .init(id: .readiness, method: .get, path: "/v1/readiness", summary: "Return commercial readiness dashboard.", auditCategory: "local.readiness", cliEquivalent: "connor readiness --json"),
        .init(id: .sessions, method: .get, path: "/v1/sessions", summary: "List Connor sessions.", auditCategory: "local.sessions", cliEquivalent: "connor sessions list"),
        .init(id: .sessionDetail, method: .get, path: "/v1/sessions/{id}", summary: "Show one Connor session.", auditCategory: "local.sessions", cliEquivalent: "connor sessions show <id>"),
        .init(id: .automations, method: .get, path: "/v1/automations", summary: "List governed automation rules.", auditCategory: "local.automation", cliEquivalent: "connor automations list"),
        .init(id: .automationEvaluate, method: .post, path: "/v1/automations/evaluate", summary: "Dry-run an automation trigger and return governed action plans.", riskLevel: .reviewRequired, requiredCapabilities: [.readSession, .proposeGraphWrite], requiresReview: false, auditCategory: "local.automation.evaluate", cliEquivalent: "connor automations evaluate --dry-run"),
        .init(id: .automationExecuteReviewed, method: .post, path: "/v1/automations/execute-reviewed", summary: "Execute reviewed safe automation actions only.", riskLevel: .stateChanging, requiredCapabilities: [.commitGraphWrite], requiresReview: true, auditCategory: "local.automation.execute", cliEquivalent: "connor automations execute-reviewed <evaluation-id>"),
        .init(id: .sourceHealth, method: .get, path: "/v1/sources/health", summary: "Return Source/MCP platform health.", auditCategory: "local.sources", cliEquivalent: "connor sources health"),
        .init(id: .graphMemoryReview, method: .get, path: "/v1/memory/review", summary: "Return graph memory review summary.", auditCategory: "local.memory", cliEquivalent: "connor memory review --summary")
    ]

    public static let defaultCommands: [ConnorCLICommandPresentation] = [
        .init(id: .commands, name: "commands", usage: "connor commands", summary: "List available Connor CLI commands.", examples: ["connor commands"]),
        .init(id: .readiness, name: "readiness", usage: "connor readiness --json", summary: "Inspect commercial readiness.", examples: ["connor readiness --json"], apiRoute: .readiness),
        .init(id: .sessionList, name: "sessions list", usage: "connor sessions list --limit 20", summary: "List recent sessions.", examples: ["connor sessions list"], apiRoute: .sessions),
        .init(id: .sessionShow, name: "sessions show", usage: "connor sessions show <session-id>", summary: "Show one session.", examples: ["connor sessions show session-1"], apiRoute: .sessionDetail),
        .init(id: .automationList, name: "automations list", usage: "connor automations list", summary: "List automation rules.", examples: ["connor automations list"], apiRoute: .automations),
        .init(id: .automationEvaluate, name: "automations evaluate", usage: "connor automations evaluate --trigger sessionStatusChanged --session <id> --status needsReview --dry-run", summary: "Dry-run automation trigger evaluation.", riskLevel: .reviewRequired, examples: ["connor automations evaluate --trigger sessionStatusChanged --session demo --status needsReview --dry-run"], apiRoute: .automationEvaluate),
        .init(id: .automationExecuteReviewed, name: "automations execute-reviewed", usage: "connor automations execute-reviewed <evaluation-id> --reviewed", summary: "Execute reviewed safe automation actions.", riskLevel: .stateChanging, requiresReview: true, examples: ["connor automations execute-reviewed eval-1 --reviewed"], apiRoute: .automationExecuteReviewed),
        .init(id: .sourceHealth, name: "sources health", usage: "connor sources health", summary: "Inspect source runtime health.", examples: ["connor sources health"], apiRoute: .sourceHealth),
        .init(id: .graphMemoryReview, name: "memory review", usage: "connor memory review --summary", summary: "Inspect graph memory review queue.", examples: ["connor memory review --summary"], apiRoute: .graphMemoryReview),
        .init(id: .openAppRoute, name: "open", usage: "connor open connor://runtime/home", summary: "Open a Connor app route.", examples: ["connor open connor://runtime/home"])
    ]
}

public struct ConnorAutomationSurfaceEvaluator: Sendable, Equatable {
    public init() {}

    public func evaluate(request: ConnorAutomationSurfaceTriggerRequest, config: ProductOSAutomationConfig) -> ConnorAutomationSurfaceEvaluation {
        let matchedRules = config.rules.filter { $0.isEnabled && AppProductOSAutomationRepository.matches(rule: $0, context: request.context) }
        let plans = matchedRules.flatMap { rule in
            rule.actions.map { action in
                AutomationActionPlan(
                    ruleID: rule.id,
                    ruleName: rule.name,
                    action: action,
                    disposition: rule.requiresReview ? .pendingReview : .ready,
                    reason: rule.requiresReview ? "Rule requires governed review before execution." : "Rule is eligible for safe execution."
                )
            }
        }
        return ConnorAutomationSurfaceEvaluation(
            request: request,
            matchedRuleIDs: matchedRules.map(\.id),
            actionPlans: plans,
            auditSummary: "automation dry-run · trigger \(request.triggerKind.rawValue) · \(matchedRules.count) matched rules · \(plans.count) action plans"
        )
    }

    public func executionGate(for evaluation: ConnorAutomationSurfaceEvaluation, reviewed: Bool) -> ConnorAutomationSurfaceExecutionGate {
        let readyPlans = evaluation.actionPlans.filter { $0.disposition == .ready }.map(\.id)
        let reviewPlans = evaluation.actionPlans.filter { $0.disposition != .ready }.map(\.id)
        if !reviewed && (!reviewPlans.isEmpty || !readyPlans.isEmpty) {
            return ConnorAutomationSurfaceExecutionGate(
                status: .reviewRequired,
                executablePlanIDs: [],
                blockedPlanIDs: evaluation.actionPlans.map(\.id),
                reason: "Local automation execution requires reviewed evidence; use dry-run output for human review first."
            )
        }
        return ConnorAutomationSurfaceExecutionGate(
            status: reviewPlans.isEmpty ? .stateChanging : .reviewRequired,
            executablePlanIDs: readyPlans,
            blockedPlanIDs: reviewPlans,
            reason: reviewPlans.isEmpty ? "Reviewed safe actions are eligible for execution." : "Pending-review actions remain blocked even after reviewed execution request."
        )
    }
}

public struct ConnorLocalAPIRequest: Codable, Sendable, Equatable {
    public var method: ConnorLocalAPIMethod
    public var path: String
    public var query: [String: String]
    public var body: String?
    public var caller: String
    public var dryRun: Bool

    public init(method: ConnorLocalAPIMethod, path: String, query: [String: String] = [:], body: String? = nil, caller: String = "local", dryRun: Bool = true) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.caller = caller
        self.dryRun = dryRun
    }
}

public struct ConnorLocalAPIResponse: Codable, Sendable, Equatable {
    public var statusCode: Int
    public var body: String
    public var auditSummary: String

    public init(statusCode: Int, body: String, auditSummary: String) {
        self.statusCode = statusCode
        self.body = body
        self.auditSummary = auditSummary
    }
}

public struct ConnorLocalAPIRouter: Sendable, Equatable {
    public var presentation: ConnorLocalAutomationSurfacePresentation

    public init(presentation: ConnorLocalAutomationSurfacePresentation = .default) {
        self.presentation = presentation
    }

    public func handle(_ request: ConnorLocalAPIRequest) -> ConnorLocalAPIResponse {
        if request.method == .get && request.path == "/v1/readiness" {
            return jsonResponse(statusCode: 200, body: "{\"surface\":\"readiness\",\"localOnly\":\(presentation.localOnly)}", audit: "local.readiness read")
        }
        if request.method == .get && request.path == "/v1/commands" {
            return jsonResponse(statusCode: 200, body: "{\"commands\":\(presentation.cliCommands.count)}", audit: "local.commands read")
        }
        if request.method == .post && request.path == "/v1/automations/evaluate" {
            return jsonResponse(statusCode: 202, body: "{\"surface\":\"automation-evaluate\",\"dryRun\":true}", audit: "local.automation.evaluate dry-run")
        }
        return jsonResponse(statusCode: 404, body: "{\"error\":\"route_not_found\"}", audit: "local.route missing")
    }

    private func jsonResponse(statusCode: Int, body: String, audit: String) -> ConnorLocalAPIResponse {
        ConnorLocalAPIResponse(statusCode: statusCode, body: body, auditSummary: audit)
    }
}
