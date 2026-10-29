import SwiftUI
import AppKit

enum ConnorCraftPalette {
    // 与 Android ConnorTheme 对齐：浅色深金文字、深色品牌黄，保持可读对比。
    static let brandYellow = dynamicColor(light: "#FFD84D", dark: "#FFD84D")
    static let background = dynamicColor(light: "#F6F6F7", dark: "#141416")
    static let foreground = dynamicColor(light: "#242528", dark: "#EEEEF0")
    static let accent = dynamicColor(light: "#715600", dark: "#FFD84D")
    static let onAccent = dynamicColor(light: "#FFFFFF", dark: "#101820")
    static let surface = dynamicColor(light: "#FFFFFF", dark: "#1E1E21")
    static let surfaceVariant = dynamicColor(light: "#F1F1F3", dark: "#252528")
    static let accentContainer = dynamicColor(light: "#FFF3C4", dark: "#544400")
    static let onAccentContainer = dynamicColor(light: "#101820", dark: "#FFE89B")
    static let userBubble = foreground.opacity(0.05)
    static let userBubbleDimmed = foreground.opacity(0.03)
    static let sendButton = brandYellow
    static let sendButtonForeground = dynamicColor(light: "#101820", dark: "#101820")
    static let stopButton = foreground.opacity(0.05)
    static let accentSoftFill = accentContainer
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

    static var composerNSFont: NSFont {
        .systemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize + 1)
    }

    static var composerMonospacedNSFont: NSFont {
        .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }
}

struct AgentMessageExpansionButton: View {
    var title: String
    var systemImage: String
    var accessibilityLabel: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .imageScale(.small)
                Text(title)
                    .font(AgentChatTypography.microEmphasis)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }
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
    static let primaryButtonSize: CGFloat = 30
    static let hitTargetSize: CGFloat = 44
    static let activityRowMinHeight: CGFloat = 24
    static let composerTextMinHeight: CGFloat = 56
    static let composerTextMaxHeight: CGFloat = 120
    static let composerInfoButtonWidth: CGFloat = 78
    static let modelMenuMaxWidth: CGFloat = 176

    static let chatContentMaxWidth: CGFloat = 740
    static let chatViewportSpacing: CGFloat = 16
    static let assistantGroupSpacing: CGFloat = 8
    static let conversationTurnSpacing: CGFloat = 20
    static let chatViewportVerticalInset: CGFloat = 20
    static let chatViewportHorizontalInset: CGFloat = 0
    static let chatBottomPinnedThreshold: CGFloat = 8
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
    static let assistantIdentityContentSpacing: CGFloat = 8
}
