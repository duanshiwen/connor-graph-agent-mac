import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

/// Compact permission control embedded in the input toolbar.
struct AgentComposerOptionBar: View {
    var composerState: AgentComposerState
    var onAction: (AgentComposerAction) -> Void

    var body: some View {
        Menu {
            ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                Button {
                    onAction(.setPermissionMode(mode))
                } label: {
                    if mode == composerState.permissionMode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            AgentComposerOptionBadge(
                title: composerState.permissionMode.displayName,
                systemImage: "lock",
                tint: .accentColor,
                isActive: true,
                style: .compact,
                showsBorder: false,
                fill: Color.accentColor.opacity(0.10)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("调整本轮会话权限")
        .accessibilityLabel("操作权限：\(composerState.permissionMode.displayName)")
    }
}

struct SpeechInputProvisionalTranscriptView: View {
    var transcript: String?

    var body: some View {
        if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .top, spacing: AgentChatLayout.spaceXS) {
                Image(systemName: "waveform")
                    .font(.system(size: AgentChatTypography.smallIconSize, weight: .medium))
                Text(transcript)
                    .font(AgentChatTypography.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(AgentChatLayout.spaceM)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
