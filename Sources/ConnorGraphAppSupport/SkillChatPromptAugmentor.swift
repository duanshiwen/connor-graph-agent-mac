import Foundation
import ConnorGraphCore

public struct SkillChatPromptAugmentation: Sendable, Equatable {
    public var originalPrompt: String
    public var augmentedPrompt: String
    public var plans: [SkillInvocationPlan]
    public var warnings: [String]
    public var scannedSkillCount: Int

    public init(originalPrompt: String, augmentedPrompt: String, plans: [SkillInvocationPlan] = [], warnings: [String] = [], scannedSkillCount: Int = 0) {
        self.originalPrompt = originalPrompt
        self.augmentedPrompt = augmentedPrompt
        self.plans = plans
        self.warnings = warnings
        self.scannedSkillCount = scannedSkillCount
    }

    public var didAugment: Bool { !plans.isEmpty }
}

public struct SkillChatPromptAugmentor {
    public var storagePaths: AppStoragePaths
    public var scanner: SkillPackageScanner
    public var parser: SkillInvocationParser
    public var runtime: SkillInvocationRuntime
    public var auditWriter: SkillInvocationAuditWriter

    public init(
        storagePaths: AppStoragePaths,
        scanner: SkillPackageScanner = SkillPackageScanner(),
        parser: SkillInvocationParser = SkillInvocationParser(),
        runtime: SkillInvocationRuntime = SkillInvocationRuntime()
    ) {
        self.storagePaths = storagePaths
        self.scanner = scanner
        self.parser = parser
        self.runtime = runtime
        self.auditWriter = SkillInvocationAuditWriter(storagePaths: storagePaths)
    }

    public func augment(
        prompt rawPrompt: String,
        sessionID: String,
        runID: String? = nil
    ) -> SkillChatPromptAugmentation {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return SkillChatPromptAugmentation(originalPrompt: rawPrompt, augmentedPrompt: rawPrompt)
        }

        let snapshot = scanner.scan(storagePaths: storagePaths)
        let availableSlugs = Set(snapshot.resolutions.compactMap { $0.selected?.slug.rawValue })
        let invocations = parser.parse(prompt, availableSlugs: availableSlugs)
        guard !invocations.isEmpty else {
            return SkillChatPromptAugmentation(
                originalPrompt: rawPrompt,
                augmentedPrompt: rawPrompt,
                warnings: snapshot.warnings,
                scannedSkillCount: snapshot.packages.count
            )
        }

        var plans: [SkillInvocationPlan] = []
        var warnings = snapshot.warnings
        for result in runtime.buildPlans(invocations: invocations, snapshot: snapshot, sessionID: sessionID, runID: runID) {
            switch result {
            case .success(let plan):
                plans.append(plan)
                do {
                    try auditWriter.append(plan: plan, outcome: .planned, message: "Skill invocation attached to chat prompt")
                } catch {
                    warnings.append("Failed to audit skill invocation \(plan.package.slug.rawValue): \(error)")
                }
            case .failure(let error):
                warnings.append("Failed to plan skill invocation: \(error)")
            }
        }

        guard !plans.isEmpty else {
            return SkillChatPromptAugmentation(
                originalPrompt: rawPrompt,
                augmentedPrompt: rawPrompt,
                plans: [],
                warnings: warnings,
                scannedSkillCount: snapshot.packages.count
            )
        }

        let skillBlock = plans.map(\.renderedInstructions).joined(separator: "\n\n")
        let warningBlock = warnings.isEmpty ? "" : "\n\n<connor-skill-warnings>\n" + warnings.map { "- \($0)" }.joined(separator: "\n") + "\n</connor-skill-warnings>"
        let augmented = """
        \(prompt)

        <connor-active-skills count=\"\(plans.count)\">
        \(skillBlock)
        </connor-active-skills>\(warningBlock)
        """

        return SkillChatPromptAugmentation(
            originalPrompt: rawPrompt,
            augmentedPrompt: augmented,
            plans: plans,
            warnings: warnings,
            scannedSkillCount: snapshot.packages.count
        )
    }
}
