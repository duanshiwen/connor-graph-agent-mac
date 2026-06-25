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

    static let title: Font = .system(size: 15.5, weight: .semibold)
    static let sectionTitle: Font = .headline.weight(.semibold)
    static let sessionTitle: Font = .system(size: 15, weight: .regular)
    static let sessionTitleEmphasis: Font = .system(size: 15, weight: .semibold)
    static let body: Font = .system(size: 15)
    static let bodyEmphasis: Font = .system(size: 15, weight: .semibold)
    static let callout: Font = .system(size: 14)
    static let calloutEmphasis: Font = .system(size: 14, weight: .semibold)
    static let meta: Font = .system(size: 13)
    static let metaEmphasis: Font = .system(size: 13, weight: .semibold)
    static let micro: Font = .system(size: 12)
    static let microEmphasis: Font = .system(size: 12, weight: .semibold)
    static let monoMeta: Font = .system(size: 13, design: .monospaced)
    static let monoMetaEmphasis: Font = .system(size: 13, weight: .semibold, design: .monospaced)
    static let monoMicro: Font = .system(size: 12, design: .monospaced)

    static var composerNSFont: NSFont { .systemFont(ofSize: 16) }
}

enum AgentChatLayout {
    static let spaceXS: CGFloat = 3
    static let spaceS: CGFloat = 6
    static let spaceM: CGFloat = 10
    static let spaceL: CGFloat = 14
    static let spaceXL: CGFloat = 20

    static let radiusS: CGFloat = 7
    static let radiusM: CGFloat = 10
    static let radiusL: CGFloat = 14
    static let radiusXL: CGFloat = 18

    static let hairlineOpacity: Double = 0.14
    static let chipHeight: CGFloat = 30
    static let iconButtonSize: CGFloat = 32
    static let primaryButtonSize: CGFloat = 34
    static let hitTargetSize: CGFloat = 44
    static let activityRowMinHeight: CGFloat = 24
    static let composerTextMinHeight: CGFloat = 56
    static let composerTextMaxHeight: CGFloat = 120
    static let composerInfoButtonWidth: CGFloat = 78
    static let modelMenuMaxWidth: CGFloat = 176

    static let chatContentMaxWidth: CGFloat = 720
    static let messageMaxWidth: CGFloat = chatContentMaxWidth
    static let userMessageMaxWidth: CGFloat = chatContentMaxWidth * 0.72
    static let processMaxWidth: CGFloat = chatContentMaxWidth
    static let messageSideInset: CGFloat = 0

    static let avatarSize: CGFloat = 28
    static let avatarBubbleSpacing: CGFloat = 8
}
