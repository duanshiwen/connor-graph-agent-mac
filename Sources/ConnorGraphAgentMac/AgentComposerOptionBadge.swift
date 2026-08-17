import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct AgentComposerOptionBadge: View {
    @Environment(\.windowWidthClass) private var windowWidthClass

    /// 标题文本最大宽度。长文件名/长标题（例如工作目录）会在此处中间截断，
    /// 避免把输入框操作栏或弹层撑出窗口；堆叠窄窗口下进一步收窄，保证输入区完整适配。
    private var maximumTitleWidth: CGFloat {
        switch windowWidthClass {
        case .regular: 200
        case .compact: 160
        case .narrow, .phone: 96
        }
    }

    enum Style {
        case compact
        case prominent

        var iconSize: CGFloat {
            switch self {
            case .compact: AgentChatTypography.controlIconSize
            case .prominent: AgentChatTypography.controlIconSize + 1
            }
        }

        var textFont: Font {
            switch self {
            case .compact: AgentChatTypography.meta.weight(.medium)
            case .prominent: AgentChatTypography.metaEmphasis
            }
        }

        var chevronSize: CGFloat {
            AgentChatTypography.smallIconSize
        }
    }

    var title: String
    var systemImage: String
    var tint: Color
    var showsChevron: Bool = true
    var isActive: Bool = false
    var style: Style = .compact
    var showsBorder: Bool = true
    var fill: Color = .clear
    var borderTint: Color = .secondary
    var horizontalPadding: CGFloat = AgentChatLayout.spaceS

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: style.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(style.textFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: maximumTitleWidth, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: style.chevronSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .opacity(0.72)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: AgentChatLayout.chipHeight)
        .foregroundStyle(tint)
        .background(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                .fill(fill)
        )
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                    .stroke(borderTint.opacity(isActive ? 0.30 : 0.20), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        .frame(minHeight: AgentChatLayout.hitTargetSize)
        .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
    }
}
