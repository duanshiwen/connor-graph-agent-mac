import Foundation

public struct AgentPromptModuleID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let preamble: Self = "preamble"
    public static let runtimeRetrievalPlan: Self = "runtime_retrieval_plan"
    public static let conversationalProgress: Self = "conversational_progress"
    public static let instructionAppendix: Self = "instruction_appendix"
    public static let environmentSnapshot: Self = "environment_snapshot"
    public static let activatedSkill: Self = "activated_skill"
}

public enum AgentPromptCapability: String, Hashable, Sendable, Codable {
    case currentTime
    case memory
    case note
    case skills
    case people
    case calendar
    case mail
    case rss
    case browserHistory
    case cloudKnowledge
    case web
    case images
    case environment
    case sessions
    case workspace
}

public enum AgentPromptModuleRequirement: Sendable, Equatable {
    case always
    case allOf(Set<AgentPromptCapability>)
    case anyOf(Set<AgentPromptCapability>)

    public func isSatisfied(by capabilities: Set<AgentPromptCapability>) -> Bool {
        switch self {
        case .always:
            return true
        case .allOf(let required):
            return required.isSubset(of: capabilities)
        case .anyOf(let required):
            return !required.isDisjoint(with: capabilities)
        }
    }
}

public struct AgentPromptModule: Sendable, Equatable, Identifiable {
    public var id: AgentPromptModuleID
    public var title: String?
    public var content: String
    public var requirement: AgentPromptModuleRequirement

    public init(
        id: AgentPromptModuleID,
        title: String? = nil,
        content: String,
        requirement: AgentPromptModuleRequirement = .always
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.requirement = requirement
    }

    public var renderedText: String {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title else { return body }
        return body.isEmpty ? "## \(title)" : "## \(title)\n\(body)"
    }
}

public struct AgentPromptDocument: Sendable, Equatable {
    public var modules: [AgentPromptModule]

    public init(modules: [AgentPromptModule] = []) {
        self.modules = modules
    }

