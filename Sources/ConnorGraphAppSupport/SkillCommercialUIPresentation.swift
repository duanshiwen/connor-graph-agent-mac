import Foundation
import ConnorGraphCore

public struct SkillManagerSummary: Sendable, Equatable {
    public var total: Int
    public var enabled: Int
    public var projectScoped: Int
    public var risky: Int
    public var invalid: Int
    public var sourceBlocked: Int

    public init(total: Int, enabled: Int, projectScoped: Int, risky: Int, invalid: Int, sourceBlocked: Int) {
        self.total = total
        self.enabled = enabled
        self.projectScoped = projectScoped
        self.risky = risky
        self.invalid = invalid
        self.sourceBlocked = sourceBlocked
    }
}

public struct SkillManagerCard: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var path: String
    public var packagePath: String
    public var instructions: String
    public var sourceTier: String
    public var trustState: String
    public var riskLabel: String
    public var lifecycleLabel: String
    public var requiredSources: [String]
    public var permissionLabels: [String]
    public var overrideChain: [String]
    public var warnings: [String]

    public init(id: String, title: String, subtitle: String, path: String, packagePath: String = "", instructions: String = "", sourceTier: String, trustState: String, riskLabel: String, lifecycleLabel: String, requiredSources: [String], permissionLabels: [String], overrideChain: [String], warnings: [String]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.packagePath = packagePath
        self.instructions = instructions
        self.sourceTier = sourceTier
        self.trustState = trustState
        self.riskLabel = riskLabel
        self.lifecycleLabel = lifecycleLabel
        self.requiredSources = requiredSources
        self.permissionLabels = permissionLabels
        self.overrideChain = overrideChain
        self.warnings = warnings
    }
}

public struct SkillManagerPresentation: Sendable, Equatable {
    public var summary: SkillManagerSummary
    public var cards: [SkillManagerCard]
    public var globalWarnings: [String]

    public init(summary: SkillManagerSummary, cards: [SkillManagerCard], globalWarnings: [String]) {
        self.summary = summary
        self.cards = cards
        self.globalWarnings = globalWarnings
    }
}

public struct SkillCommercialUIPresentationBuilder: Sendable {
    public init() {}

    public func build(snapshot: SkillPackageScanSnapshot, sourceReadiness: [String: [SkillSourceReadiness]] = [:]) -> SkillManagerPresentation {
        let cards = snapshot.resolutions.compactMap { resolution -> SkillManagerCard? in
            guard let selected = resolution.selected else { return nil }
            guard !selected.manifest.hidden else { return nil }
            let readiness = sourceReadiness[selected.slug.rawValue] ?? []
            let sourceWarnings = readiness.filter { $0.state != .ready }.map { "\($0.sourceSlug): \($0.message)" }
            return SkillManagerCard(
                id: selected.slug.rawValue,
                title: selected.manifest.name,
                subtitle: selected.manifest.description,
                path: selected.skillFilePath,
                packagePath: selected.packagePath,
                instructions: selected.instructions,
                sourceTier: selected.sourceTier.rawValue,
                trustState: selected.trustState.rawValue,
                riskLabel: selected.riskLevel.rawValue,
                lifecycleLabel: selected.manifest.connor.lifecycle.rawValue,
                requiredSources: selected.manifest.requiredSources,
                permissionLabels: selected.manifest.connor.requiredCapabilities.map(\.rawValue).sorted(),
                overrideChain: resolution.candidates.map { "\($0.sourceTier.rawValue):\($0.skillFilePath)" },
                warnings: selected.manifest.warnings + resolution.warnings + sourceWarnings
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let summary = SkillManagerSummary(
            total: cards.count,
            enabled: cards.filter { $0.lifecycleLabel != SkillLifecycleState.deprecated.rawValue }.count,
            projectScoped: cards.filter { $0.sourceTier == SkillSourceTier.project.rawValue || $0.sourceTier == SkillSourceTier.nestedContextual.rawValue }.count,
            risky: cards.filter { [SkillRiskLevel.high.rawValue, SkillRiskLevel.critical.rawValue].contains($0.riskLabel) }.count,
            invalid: snapshot.warnings.count,
            sourceBlocked: sourceReadiness.values.flatMap { $0 }.filter { $0.state == .missing || $0.state == .unauthenticated }.count
        )
        return SkillManagerPresentation(summary: summary, cards: cards, globalWarnings: snapshot.warnings)
    }
}
