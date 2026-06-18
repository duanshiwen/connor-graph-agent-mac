import Foundation

public struct SkillAgentPromptBuilder: Sendable {
    public var fallbackPlanner: SkillCreationFallbackPlanner

    public init(fallbackPlanner: SkillCreationFallbackPlanner = SkillCreationFallbackPlanner()) {
        self.fallbackPlanner = fallbackPlanner
    }

    public func addSkillPrompt(userRequest: String, skillRootPath: String, existingSlugs: Set<String>) -> String {
        let suggestion = fallbackPlanner.suggestedIdentity(for: userRequest, existingSlugs: existingSlugs)
        return """
        你正在帮助用户为 Connor 创建一个新技能。用户在“添加技能”弹窗中输入了以下需求：

        \(userRequest)

        请按成熟技能创建流程工作：
        1. 如果需求不清楚，先用简短问题澄清技能的用途、触发时机、输入、输出和约束。
        2. 如果需求足够清楚，必须调用 `connor_skill_create` 创建技能；不要只在回复中说“已添加”。
        3. 推荐技能名称：\(suggestion.name)
        4. 推荐 slug：\(suggestion.slug)
        5. 目标目录：\(skillRootPath)/\(suggestion.slug)/
        6. `connor_skill_create` 的 instructions 参数应包含完整 Markdown 工作流说明，包括适用场景、步骤、输出格式和注意事项。
        7. 用户创建的技能必须是可见技能，不要写入或要求写入 `hidden: true`；隐藏技能只允许 Connor 内置 bundled skills 使用。
        8. 创建完成后，请验证技能可以被 Connor 扫描，并告诉用户技能名称、slug 和文件路径。

        首选工具：`connor_skill_create`。只有当该工具不可用时，才使用通用文件写入工具，并明确说明降级原因。
        """
    }

    public func editSkillPrompt(card: SkillManagerCard, userRequest: String) -> String {
        return """
        你正在帮助用户修改一个已有 Connor 技能。用户在“编辑技能”弹窗中输入了以下修改需求：

        \(userRequest)

        当前技能信息：
        - slug: \(card.id)
        - name: \(card.title)
        - description: \(card.subtitle)
        - source tier: \(card.sourceTier)
        - skill file: \(card.path)
        - package: \(card.packagePath)
        - risk: \(card.riskLabel)
        - lifecycle: \(card.lifecycleLabel)
        - required sources: \(card.requiredSources.joined(separator: ", "))
        - permissions: \(card.permissionLabels.joined(separator: ", "))

        当前技能正文：
        ```markdown
        \(card.instructions)
        ```

        请按成熟技能修改流程工作：
        1. 如果修改需求不清楚，先简短澄清。
        2. 如果需求足够清楚，必须调用 `connor_skill_update` 修改 slug 为 `\(card.id)` 的技能；不要只回复修改建议。
        3. 尽量保留当前技能的有效结构，只调整用户要求改变的部分。
        4. 修改完成后，请说明修改了什么，并确认技能仍可被 Connor 扫描。

        首选工具：`connor_skill_update`。只有当该工具不可用时，才使用通用文件编辑工具，并明确说明降级原因。
        """
    }
}
