import SwiftUI

struct AgentSendControlButton: View {
    var isSubmitting: Bool
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSubmitting ? "stop.fill" : "arrow.up")
                .font(.system(size: AgentChatTypography.sendIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: AgentChatLayout.primaryButtonSize, height: AgentChatLayout.primaryButtonSize)
                .background(buttonBackground, in: Circle())
                .overlay(Circle().stroke(buttonBorder, lineWidth: 1))
                .shadow(color: buttonShadow, radius: 7, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSubmitting ? ConnorCraftPalette.foreground : ConnorCraftPalette.sendButtonForeground)
        .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
        .contentShape(Circle())
        .opacity(isDisabled ? 0.42 : 1)
        .disabled(isDisabled)
    }

    private var buttonBackground: Color {
        isSubmitting ? ConnorCraftPalette.stopButton : ConnorCraftPalette.sendButton
    }

    private var buttonBorder: Color {
        isSubmitting ? ConnorCraftPalette.foreground.opacity(0.10) : ConnorCraftPalette.foreground.opacity(0.08)
    }

    private var buttonShadow: Color {
        isDisabled || isSubmitting ? Color.clear : ConnorCraftPalette.foreground.opacity(0.12)
    }
}
