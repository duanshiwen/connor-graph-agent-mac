import SwiftUI
import ConnorGraphCore

struct SpeechInputHoldToTalkButton: View {
    var isEnabled: Bool
    var status: SessionSpeechTranscriptionStatus
    var onBegin: () -> Void
    var onEnd: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceXS) {
            Image(systemName: iconName)
                .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(AgentChatTypography.meta.weight(.medium))
                .lineLimit(1)
            if status.isFinalizing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, AgentChatLayout.spaceM)
        .frame(minWidth: 190, minHeight: AgentChatLayout.hitTargetSize)
        .background(background, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginIfNeeded() }
                .onEnded { _ in endIfNeeded() }
        )
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled && !status.isFinalizing)
        .help(helpText)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch status {
        case .recording:
            "正在听… 松开结束"
        case .finalizing:
            "正在优化识别结果…"
        case .failed:
            "语音输入失败"
        case .idle:
            "按住说话 · 鼠标按住或按住 Option"
        }
    }

    private var iconName: String {
        switch status {
        case .recording: "mic.fill"
        case .finalizing: "waveform"
        case .failed: "exclamationmark.triangle"
        case .idle: "mic"
        }
    }

    private var foreground: Color {
        switch status {
        case .recording, .finalizing: .accentColor
        case .failed: .orange
        case .idle: .secondary
        }
    }

    private var background: Color {
        switch status {
        case .recording: Color.accentColor.opacity(0.16)
        case .finalizing: Color.accentColor.opacity(0.10)
        case .failed: Color.orange.opacity(0.10)
        case .idle: Color.secondary.opacity(0.06)
        }
    }

    private var border: Color {
        switch status {
        case .recording, .finalizing: Color.accentColor.opacity(0.30)
        case .failed: Color.orange.opacity(0.30)
        case .idle: Color.secondary.opacity(0.12)
        }
    }

    private var helpText: String {
        guard isEnabled else { return "请选择一个会话后再开始语音输入" }
        return "鼠标按住开始录音，松开后 Connor 会用完整音频再识别一遍以提高准确度。键盘可按住 Option。长按空格可在设置中开启，但默认关闭。"
    }

    private func beginIfNeeded() {
        guard isEnabled, !isPressed, !status.isRunning else { return }
        isPressed = true
        onBegin()
    }

    private func endIfNeeded() {
        guard isPressed else { return }
        isPressed = false
        onEnd()
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
