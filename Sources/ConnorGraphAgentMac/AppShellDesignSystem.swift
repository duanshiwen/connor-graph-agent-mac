import SwiftUI
import AppKit
import ConnorGraphCore
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
    static let listColumnNarrowWidth: CGFloat = 240

    static let detailColumnMinWidth: CGFloat = 360
    static let shellMinWidth: CGFloat = 420
    static let shellMinHeight: CGFloat = 560

    // 响应式断点（按窗口内容宽度）：
    // - 小于 sidebarCollapseThreshold：自动收起主侧栏（并禁用手动展开，保证详情列宽度）
    // - 大于 sidebarExpandThreshold：自动展开主侧栏（若用户未手动隐藏）
    // - 小于 narrowWidthThreshold：进入窄模式，省略次要控件、压缩列表列
    static let sidebarCollapseThreshold: CGFloat = 1120
    static let sidebarExpandThreshold: CGFloat = 1160
    static let narrowWidthThreshold: CGFloat = 920
    // - 小于 phoneWidthThreshold：进入手机式堆叠布局（列表/详情二选一全屏）
    static let phoneWidthThreshold: CGFloat = 600

    static let contentMaxWidth: CGFloat = 780
    static let hairlineOpacity: Double = 0.14
}

/// 主窗口宽度档位：驱动侧边栏自动收起与窄窗口下的控件省略。
enum AppWindowWidthClass: Equatable, Sendable {
    case regular   // 完整布局：主侧栏 + 列表 + 详情
    case compact   // 自动收起主侧栏，保留全部控件
    case narrow    // 窄窗口：收起主侧栏，省略次要控件
    case phone     // 手机宽度：列表/详情堆叠切换

    var isNarrow: Bool { self == .narrow }
    var isPhone: Bool { self == .phone }
    var isCompactOrNarrow: Bool { self != .regular }
}

private struct AppWindowWidthClassKey: EnvironmentKey {
    static let defaultValue: AppWindowWidthClass = .regular
}

extension EnvironmentValues {
    var windowWidthClass: AppWindowWidthClass {
        get { self[AppWindowWidthClassKey.self] }
        set { self[AppWindowWidthClassKey.self] = newValue }
    }
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

enum AppSessionStatusVisualStyle {
    static func color(for status: AgentSessionStatus) -> Color {
        switch status {
        case .todo: .secondary
        case .inProgress: .blue
        case .waiting: .orange
        case .needsReview: .purple
        case .done: .green
        case .blocked: .red
        case .cancelled, .archived: .gray
        }
    }
}

enum AppShellColors {
    static let listBackground = Color(nsColor: .windowBackgroundColor)
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

// MARK: - 原生右键菜单（修复 SwiftUI contextMenu 嵌套子菜单 hover 消失）

/// SwiftUI `.contextMenu` 内嵌套 `Menu` 子菜单在 macOS 上存在已知缺陷：
/// 光标移到子菜单所在行时，hover 会触发视图重建，菜单跟踪被中断，整个菜单消失。
/// 该问题在行视图带 `onHover`/状态动画（如会话卡片）时稳定复现。
/// 这里改为原生 `NSMenu` 子菜单：子菜单的展开由 AppKit 跟踪，不受 SwiftUI 重建影响。
final class NativeMenuActionTarget: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }
    @objc func invoke(_ sender: Any?) {
        handler()
    }
}

nonisolated(unsafe) private var nativeMenuTargetsKey: UInt8 = 0

