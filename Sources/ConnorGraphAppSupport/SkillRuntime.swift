import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct SkillInstructionBundle: Sendable, Equatable {
    public var skill: SkillRuntimeDefinition
    public var instructions: String
    public var requiredSources: [String]
    public var permissionRequests: [AgentPermissionRequest]
    public var registryEvent: AgentProductOSRegistryEvent
    public var event: AgentEvent

    public init(
        skill: SkillRuntimeDefinition,
        instructions: String,
        requiredSources: [String],
        permissionRequests: [AgentPermissionRequest],
        registryEvent: AgentProductOSRegistryEvent
    ) {
        self.skill = skill
        self.instructions = instructions
        self.requiredSources = requiredSources
        self.permissionRequests = permissionRequests
        self.registryEvent = registryEvent
        self.event = .skillRegistryChanged(registryEvent)
    }
}

public enum SkillRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case skillDisabled(String)

    public var description: String {
        switch self {
        case .skillDisabled(let slug): "skillDisabled: \(slug)"
        }
    }
}

public struct SkillRuntime: Sendable {
    public var definitions: [SkillRuntimeDefinition]
    public var disabledSkillIDs: Set<String>

    public init(definitions: [SkillRuntimeDefinition], disabledSkillIDs: Set<String> = []) {
        self.definitions = definitions.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
        self.disabledSkillIDs = disabledSkillIDs
    }

    public func instructionBundle(
        trigger: ProductOSSkillTrigger,
        filePaths: [String] = [],
        sessionID: String,
        runID: String? = nil
    ) throws -> SkillInstructionBundle? {
        for definition in definitions {
            guard definition.manifest.triggers.contains(trigger) else { continue }
            guard matchesGlobs(definition.manifest.globs, filePaths: filePaths) else { continue }
            if disabledSkillIDs.contains(definition.slug) {
                throw SkillRuntimeError.skillDisabled(definition.slug)
            }
            let permissionRequests = definition.manifest.requiredCapabilities.map { capability in
                AgentPermissionRequest(
                    runID: runID ?? "skill-runtime",
                    sessionID: sessionID,
                    capability: capability,
                    toolName: "skill:\(definition.slug)",
                    payloadJSON: "{\"skillID\":\"\(definition.slug)\"}"
                )
            }
            let registryEvent = AgentProductOSRegistryEvent(
                runID: runID,
                sessionID: sessionID,
                registryKind: "skill",
                entryID: definition.slug,
                status: .enabled,
                message: "Skill \(definition.slug) activated for \(trigger.rawValue)."
            )
            return SkillInstructionBundle(
                skill: definition,
                instructions: renderInstructions(definition),
                requiredSources: definition.manifest.requiredSources,
                permissionRequests: permissionRequests,
                registryEvent: registryEvent
            )
        }
        return nil
    }

    private func renderInstructions(_ definition: SkillRuntimeDefinition) -> String {
        """
        # \(definition.manifest.name)

        Description: \(definition.manifest.description)
        Skill ID: \(definition.slug)
        Scope: \(definition.scope.rawValue)
        Graph context policy: \(definition.manifest.graphContextPolicy.rawValue)

        \(definition.instructions)
        """
    }

    private func matchesGlobs(_ globs: [String], filePaths: [String]) -> Bool {
        guard !globs.isEmpty else { return true }
        guard !filePaths.isEmpty else { return false }
        return filePaths.contains { path in
            globs.contains { glob in
                matches(glob: glob, path: path)
            }
        }
    }

    private func matches(glob: String, path: String) -> Bool {
        if glob == "*" { return true }
        if glob.hasPrefix("*.") {
            return path.hasSuffix(String(glob.dropFirst()))
        }
        if glob.hasSuffix("/*") {
            return path.hasPrefix(String(glob.dropLast(1)))
        }
        return path == glob || path.hasSuffix("/\(glob)")
    }
}
