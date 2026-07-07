import SwiftUI
import ConnorGraphCore

struct PersonMentionPickerView: View {
    var query: String
    var profiles: [PersonProfile]
    var selectionIndex: Int
    var onSelect: (PersonProfile) -> Void

    private var results: [PersonProfile] {
        PersonMentionSearch().search(query: query, profiles: profiles, limit: 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text(query.isEmpty ? "选择人物" : "没有匹配的人物")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AgentChatLayout.spaceM)
                    .padding(.vertical, AgentChatLayout.spaceS)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        onSelect(profile)
                    } label: {
                        HStack(spacing: AgentChatLayout.spaceS) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(AgentChatTypography.metaEmphasis)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(profile.contactSubtitle)
                                    .font(AgentChatTypography.micro)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: AgentChatLayout.spaceS)
                        }
                        .padding(.horizontal, AgentChatLayout.spaceM)
                        .padding(.vertical, AgentChatLayout.spaceS)
                        .background(index == selectionIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择人物：\(profile.displayName)")
                }
            }
        }
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(query.isEmpty ? "人物选择列表" : "人物选择列表，搜索：\(query)")
    }
}