extension NSMenu {
    /// 强持有菜单项的 action target。
    /// `NSMenuItem.target` 是弱引用，若不额外持有，target 会在菜单弹出前被 ARC 释放，
    /// 导致菜单项因无法响应 action 而变灰不可点击。
    func retainingActionTargets(_ targets: [NativeMenuActionTarget]) {
        objc_setAssociatedObject(self, &nativeMenuTargetsKey, targets, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// 捕获右键点击并在该位置弹出原生 NSMenu 的透明桥接视图。
/// 仅拦截右键事件；左键/双击等事件全部穿透到下层 SwiftUI 视图。
final class NativeRightClickMenuView: NSView {
    var makeMenu: () -> NSMenu

    init(makeMenu: @escaping () -> NSMenu) {
        self.makeMenu = makeMenu
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 只拦截右键，其余事件放行给下层（避免挡住行点击/双击/滚动）。
        if NSApp.currentEvent?.type == .rightMouseDown {
            return self
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        // menu 通过 retainingActionTargets 强持有所有 action target，
        // popUp 同步运行期间 target 必然存活。
        let menu = makeMenu()
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
}

struct NativeContextMenuBridge: NSViewRepresentable {
    var makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> NativeRightClickMenuView {
        NativeRightClickMenuView(makeMenu: makeMenu)
    }

    func updateNSView(_ nsView: NativeRightClickMenuView, context: Context) {
        nsView.makeMenu = makeMenu
    }
}

extension View {
    /// 用原生 NSMenu 替代 SwiftUI `.contextMenu`，支持可靠的嵌套子菜单。
    func nativeContextMenu(_ makeMenu: @escaping () -> NSMenu) -> some View {
        self.overlay(NativeContextMenuBridge(makeMenu: makeMenu))
    }
}

// MARK: - 会话卡片原生右键菜单构建

enum AppSessionNativeContextMenu {
    /// 构建会话卡片的完整原生右键菜单（替代 SwiftUI `.contextMenu` 嵌套 `Menu`）。
    /// - Parameters:
    ///   - currentStatus: 当前状态，用于在子菜单中打勾。
    ///   - statuses: 可选的状态列表，默认全部（除已归档）。
    ///   - labels: 标签定义列表；为空时显示“暂无可切换标签”。
    ///   - selectedLabelIDs: 已选中的标签 ID 集合，用于打勾。
    ///   - statusImageProvider: 状态图标（默认用 AgentSessionStatusDefinition.defaults）。
    static func makeMenu(
        title: String = "",
        currentStatus: AgentSessionStatus,
        statuses: [AgentSessionStatus]? = nil,
        labels: [AgentSessionLabelDefinition],
        selectedLabelIDs: Set<String>,
        statusImageProvider: (AgentSessionStatus) -> String = { status in
            AgentSessionStatusDefinition.defaults.first(where: { $0.id == status.rawValue })?.systemImage ?? "circle"
        },
        onSetStatus: @escaping (AgentSessionStatus) -> Void,
        onToggleLabel: @escaping (String) -> Void,
        onRename: @escaping () -> Void,
        onRegenerateTitle: @escaping () -> Void,
        onToggleMuted: (() -> Void)? = nil,
        isMuted: Bool = false,
        isRegeneratingTitle: Bool,
        onDelete: @escaping () -> Void,
        canDelete: Bool = true,
        deleteTitle: String = "删除会话"
    ) -> NSMenu {
        let menu = NSMenu(title: title)
        var retainedTargets: [NativeMenuActionTarget] = []
        if !title.isEmpty {
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }

        // 更改状态（子菜单）
        let statusItem = NSMenuItem(title: "更改状态", action: nil, keyEquivalent: "")
        statusItem.image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "更改状态")
        let statusMenu = NSMenu(title: "更改状态")
        for status in statuses ?? AgentSessionStatus.allCases.filter({ $0 != .archived }) {
            let item = NSMenuItem(title: status.displayName, action: #selector(NativeMenuActionTarget.invoke(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: statusImageProvider(status), accessibilityDescription: status.displayName)
            let target = NativeMenuActionTarget { onSetStatus(status) }
            item.target = target
            retainedTargets.append(target)
            if status == currentStatus {
                item.state = .on
            }
            statusMenu.addItem(item)
        }
        statusItem.submenu = statusMenu
        menu.addItem(statusItem)

        // 标签（子菜单）
        let labelItem = NSMenuItem(title: "标签", action: nil, keyEquivalent: "")
        labelItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "标签")
        let labelMenu = NSMenu(title: "标签")
        if labels.isEmpty {
            let empty = NSMenuItem(title: "暂无可切换标签", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            labelMenu.addItem(empty)
        } else {
            for definition in labels {
                let item = NSMenuItem(title: definition.name, action: #selector(NativeMenuActionTarget.invoke(_:)), keyEquivalent: "")
                item.image = NSImage(systemSymbolName: selectedLabelIDs.contains(definition.id) ? "checkmark.circle.fill" : (definition.systemImage.isEmpty ? "tag" : definition.systemImage), accessibilityDescription: definition.name)
                let target = NativeMenuActionTarget { onToggleLabel(definition.id) }
                item.target = target
                retainedTargets.append(target)
                if selectedLabelIDs.contains(definition.id) {
                    item.state = .on
                }
                labelMenu.addItem(item)
            }
        }
        labelItem.submenu = labelMenu
        menu.addItem(labelItem)

        menu.addItem(.separator())

        // 重命名
        let renameItem = NSMenuItem(title: "重命名", action: #selector(NativeMenuActionTarget.invoke(_:)), keyEquivalent: "")
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "重命名")
        let renameTarget = NativeMenuActionTarget(onRename)
        renameItem.target = renameTarget
        retainedTargets.append(renameTarget)
        menu.addItem(renameItem)

        // AI 重设标题
        let regenerateItem = NSMenuItem(title: "AI 重设标题", action: #selector(NativeMenuActionTarget.invoke(_:)), keyEquivalent: "")
        regenerateItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 重设标题")
        let regenerateTarget = NativeMenuActionTarget(onRegenerateTitle)
        regenerateItem.target = regenerateTarget
        retainedTargets.append(regenerateTarget)
        regenerateItem.isEnabled = !isRegeneratingTitle
        menu.addItem(regenerateItem)

        // 免打扰（可选：IM 会话有免打扰，Craft 会话没有）
        if let onToggleMuted {
            let muteItem = NSMenuItem(title: isMuted ? "取消免打扰" : "免打扰", action: #selector(NativeMenuActionTarget.invoke(_:)), keyEquivalent: "")
            muteItem.image = NSImage(systemSymbolName: "bell.slash", accessibilityDescription: isMuted ? "取消免打扰" : "免打扰")
            let muteTarget = NativeMenuActionTarget(onToggleMuted)
            muteItem.target = muteTarget
            retainedTargets.append(muteTarget)
            menu.addItem(muteItem)
        }

        menu.addItem(.separator())

        // 删除
        let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(NativeMenuActionTarget.invoke(_:)), keyEquivalent: "")
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: deleteTitle)
        let deleteTarget = NativeMenuActionTarget(onDelete)
        deleteItem.target = deleteTarget
        retainedTargets.append(deleteTarget)
        deleteItem.isEnabled = canDelete
        menu.addItem(deleteItem)

        // 让 menu 自身强持有所有 action target，直到菜单弹出结束。
        menu.retainingActionTargets(retainedTargets)
        return menu
    }
}
