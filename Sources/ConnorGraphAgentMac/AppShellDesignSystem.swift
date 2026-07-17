import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

/// App-wide semantic type scale based on the macOS system text styles.
/// Text roles stay consistent while still respecting the user's system settings.
enum AppTypography {
    static let pageTitle: Font = .title3.weight(.semibold)
    static let paneTitle: Font = .headline.weight(.semibold)
    static let sectionTitle: Font = .headline.weight(.semibold)
    static let body: Font = .body
    static let bodyEmphasis: Font = .body.weight(.semibold)
    static let callout: Font = .callout
    static let calloutEmphasis: Font = .callout.weight(.semibold)
    static let meta: Font = .subheadline
    static let metaEmphasis: Font = .subheadline.weight(.semibold)
    static let caption: Font = .caption
    static let captionEmphasis: Font = .caption.weight(.semibold)
    static let micro: Font = .caption2
    static let microEmphasis: Font = .caption2.weight(.semibold)
    static let monoMeta: Font = .system(.subheadline, design: .monospaced)
    static let monoMetaEmphasis: Font = .system(.subheadline, design: .monospaced).weight(.semibold)
    static let monoMicro: Font = .system(.caption2, design: .monospaced)
    static let monoMicroEmphasis: Font = .system(.caption2, design: .monospaced).weight(.semibold)
}

enum AppListTypography {
    static let actionTitle = AppTypography.body
    static let actionIcon = AppTypography.bodyEmphasis
    static let header = AppTypography.paneTitle
    static let rowTitle: Font = .system(size: 14)
    static let rowTitleSelected: Font = .system(size: 14, weight: .semibold)
    static let rowSubtitle: Font = .system(size: 12.5)
    static let rowCaption: Font = .system(size: 12)
    static let rowCaptionEmphasized: Font = .system(size: 12, weight: .semibold)
}

struct AppListPaneHeader<Actions: View>: View {
    var title: String
    var verticalPadding: CGFloat
    @ViewBuilder var actions: Actions

    init(title: String, verticalPadding: CGFloat = AppShellLayout.paneHeaderVerticalPadding, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.verticalPadding = verticalPadding
        self.actions = actions()
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(AppListTypography.header)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: AppShellLayout.spaceS) {
                Spacer(minLength: 0)
                actions
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppShellLayout.paneHeaderHorizontalPadding)
        .padding(.vertical, verticalPadding)
    }
}

struct SidebarActionButtonLabel: View {
    var title: String
    var systemImage: String
    var fillsWidth: Bool = true
    var titleFont: Font = AppListTypography.actionTitle
    var iconFont: Font = AppListTypography.actionIcon
    var minHeight: CGFloat = AppButtonLayout.height

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
    static let spaceXL: CGFloat = 24

    static let paneHeaderHorizontalPadding: CGFloat = 16
    static let paneHeaderVerticalPadding: CGFloat = 12
    static let pageHorizontalPadding: CGFloat = 24
    static let pageVerticalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24

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

/// Shared button metrics for every app surface. Native text buttons use the
/// regular macOS control size; icon-only actions use one stable square target.
enum AppButtonLayout {
    static let controlSize: ControlSize = .regular
    static let height: CGFloat = 32
    static let iconButtonSize: CGFloat = 32
    static let iconSize: CGFloat = 14
}

/// Native macOS form defaults shared by every window. Individual search and
/// title fields can still opt into `.plain` when their container supplies the
/// border and focus treatment.
struct AppFormThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .controlSize(AppButtonLayout.controlSize)
            .textFieldStyle(.roundedBorder)
    }
}

struct AppFormTextEditorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                Color(nsColor: isEnabled ? .textBackgroundColor : .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(isEnabled ? 0.65 : 0.35),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func appFormTheme() -> some View {
        modifier(AppFormThemeModifier())
    }

    func appFormTextEditor() -> some View {
        modifier(AppFormTextEditorModifier())
    }
}

struct AppIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AppButtonLayout.iconSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: AppButtonLayout.iconButtonSize, height: AppButtonLayout.iconButtonSize)
            .contentShape(Circle())
            .background(
                Color.secondary.opacity(configuration.isPressed ? 0.16 : 0.08),
                in: Circle()
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppIconButtonStyle {
    static var appIcon: AppIconButtonStyle { AppIconButtonStyle() }
}

/// Shared metrics for selectable rows in every primary app list.
/// Rows keep a compact macOS rhythm, use a stable minimum height, and grow only
/// when their content needs another line.
enum AppListCardLayout {
    static let horizontalInset: CGFloat = 8
    static let verticalInset: CGFloat = 6
    static let spacing: CGFloat = 0
    static let contentHorizontalPadding: CGFloat = 10
    static let contentVerticalPadding: CGFloat = 10
    static let contentPadding: CGFloat = 10
    static let contentSpacing: CGFloat = 6
    static let cornerRadius: CGFloat = 6
    static let minimumHeight: CGFloat = 64
    static let titleLineLimit = 2
    static let separatorLeadingInset: CGFloat = 10

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

private struct AppListRowSurfaceModifier: ViewModifier {
    var isSelected: Bool
    var backgroundColor: Color?

    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppListCardLayout.contentHorizontalPadding)
            .padding(.vertical, AppListCardLayout.contentVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: AppListCardLayout.minimumHeight, alignment: .leading)
            .background(resolvedBackgroundColor, in: AppListCardLayout.shape)
            .overlay(alignment: .bottom) {
                if !isSelected {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.55))
                        .frame(height: 1)
                        .padding(.leading, AppListCardLayout.separatorLeadingInset)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private var resolvedBackgroundColor: Color {
        if let backgroundColor { return backgroundColor }
        if isSelected {
            return Color.accentColor.opacity(controlActiveState == .active ? 0.18 : 0.10)
        }
        if isHovering { return Color.secondary.opacity(0.07) }
        return .clear
    }
}

extension View {
    func appListRowSurface(isSelected: Bool, backgroundColor: Color? = nil) -> some View {
        modifier(AppListRowSurfaceModifier(isSelected: isSelected, backgroundColor: backgroundColor))
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
