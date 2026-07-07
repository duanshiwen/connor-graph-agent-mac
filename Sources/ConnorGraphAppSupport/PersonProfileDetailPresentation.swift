import Foundation
import ConnorGraphCore

public struct PersonProfileDetailPresentation: Sendable, Equatable {
    public var profile: PersonProfile
    public var aliasesText: String
    public var memoryBindingTitle: String
    public var memoryBindingDetail: String
    public var memorySummary: String

    public init(profile: PersonProfile) {
        self.profile = profile
        let aliases = profile.aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.aliasesText = aliases.isEmpty ? "暂无别名" : aliases.joined(separator: ", ")

        let stableKey = profile.memoryStableKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let entityID = profile.memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stableKey.isEmpty || !entityID.isEmpty {
            self.memoryBindingTitle = "已连接 Memory OS"
            let detailParts = [
                stableKey.isEmpty ? nil : "stable key: \(stableKey)",
                entityID.isEmpty ? nil : "entity: \(entityID)"
            ].compactMap { $0 }
            self.memoryBindingDetail = detailParts.joined(separator: " · ")
        } else {
            self.memoryBindingTitle = "尚未连接 Memory OS"
            self.memoryBindingDetail = "保存或同步后会自动建立人物记忆锚点。"
        }

        let notes = profile.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.memorySummary = notes.isEmpty ? "暂无人物记忆摘要" : notes
    }
}
