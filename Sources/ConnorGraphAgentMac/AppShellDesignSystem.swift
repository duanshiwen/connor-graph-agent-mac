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

enum AppShellLayout {
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 22

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16

    static let primarySidebarMinWidth: CGFloat = 180
    static let primarySidebarDefaultWidth: CGFloat = 210
    static let primarySidebarMaxWidth: CGFloat = 250

    static let listColumnWidth: CGFloat = 300

    static let detailColumnMinWidth: CGFloat = 360
    static let shellMinWidth: CGFloat = 860
    static let shellMinHeight: CGFloat = 680

    static let contentMaxWidth: CGFloat = 780
    static let hairlineOpacity: Double = 0.14
}

/// Shared metrics for selectable cards in every primary app list.
/// The conversation card is the visual baseline; content-heavy cards may grow naturally.
enum AppListCardLayout {
    static let horizontalInset: CGFloat = 8
    static let verticalInset: CGFloat = 8
    static let spacing: CGFloat = 2
    static let contentPadding: CGFloat = 10
    static let contentSpacing: CGFloat = 6
    static let cornerRadius: CGFloat = 10
    static let minimumHeight: CGFloat = 72

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

enum AppShellColors {
    static let detailBackground = Color(nsColor: .textBackgroundColor).opacity(0.18)
    static let cardBackground = Color(nsColor: .windowBackgroundColor)
    static let subtleCardBackground = Color(nsColor: .textBackgroundColor).opacity(0.42)
    static let hairline = Color.secondary.opacity(AppShellLayout.hairlineOpacity)
}

enum GlobalSearchOverlayGlassStyle {
    static let selectedAccentOpacity: Double = 0.20
    static let hoverAccentOpacity: Double = 0.12

    static let outerShadowOpacity: Double = 0.24
    static let outerShadowRadius: CGFloat = 28
    static let outerShadowY: CGFloat = 16

    static let edgeHighlightOpacityLight: Double = 0.22
    static let edgeHighlightOpacityDark: Double = 0.10
    static let edgeLowlightOpacityLight: Double = 0.10
    static let edgeLowlightOpacityDark: Double = 0.22

    static let chipStrokeOpacity: Double = 0.10
}

struct AppPill: View {
    var text: String
    var color: Color = .secondary
    var systemImage: String? = nil

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
            }
        }
        .labelStyle(.titleAndIcon)
        .font(AppListTypography.rowCaption)
        .padding(.horizontal, AppShellLayout.spaceS)
        .frame(height: 22)
        .foregroundStyle(color)
        .background(color.opacity(0.11), in: Capsule())
    }
}

struct AppSectionCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
            Label(title, systemImage: systemImage)
                .font(AppListTypography.rowCaptionEmphasized)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(AppShellLayout.spaceL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                    .stroke(AppShellColors.hairline, lineWidth: 1)
            )
        }
    }
}

struct AppMetricCard: View {
    var title: String
    var value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
            Text(title)
                .font(AppListTypography.rowCaptionEmphasized)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(AppShellLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
    }
}
