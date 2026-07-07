import SwiftUI
import ConnorGraphCore

struct PersonMentionPickerRowPresentation: Equatable, Identifiable {
    var id: ContactID { profile.id }
    var profile: PersonProfile
    var displayName: String
    var subtitle: String

    var accessibilityLabel: String {
        "选择人物，\(displayName)，\(subtitle)"
    }
}

struct PersonMentionPickerPresentation: Equatable {
    var query: String
    var selectionIndex: Int
    var rows: [PersonMentionPickerRowPresentation]

    init(query: String, profiles: [PersonProfile], selectionIndex: Int) {
        let results = PersonMentionSearch().search(query: query, profiles: profiles, limit: 8)
        self.query = query
        self.selectionIndex = selectionIndex
        self.rows = results.map { profile in
            PersonMentionPickerRowPresentation(
                profile: profile,
                displayName: profile.displayName,
                subtitle: profile.contactSubtitle
            )
        }
    }

    var title: String { "选择人物" }

    var subtitle: String {
        if rows.isEmpty {
            return trimmedQuery.isEmpty ? "输入姓名、别名或联系方式筛选" : "搜索“\(trimmedQuery)”"
        }
        return "\(rows.count) 个匹配人物"
    }

    var emptyTitle: String {
        trimmedQuery.isEmpty ? "选择人物" : "没有匹配的人物"
    }

    var emptySubtitle: String {
        trimmedQuery.isEmpty ? "继续输入姓名、别名或联系方式筛选" : "继续输入，或调整姓名、别名、联系方式关键词"
    }

    var keyboardHint: String { "↑↓ 选择   Return 确认   Esc 关闭" }

    var clampedSelectionIndex: Int {
        guard !rows.isEmpty else { return 0 }
        return min(max(selectionIndex, 0), rows.count - 1)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PersonMentionPickerView: View {
    var query: String
    var profiles: [PersonProfile]
    var selectionIndex: Int
    var onSelect: (PersonProfile) -> Void

    private var presentation: PersonMentionPickerPresentation {
        PersonMentionPickerPresentation(query: query, profiles: profiles, selectionIndex: selectionIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .opacity(0.55)

            if presentation.rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                        rowButton(row, isSelected: index == presentation.clampedSelectionIndex)
                    }
                }
                .padding(.vertical, AgentChatLayout.spaceXS)
            }

            Divider()
                .opacity(0.45)

            footer
        }
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("人物选择器")
    }

    private var header: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Image(systemName: "person.2")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(AgentChatTypography.metaEmphasis)
                    .foregroundStyle(.primary)
                Text(presentation.subtitle)
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AgentChatLayout.spaceS)
        }
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, AgentChatLayout.spaceS)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: AgentChatLayout.spaceXS) {
            Image(systemName: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "at.circle" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(presentation.emptyTitle)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.primary)
            Text(presentation.emptySubtitle)
                .font(AgentChatTypography.micro)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AgentChatLayout.spaceL)
        .padding(.vertical, AgentChatLayout.spaceL)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        Text(presentation.keyboardHint)
            .font(AgentChatTypography.micro)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceXS)
            .accessibilityHidden(true)
    }

    private func rowButton(_ row: PersonMentionPickerRowPresentation, isSelected: Bool) -> some View {
        Button {
            onSelect(row.profile)
        } label: {
            HStack(spacing: AgentChatLayout.spaceS) {
                selectionIndicator(isSelected: isSelected)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayName)
                        .font(AgentChatTypography.metaEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AgentChatLayout.spaceS)

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceS)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.clear)
            .frame(width: 3, height: 28)
            .accessibilityHidden(true)
    }
}
