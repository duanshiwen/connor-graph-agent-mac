import SwiftUI
import AppKit

enum ConnorCraftPalette {
    // Mirrors Craft Agents OSS renderer tokens:
    // --background: light oklch(0.98 0.003 265), dark oklch(0.2 0.005 270)
    // --foreground: light oklch(0.185 0.01 270), dark oklch(0.92 0.005 270)
    // --accent: light oklch(0.62 0.13 293), dark oklch(0.65 0.20 293)
    static let background = dynamicColor(light: "#F7F8FA", dark: "#151618")
    static let foreground = dynamicColor(light: "#111317", dark: "#E3E4E8")
    static let accent = dynamicColor(light: "#8A75CD", dark: "#9770FC")
    static let userBubble = foreground.opacity(0.05)
    static let userBubbleDimmed = foreground.opacity(0.03)
    static let sendButton = foreground
    static let sendButtonForeground = background
    static let stopButton = foreground.opacity(0.05)
    static let accentSoftFill = accent.opacity(0.14)
    static let accentSubtleFill = accent.opacity(0.08)
    static let accentBorder = accent.opacity(0.28)

    private static func dynamicColor(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return nsColor(hex: dark)
            }
            return nsColor(hex: light)
        })
    }

    private static func nsColor(hex: String) -> NSColor {
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            return .controlAccentColor
        }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

enum AgentChatTypography {
    // Keep a small, semantic scale instead of one-off sizes. Apple HIG recommends
    // using font size, weight, and color to preserve legibility and hierarchy.
    static let largeIconSize: CGFloat = 48
    static let controlIconSize: CGFloat = 15
    static let smallIconSize: CGFloat = 13
    static let chevronIconSize: CGFloat = 13
    static let sendIconSize: CGFloat = 15

    static let title = AppTypography.paneTitle
    static let sectionTitle = AppTypography.sectionTitle
    static let sessionTitle = AppTypography.body
    static let sessionTitleEmphasis = AppTypography.bodyEmphasis
    static let body = AppTypography.body
    static let bodyEmphasis = AppTypography.bodyEmphasis
    static func messageBody(pointSize: CGFloat) -> Font { .system(size: pointSize) }
    static let callout = AppTypography.callout
    static let calloutEmphasis = AppTypography.calloutEmphasis
    static let meta = AppTypography.meta
    static let metaEmphasis = AppTypography.metaEmphasis
    static let micro = AppTypography.caption
    static let microEmphasis = AppTypography.captionEmphasis
    static let monoMeta = AppTypography.monoMeta
    static let monoMetaEmphasis = AppTypography.monoMetaEmphasis
    static let monoMicro = AppTypography.monoMicro

    static var composerNSFont: NSFont { .preferredFont(forTextStyle: .body) }
}

enum AgentChatFontPreferences {
    static let messageBodyPointSizeKey = "agentChat.messageBodyPointSize"
    static let messageBodyPointSizeRange = 11.0...22.0

    static var systemBodyPointSize: CGFloat {
        NSFont.preferredFont(forTextStyle: .body).pointSize
    }

    static var defaultMessageBodyPointSize: Double {
        Double(systemBodyPointSize)
    }

    static func validatedMessageBodyPointSize(_ pointSize: Double) -> CGFloat {
        CGFloat(pointSize.clamped(to: messageBodyPointSizeRange))
    }

    static func pointSizeLabel(_ pointSize: Double) -> String {
        "\(Int(pointSize.rounded())) pt"
    }
}

struct AgentComposerPopoverEmptyState: View {
    var title: String
    var systemImage: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            Text(title)
                .font(AgentChatTypography.sectionTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .font(AgentChatTypography.meta)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum AgentChatLayout {
    static let spaceXS = AppShellLayout.spaceXS
    static let spaceS = AppShellLayout.spaceS
    static let spaceM = AppShellLayout.spaceM
    static let spaceL = AppShellLayout.spaceL
    static let spaceXL = AppShellLayout.spaceXL

    static let radiusS = AppShellLayout.radiusS
    static let radiusM = AppShellLayout.radiusM
    static let radiusL = AppShellLayout.radiusL
    static let radiusXL: CGFloat = 20

    static let hairlineOpacity: Double = 0.14
    static let chipHeight = AppButtonLayout.height
    static let iconButtonSize = AppButtonLayout.iconButtonSize
    static let primaryButtonSize = AppButtonLayout.iconButtonSize
    static let hitTargetSize: CGFloat = 44
    static let activityRowMinHeight: CGFloat = 24
    static let composerTextMinHeight: CGFloat = 56
    static let composerTextMaxHeight: CGFloat = 120
    static let composerInfoButtonWidth: CGFloat = 78
    static let modelMenuMaxWidth: CGFloat = 176

    static let chatContentMaxWidth: CGFloat = 740
    static let chatViewportSpacing: CGFloat = 16
    static let chatViewportVerticalInset: CGFloat = 20
    static let chatViewportHorizontalInset: CGFloat = 0
    static let chatBottomPinnedThreshold: CGFloat = 72
    static let jumpToLatestButtonBottomInset: CGFloat = 12
    static let jumpToLatestButtonTrailingInset: CGFloat = 12
    static let messageMaxWidth: CGFloat = chatContentMaxWidth
    static let userMessageMaxWidth: CGFloat = chatContentMaxWidth * 0.70
    static let processMaxWidth: CGFloat = chatContentMaxWidth
    static let messageSideInset: CGFloat = 0
    static let messageBubbleHorizontalPadding = AppShellLayout.spaceL
    static let messageBubbleVerticalPadding = AppShellLayout.spaceM
    static let assistantMessageTrailingPadding: CGFloat = 4

    static let avatarSize: CGFloat = 28
}
