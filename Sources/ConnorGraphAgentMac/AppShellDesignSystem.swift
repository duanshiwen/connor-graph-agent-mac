import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

enum AppListTypography {
    static let actionTitle: Font = .system(size: 13.5, weight: .regular)
    static let actionIcon: Font = .system(size: 14.5, weight: .medium)
    static let header: Font = .system(size: 15.5, weight: .semibold)
    static let rowTitle: Font = .system(size: 14.5, weight: .regular)
    static let rowTitleSelected: Font = .system(size: 14.5, weight: .semibold)
    static let rowSubtitle: Font = .system(size: 12.5)
    static let rowCaption: Font = .system(size: 12.5)
    static let rowCaptionEmphasized: Font = .system(size: 12.5, weight: .semibold)
}

struct SidebarActionButtonLabel: View {
    var title: String
    var systemImage: String
    var fillsWidth: Bool = true
    var titleFont: Font = AppListTypography.actionTitle
    var iconFont: Font = AppListTypography.actionIcon
    var minHeight: CGFloat = 24

    var body: some View {
        Label {
            Text(title)
                .font(titleFont)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .font(iconFont)
                .symbolRenderingMode(.monochrome)
                .frame(width: 15, alignment: .center)
        }
        .foregroundStyle(Color.primary)
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight, alignment: .leading)
        .padding(.horizontal, 7)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SidebarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .shadow(color: shadowColor(isPressed: configuration.isPressed), radius: configuration.isPressed ? 0 : 0.5, x: 0, y: configuration.isPressed ? 0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(isPressed ? 0.78 : 0.96)
    }

    private func borderColor(isPressed: Bool) -> Color {
        Color(nsColor: .separatorColor)
            .opacity(isPressed ? 0.42 : 0.28)
    }

    private func shadowColor(isPressed: Bool) -> Color {
        Color.black.opacity(isPressed ? 0.04 : 0.08)
    }
}

