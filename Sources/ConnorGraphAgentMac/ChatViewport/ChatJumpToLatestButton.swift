import SwiftUI

struct ChatJumpToLatestButton: View {
    var pendingCount: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: AgentChatTypography.sendIconSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: AgentChatLayout.primaryButtonSize, height: AgentChatLayout.primaryButtonSize)
                .background(.regularMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 7, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
        .contentShape(Circle())
        .accessibilityLabel(pendingCount > 0 ? "滚动到最新消息，\(pendingCount) 条新消息" : "滚动到最新消息")
        .help("滚动到最新消息")
    }
}