    public var renderedText: String {
        modules.map(\.renderedText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public var moduleIDs: [AgentPromptModuleID] { modules.map(\.id) }

    public func projected(for capabilities: Set<AgentPromptCapability>) -> Self {
        Self(modules: modules.filter { $0.requirement.isSatisfied(by: capabilities) })
    }

    public mutating func append(_ module: AgentPromptModule) {
        modules.append(module)
    }
}

public struct AgentPromptModuleSpecification: Sendable, Equatable {
    public var id: AgentPromptModuleID
    public var title: String
    public var requirement: AgentPromptModuleRequirement
    public var summary: String
    public var dependencies: [AgentPromptModuleID]
    public var toolFamilies: Set<String>

    public init(
        id: AgentPromptModuleID,
        title: String,
        requirement: AgentPromptModuleRequirement = .always,
        summary: String = "",
        dependencies: [AgentPromptModuleID] = [],
        toolFamilies: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.requirement = requirement
        self.summary = summary.isEmpty ? title : summary
        self.dependencies = dependencies
        self.toolFamilies = toolFamilies
    }
}

public enum AgentPromptModuleCatalog {
    private static let nativeSourceCapabilities: Set<AgentPromptCapability> = [.calendar, .mail, .rss, .browserHistory]

    public static let specifications: [AgentPromptModuleSpecification] = [
        .init(id: "identity", title: "Identity"),
        .init(id: "priority_order", title: "Priority Order"),
        .init(id: "cross_run_continuity", title: "Cross-Run Continuity"),
        .init(id: "intermediate_messages", title: "Intermediate Messages and the Final Response"),
        .init(id: "personality_configuration", title: "Personality Configuration"),
        .init(id: "confidentiality", title: "Confidentiality and Non-Disclosure"),
        .init(id: "tool_usage_contract", title: "Tool Usage Contract"),
        .init(id: "environment_tool_rules", title: "Environment Tool Rules", requirement: .allOf([.environment])),
        .init(id: "tool_chaining_pagination", title: "Tool Chaining and Pagination"),
        .init(id: "workspace_tool_rules", title: "Workspace Tool Rules", requirement: .allOf([.workspace]), toolFamilies: ["workspace"]),
        .init(id: "current_time_tool_contract", title: "Current Time Tool Contract", requirement: .allOf([.currentTime])),
        .init(id: "session_status_tool_rules", title: "Session Status Tool Rules", requirement: .allOf([.sessions])),
        .init(id: "workspace_execution_rules", title: "Workspace Execution Rules", requirement: .allOf([.workspace]), dependencies: ["workspace_tool_rules"], toolFamilies: ["workspace"]),
        .init(id: "tool_failure_safety", title: "Tool Failure and Safety Rules"),
        .init(id: "file_handoff_reuse", title: "File Handoff, Retrieval, and Reuse", requirement: .allOf([.workspace]), toolFamilies: ["workspace"]),
        .init(id: "note_session_file_boundary", title: "Note Session File Boundary", requirement: .allOf([.workspace, .note])),
        .init(id: "programming_precision", title: "Programming and Precision Work", requirement: .allOf([.workspace]), dependencies: ["workspace_execution_rules"], toolFamilies: ["workspace"]),
        .init(id: "memory_architecture", title: "Memory OS Architecture", requirement: .allOf([.memory]), toolFamilies: ["memory"]),
        .init(id: "note_reference_materials", title: "Note Reference Materials", requirement: .allOf([.note])),
        .init(id: "core_startup", title: "Core Startup and Continuity Checkpoint"),
        .init(id: "current_time_retrieval", title: "Current Time Retrieval Rules", requirement: .allOf([.currentTime])),
        .init(id: "memory_retrieval", title: "Memory Retrieval Rules", requirement: .allOf([.memory]), dependencies: ["memory_architecture"], toolFamilies: ["memory"]),
        .init(id: "calendar_retrieval", title: "Calendar Retrieval Rules", requirement: .allOf([.calendar]), toolFamilies: ["calendar"]),
        .init(id: "mail_retrieval", title: "Mail Retrieval Rules", requirement: .allOf([.mail]), toolFamilies: ["mail"]),
        .init(
            id: "proactive_reminder_judgment",
            title: "Proactive Reminder Judgment",
            requirement: .anyOf([.calendar, .mail]),
            dependencies: ["calendar_retrieval", "mail_retrieval"],
            toolFamilies: ["calendar", "mail"]
        ),
        .init(id: "skill_discovery", title: "Skill Discovery Rules", requirement: .allOf([.skills]), toolFamilies: ["skills"]),
        .init(id: "note_retrieval", title: "Note Retrieval Rules", requirement: .allOf([.note]), toolFamilies: ["note"]),
        .init(id: "cloud_knowledge_retrieval", title: "Cloud Knowledge Retrieval Rules", requirement: .allOf([.cloudKnowledge]), toolFamilies: ["external-research"]),
        .init(id: "web_research", title: "Web Research Rules", requirement: .allOf([.web]), toolFamilies: ["external-research"]),
        .init(id: "retrieval_completion", title: "Retrieval Completion Rules"),
        .init(id: "skill_instruction_authority", title: "Skill Instruction Authority"),
        .init(id: "connor_skill_tools", title: "Connor Skill Tools", requirement: .allOf([.skills])),
        .init(id: "evidence_finalization", title: "Evidence, Tool Output, and Finalization"),
        .init(id: "person_registry", title: "Person Registry and Relationships", requirement: .allOf([.people])),
        .init(id: "native_personal_sources", title: "Native Personal Source Tools", requirement: .anyOf(nativeSourceCapabilities)),
        .init(id: "mail_tool_workflow", title: "Mail Tool Workflow", requirement: .allOf([.mail]), dependencies: ["mail_retrieval"], toolFamilies: ["mail"]),
        .init(id: "calendar_tool_workflow", title: "Calendar Tool Workflow", requirement: .allOf([.calendar]), dependencies: ["calendar_retrieval"], toolFamilies: ["calendar"]),
        .init(id: "rss_tool_workflow", title: "RSS Tool Workflow", requirement: .allOf([.rss]), toolFamilies: ["rss"]),
        .init(id: "browser_history_workflow", title: "Browser History Tool Workflow", requirement: .allOf([.browserHistory]), toolFamilies: ["browser-history"]),
        .init(id: "native_source_evidence", title: "Native Source Evidence Rules", requirement: .anyOf(nativeSourceCapabilities)),
        .init(id: "personal_continuity", title: "Personal Continuity and Tailoring", requirement: .allOf([.memory])),
        .init(id: "rich_media", title: "Rich Media Responses", requirement: .allOf([.images])),
        .init(id: "stop_conditions", title: "Stop Conditions"),
        .init(id: "response_style", title: "Response Style"),
        .init(id: "runtime_environment", title: "Runtime Environment")
    ]

    public static var specificationByID: [AgentPromptModuleID: AgentPromptModuleSpecification] {
        Dictionary(uniqueKeysWithValues: specifications.map { ($0.id, $0) })
    }

    public static var duplicateIDs: [AgentPromptModuleID] {
        Dictionary(grouping: specifications, by: \.id).filter { $0.value.count > 1 }.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public static var dependencyCycles: [[AgentPromptModuleID]] {
        let byID = specificationByID
        var visiting = Set<AgentPromptModuleID>()
        var visited = Set<AgentPromptModuleID>()
        var stack: [AgentPromptModuleID] = []
        var cycles: [[AgentPromptModuleID]] = []
        func visit(_ id: AgentPromptModuleID) {
            if let index = stack.firstIndex(of: id) {
                cycles.append(Array(stack[index...]) + [id])
                return
            }
            guard !visited.contains(id), !visiting.contains(id), let specification = byID[id] else { return }
            visiting.insert(id)
            stack.append(id)
            specification.dependencies.sorted { $0.rawValue < $1.rawValue }.forEach(visit)
            _ = stack.popLast()
            visiting.remove(id)
            visited.insert(id)
        }
        specifications.map(\.id).sorted { $0.rawValue < $1.rawValue }.forEach(visit)
        return cycles
    }

    public static func document(from markdown: String) -> AgentPromptDocument {
        let specificationsByTitle = Dictionary(uniqueKeysWithValues: specifications.map { ($0.title, $0) })
        var modules: [AgentPromptModule] = []
        var currentSpecification: AgentPromptModuleSpecification?
        var currentTitle: String?
        var currentLines: [String] = []
        var customIndex = 0

        func makeCustomID(title: String?) -> AgentPromptModuleID {
            customIndex += 1
            let stem = title?
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_")) ?? "preamble"
            return AgentPromptModuleID(rawValue: "custom_\(stem)_\(customIndex)")
        }

        func flush() {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentTitle != nil || !content.isEmpty else { return }
            if let currentSpecification {
                modules.append(AgentPromptModule(
                    id: currentSpecification.id,
                    title: currentSpecification.title,
                    content: content,
                    requirement: currentSpecification.requirement
                ))
            } else if currentTitle == nil, modules.isEmpty {
                modules.append(AgentPromptModule(id: .preamble, content: content))
            } else {
                modules.append(AgentPromptModule(id: makeCustomID(title: currentTitle), title: currentTitle, content: content))
            }
            currentLines = []
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                let title = String(line.dropFirst(3))
                currentTitle = title
                currentSpecification = specificationsByTitle[title]
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return AgentPromptDocument(modules: modules)
    }

    public static func unclassifiedHeadings(in markdown: String) -> [String] {
        let knownTitles = Set(specifications.map(\.title))
        return markdown.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("## ") else { return nil }
            let title = String(line.dropFirst(3))
            return knownTitles.contains(title) ? nil : title
        }
    }
}

public enum AgentPromptCapabilityResolver {
    private static let workspaceToolNames: Set<String> = ["Shell", "ApplyPatch"]

    public static func capabilities(for toolNames: Set<String>) -> Set<AgentPromptCapability> {
        var result = Set<AgentPromptCapability>()
        func include(_ capability: AgentPromptCapability, when predicate: (String) -> Bool) {
            if toolNames.contains(where: predicate) { result.insert(capability) }
        }

        include(.currentTime) { $0 == AgentCurrentTimePreflightPolicy.requiredToolName }
        include(.memory) { $0.hasPrefix("memory_os_") }
        include(.note) { $0.hasPrefix("note_") }
        include(.skills) { $0.hasPrefix("connor_skill_") }
        include(.people) { $0.hasPrefix("contact") || $0.hasPrefix("person_") }
        include(.calendar) { $0.hasPrefix("calendar_") }
        include(.mail) { $0.hasPrefix("mail_") }
        include(.rss) { $0.hasPrefix("rss_") }
        include(.browserHistory) { $0.hasPrefix("browser_history_") }
        include(.cloudKnowledge) { $0.hasPrefix("cloud_kb_") }
        include(.web) { $0.hasPrefix("web_") }
        include(.images) { ["generate_image", "edit_image", "image_search", "present_image"].contains($0) }
        include(.environment) { $0 == "get_current_environment" || $0.hasPrefix("environment_") }
        include(.sessions) { $0.hasPrefix("session_") }
        include(.workspace) { workspaceToolNames.contains($0) || $0.hasPrefix("local_") || $0.hasPrefix("workspace_") }
        return result
    }
}
