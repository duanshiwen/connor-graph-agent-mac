import Foundation
import ConnorGraphCore
import ConnorGraphAgent

/// Internal tool that lets the model autonomously load full skill instructions
/// by slug. The system prompt includes a summary catalog of all available skills;
/// when the model identifies a relevant skill, it calls this tool to retrieve
/// the complete SKILL.md content.
public struct SkillActivateTool: AgentTool {
    public let name = "connor_skill_activate"
    public let description = "Load the full instructions for an installed skill by slug. Call this when the user's request maps to a skill domain listed in the available skills catalog. Returns the complete skill workflow and guidance."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "slug": .string(description: "The skill slug from the available skills catalog, for example analyze-pdf or code-review.")
    ], required: ["slug"])

    private let packages: [SkillPackage]

    public init(packages: [SkillPackage]) {
        self.packages = packages
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let slug = arguments.string("slug"), !slug.isEmpty else {
            throw AgentToolError.invalidArguments("slug is required")
        }
        guard let package = packages.first(where: { $0.slug.rawValue == slug }) else {
            let available = packages.map { $0.slug.rawValue }.sorted().joined(separator: ", ")
            let json = "{\"error\":\"skill_not_found\",\"slug\":\"\(slug)\"}"
            return AgentToolResult(
                toolCallID: context.toolCallID,
                toolName: name,
                contentText: "Skill not found: \(slug). Available skills: \(available.isEmpty ? "(none)" : available)",
                contentJSON: json,
                error: "Skill not found: \(slug)"
            )
        }
        let header = "# \(package.manifest.name) (slug: \(package.slug.rawValue))\n\n\(package.manifest.description)\n\n---\n\n"
        let json = "{\"slug\":\"\(package.slug.rawValue)\",\"name\":\"\(package.manifest.name)\",\"instructionLength\":\(package.instructions.count)}"
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: header + package.instructions,
            contentJSON: json
        )
    }
}

/// Generate a compact skill catalog summary for injection into the system prompt.
public func buildSkillCatalogSummary(from packages: [SkillPackage]) -> String {
    let visible = packages.sorted(by: { $0.slug.rawValue < $1.slug.rawValue })
    guard !visible.isEmpty else { return "" }
    var lines: [String] = []
    lines.append("## Available Skills")
    lines.append("")
    lines.append("You have access to the following skills. Each skill contains specialized instructions for a specific task domain. To use a skill, call the `connor_skill_activate` tool with the skill's slug.")
    lines.append("")
    for pkg in visible {
        let tags = pkg.manifest.tags.isEmpty ? "" : " [\(pkg.manifest.tags.joined(separator: ", "))]"
        lines.append("- **\(pkg.manifest.name)** (`\(pkg.slug.rawValue)`): \(pkg.manifest.description)\(tags)")
    }
    lines.append("")
    lines.append("### How to Use Skills")
    lines.append("1. **Read the user's request carefully** — if it maps to a skill domain listed above, activate that skill BEFORE proceeding.")
    lines.append("2. **Call `connor_skill_activate(slug)`** with the exact slug to load the full skill instructions.")
    lines.append("3. **Follow the loaded instructions** — treat them as your operational guide for this task.")
    lines.append("4. **One skill per task** — if multiple skills seem relevant, pick the most specific one.")
    lines.append("5. **Skills are optional guidance** — if no skill matches, proceed with your general capabilities.")
    lines.append("6. **Do not discover skills through the filesystem** — do not use Shell, List Directory, Find Files, or search tools to inspect skill directories. This catalog is the source of truth for user-visible skills.")
    return lines.joined(separator: "\n")
}

/// Tool that lets the model discover installed skills at runtime.
/// Prefer this over injecting the full catalog into the system prompt.
public struct SkillListTool: AgentTool {
    public let name = "connor_skill_list"
    public let description = "List all installed skills available for this session. Returns slug, name, description, and tags for each skill. Call this at the start of each conversation to check for available skills."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    private let packages: [SkillPackage]

    public init(packages: [SkillPackage]) {
        self.packages = packages
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let skills = packages.map { pkg -> [String: Any] in
            [
                "slug": pkg.slug.rawValue,
                "name": pkg.manifest.name,
                "description": pkg.manifest.description,
                "tags": pkg.manifest.tags
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: skills, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Found \(skills.count) installed skill(s): \(skills.compactMap { $0["name"] as? String }.joined(separator: ", ")).",
            contentJSON: json
        )
    }
}
