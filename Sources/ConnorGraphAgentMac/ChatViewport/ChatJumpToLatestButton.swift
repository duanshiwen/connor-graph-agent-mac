import SwiftUI

struct ChatJumpToLatestButton: View {
    var pendingCount: Int
    var action: () -> Void

    private var title: String {
        pendingCount > 0 ? "\(pendingCount) 条新消息" : "跳到最新"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AgentChatLayout.spaceS) {
                Image(systemName: "arrow.down")
                    .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                Text(title)
                    .font(AgentChatTypography.microEmphasis)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AgentChatLayout.spaceM)
            .frame(minWidth: AgentChatLayout.hitTargetSize, minHeight: AgentChatLayout.hitTargetSize)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pendingCount > 0 ? "滚动到最新消息，\(pendingCount) 条新消息" : "滚动到最新消息")
        .help("滚动到最新消息")
    }
}
