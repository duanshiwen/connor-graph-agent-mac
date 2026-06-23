import Foundation

public struct UserBasicInfoPromptBuilder: Sendable, Equatable {
    public var preferences: AgentRuntimePreferenceSettings

    public init(preferences: AgentRuntimePreferenceSettings) {
        self.preferences = preferences
    }

    public var promptSection: String {
        let rows: [(String, String)] = [
            ("称呼", preferences.displayName),
            ("时区", preferences.timezone),
            ("语言偏好", preferences.preferredLanguage),
            ("性别", preferences.genderIdentity),
            ("出生日期", preferences.birthDate),
            ("城市", preferences.city),
            ("国家/地区", preferences.country),
            ("备注", preferences.notes)
        ]
        let renderedRows = rows
            .map { label, value in (label, value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty }
            .map { "- \($0.0)：\($0.1)" }
        guard !renderedRows.isEmpty else { return "" }
        return (["## 用户基本信息"] + renderedRows).joined(separator: "\n")
    }

    public static func appendedInstruction(base: String, preferences: AgentRuntimePreferenceSettings) -> String {
        let section = UserBasicInfoPromptBuilder(preferences: preferences).promptSection
        guard !section.isEmpty else { return base }
        return [base.trimmingCharacters(in: .whitespacesAndNewlines), section]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
