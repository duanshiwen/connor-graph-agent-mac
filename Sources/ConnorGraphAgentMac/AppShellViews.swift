import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AppShellView: View {
    @StateObject var viewModel: AppViewModel
    @State private var sidebarSelection: SidebarItem? = .agentChat
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var topSearchKeyMonitor: Any?

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            CraftPrimarySidebarView(viewModel: viewModel, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 320)
                .background(.bar)
                .controlSize(.small)
        } content: {
            CraftListPaneView(viewModel: viewModel, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 314, max: 380)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.84))
                .controlSize(.small)
        } detail: {
            CraftDetailPaneView(viewModel: viewModel, selection: sidebarSelection ?? .agentChat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                .controlSize(.small)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TopSearchTextField(
                        text: $viewModel.sessionSearchQuery,
                        placeholder: "搜索会话标题和内容",
                        focusRequestID: viewModel.focusTopSearchRequestID
                    )
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 420, minHeight: 20, idealHeight: 22, maxHeight: 24)
                    if !viewModel.sessionSearchQuery.isEmpty {
                        Button(action: { viewModel.sessionSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清除搜索")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.openProjectGitHubHelp() }) {
                    Label("帮助", systemImage: "questionmark.circle")
                }
                .help("用内置浏览器打开项目 GitHub 页面")
            }
        }
        .overlay(alignment: .topLeading) {
            BrowserBackgroundTaskRunnerView(viewModel: viewModel)
        }
        .frame(minWidth: 1120, minHeight: 680)
        .onAppear {
            sidebarSelection = viewModel.selection ?? .agentChat
            viewModel.reloadChatSessions()
            installTopSearchKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeTopSearchKeyMonitor()
        }
        .onChange(of: sidebarSelection) { _, newSelection in
            viewModel.deferViewUpdate {
                viewModel.selection = newSelection
            }
        }
        .onChange(of: viewModel.selection) { _, newSelection in
            if sidebarSelection != newSelection {
                sidebarSelection = newSelection
            }
        }
        .onChange(of: viewModel.runtimeSettingsAutosaveSignature) { _, _ in
            viewModel.scheduleRuntimeSettingsAutosave()
        }
    }

    private func installTopSearchKeyMonitorIfNeeded() {
        guard topSearchKeyMonitor == nil else { return }
        topSearchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shortcut = viewModel.shortcut(for: .focusTopSearch)
            guard shortcut.matches(
                character: event.charactersIgnoringModifiers,
                isCommandDown: event.modifierFlags.contains(.command),
                isShiftDown: event.modifierFlags.contains(.shift),
                isControlDown: event.modifierFlags.contains(.control),
                isOptionDown: event.modifierFlags.contains(.option)
            ) else {
                return event
            }
            viewModel.performShortcutAction(.focusTopSearch)
            return nil
        }
    }

    private func removeTopSearchKeyMonitor() {
        if let topSearchKeyMonitor {
            NSEvent.removeMonitor(topSearchKeyMonitor)
            self.topSearchKeyMonitor = nil
        }
    }

}

private struct TopSearchTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequestID: UUID?

    func makeNSView(context: Context) -> NSTextField {
        let textField = SelectAllOnFocusTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 13)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            guard focusRequestID != nil else { return }
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.selectText(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var lastFocusRequestID: UUID?

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

private final class SelectAllOnFocusTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.selectText(nil)
            }
        }
        return didBecomeFirstResponder
    }
}

private enum AppListTypography {
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

private struct CraftPrimarySidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?
    @State private var sessionsExpanded = true
    @State private var labelsExpanded = true
    @State private var sourcesExpanded = true
    @State private var automationExpanded = true
    @State private var statusEditorRequest: StatusDefinitionEditorRequest?
    @State private var labelEditorRequest: LabelDefinitionEditorRequest?

    var body: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.newChatSession()
                select(.agentChat)
            } label: {
                SidebarActionButtonLabel(title: "新建会话", systemImage: "square.and.pencil", minHeight: 32)
            }
            .buttonStyle(SidebarActionButtonStyle())
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SidebarDisclosure(title: "所有会话", systemImage: "tray", isExpanded: $sessionsExpanded) {
                        SidebarRow(title: "全部", systemImage: "bubble.left.and.bubble.right", count: allSessionsCount, isSelected: selection == .agentChat && viewModel.sessionListFilter == .all) {
                            viewModel.setSessionListFilter(.all)
                            select(.agentChat)
                        }
                        .contextMenu {
                            Button("创建状态…", systemImage: "plus.circle") { presentNewStatusEditor() }
                        }
                        ForEach(viewModel.governanceConfig.statuses.sorted { $0.sortOrder < $1.sortOrder }) { status in
                            if let sessionStatus = AgentSessionStatus(rawValue: status.id) {
                                SidebarRow(title: status.name, systemImage: status.systemImage, count: count(for: sessionStatus), isSelected: selection == .agentChat && viewModel.sessionListFilter == .status(sessionStatus)) {
                                    viewModel.setSessionListFilter(.status(sessionStatus))
                                    select(.agentChat)
                                }
                                .contextMenu {
                                    Button("编辑状态…", systemImage: "pencil") { presentStatusEditor(status) }
                                    Button("创建状态…", systemImage: "plus.circle") { presentNewStatusEditor(after: status) }
                                    Divider()
                                    Button(role: .destructive) { viewModel.deleteStatusDefinition(status) } label: {
                                        Label("删除状态", systemImage: "trash")
                                    }
                                    .disabled(!viewModel.canDeleteStatusDefinition(status))
                                }
                            } else {
                                SidebarRow(title: status.name, systemImage: status.systemImage, count: 0, isSelected: false) {
                                    presentStatusEditor(status)
                                }
                                .contextMenu {
                                    Button("编辑状态…", systemImage: "pencil") { presentStatusEditor(status) }
                                    Button("创建状态…", systemImage: "plus.circle") { presentNewStatusEditor(after: status) }
                                    Divider()
                                    Button(role: .destructive) { viewModel.deleteStatusDefinition(status) } label: {
                                        Label("删除状态", systemImage: "trash")
                                    }
                                    .disabled(!viewModel.canDeleteStatusDefinition(status))
                                }
                            }
                        }
                    }

                    SidebarDisclosure(title: "标签", systemImage: "tag", isExpanded: $labelsExpanded) {
                        if viewModel.governanceConfig.labels.isEmpty {
                            SidebarMutedText("暂无标签")
                                .contextMenu {
                                    Button("创建标签…", systemImage: "plus.circle") { presentNewLabelEditor() }
                                }
                        } else {
                            ForEach(viewModel.governanceConfig.labels) { label in
                                SidebarRow(title: label.name, systemImage: label.systemImage, count: count(forLabel: label.id), isSelected: selection == .agentChat && viewModel.sessionListFilter == .label(label.id)) {
                                    viewModel.setSessionListFilter(.label(label.id))
                                    select(.agentChat)
                                }
                                .contextMenu {
                                    Button("编辑标签…", systemImage: "pencil") { presentLabelEditor(label) }
                                    Button("创建标签…", systemImage: "plus.circle") { presentNewLabelEditor() }
                                    Divider()
                                    Button(role: .destructive) { viewModel.deleteLabelDefinition(label) } label: {
                                        Label("删除标签", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    SidebarRow(title: "数据源", systemImage: "externaldrive.connected.to.line.below", count: viewModel.sourceRuntimeConfigurations.count, isSelected: selection == .sources) { select(.sources) }

                    SidebarRow(title: "技能", systemImage: "bolt", count: viewModel.skillRuntimeDefinitions.count, isSelected: selection == .skills) { select(.skills) }

                    SidebarDisclosure(title: "自动化", systemImage: "wand.and.stars", isExpanded: $automationExpanded) {
                        SidebarRow(title: "定时任务", systemImage: "clock", count: viewModel.automationConfig.rules.count, isSelected: selection == .automation) { select(.automation) }
                        SidebarRow(title: "事件触发", systemImage: "dot.radiowaves.left.and.right", count: viewModel.automationTriggerRecords.count, isSelected: selection == .automation) { select(.automation) }
                        SidebarRow(title: "智能体", systemImage: "shippingbox", count: viewModel.productOSRegistry.skills.count, isSelected: selection == .productOS) { select(.productOS) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                SidebarRow(title: "设置", systemImage: "gearshape", count: nil, isSelected: selection == .llmSettings) { select(.llmSettings) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .sheet(item: $statusEditorRequest) { request in
            StatusDefinitionEditorSheet(
                title: request.isCreating ? "创建状态" : "编辑状态",
                definition: request.definition,
                isCreating: request.isCreating,
                onCancel: { statusEditorRequest = nil },
                onSave: { definition in
                    viewModel.upsertStatusDefinition(definition)
                    statusEditorRequest = nil
                }
            )
        }
        .sheet(item: $labelEditorRequest) { request in
            LabelDefinitionEditorSheet(
                title: request.isCreating ? "创建标签" : "编辑标签",
                definition: request.definition,
                isCreating: request.isCreating,
                onCancel: { labelEditorRequest = nil },
                onSave: { definition in
                    viewModel.upsertLabelDefinition(definition)
                    labelEditorRequest = nil
                }
            )
        }
    }

    private var countSourceSessions: [AgentSession] {
        viewModel.allChatSessions.isEmpty ? viewModel.chatSessions : viewModel.allChatSessions
    }

    private var allSessionsCount: Int {
        countSourceSessions.count
    }

    private func count(for status: AgentSessionStatus) -> Int {
        countSourceSessions.filter { $0.governance.status == status }.count
    }

    private func count(forLabel labelID: String) -> Int {
        countSourceSessions.filter { session in
            session.governance.labels.contains { $0.id == labelID }
        }.count
    }

    private func select(_ item: SidebarItem) {
        selection = item
        viewModel.selection = item
    }

    private func presentStatusEditor(_ definition: AgentSessionStatusDefinition) {
        statusEditorRequest = StatusDefinitionEditorRequest(definition: definition, isCreating: false)
    }

    private func presentNewStatusEditor(after definition: AgentSessionStatusDefinition? = nil) {
        let nextSortOrder = (definition?.sortOrder ?? viewModel.governanceConfig.statuses.map(\.sortOrder).max() ?? 0) + 10
        statusEditorRequest = StatusDefinitionEditorRequest(
            definition: AgentSessionStatusDefinition(
                id: "",
                name: "",
                systemImage: "circle",
                sortOrder: nextSortOrder,
                isTerminal: false
            ),
            isCreating: true
        )
    }

    private func presentLabelEditor(_ definition: AgentSessionLabelDefinition) {
        labelEditorRequest = LabelDefinitionEditorRequest(definition: definition, isCreating: false)
    }

    private func presentNewLabelEditor() {
        labelEditorRequest = LabelDefinitionEditorRequest(
            definition: AgentSessionLabelDefinition(id: "", name: "", colorName: "blue", systemImage: "tag"),
            isCreating: true
        )
    }

}

private struct StatusDefinitionEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionStatusDefinition
    var isCreating: Bool
}

private struct LabelDefinitionEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionLabelDefinition
    var isCreating: Bool
}

private struct StatusDefinitionEditorSheet: View {
    var title: String
    var definition: AgentSessionStatusDefinition
    var isCreating: Bool
    var onCancel: () -> Void
    var onSave: (AgentSessionStatusDefinition) -> Void

    @State private var name: String
    @State private var systemImage: String

    init(title: String, definition: AgentSessionStatusDefinition, isCreating: Bool, onCancel: @escaping () -> Void, onSave: @escaping (AgentSessionStatusDefinition) -> Void) {
        self.title = title
        self.definition = definition
        self.isCreating = isCreating
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: definition.name)
        _systemImage = State(initialValue: definition.systemImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("状态名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("图标", selection: $systemImage) {
                ForEach(statusIconOptions, id: \.self) { icon in
                    Label(statusIconTitle(for: icon), systemImage: icon).tag(icon)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(AgentSessionStatusDefinition(id: definition.id, name: trimmed(name), systemImage: systemImage, sortOrder: definition.sortOrder, isTerminal: definition.isTerminal))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct LabelDefinitionEditorSheet: View {
    var title: String
    var definition: AgentSessionLabelDefinition
    var isCreating: Bool
    var onCancel: () -> Void
    var onSave: (AgentSessionLabelDefinition) -> Void

    @State private var name: String
    @State private var color: Color
    @State private var systemImage: String

    init(title: String, definition: AgentSessionLabelDefinition, isCreating: Bool, onCancel: @escaping () -> Void, onSave: @escaping (AgentSessionLabelDefinition) -> Void) {
        self.title = title
        self.definition = definition
        self.isCreating = isCreating
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: definition.name)
        _color = State(initialValue: labelColor(from: definition.colorName))
        _systemImage = State(initialValue: definition.systemImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("标签名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("图标", selection: $systemImage) {
                ForEach(labelIconOptions, id: \.self) { icon in
                    Label(labelIconTitle(for: icon), systemImage: icon).tag(icon)
                }
            }
            .pickerStyle(.menu)
            ColorPicker("颜色", selection: $color, supportsOpacity: false)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(AgentSessionLabelDefinition(id: definition.id, name: trimmed(name), colorName: colorStorageName(from: color), systemImage: systemImage))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private let statusIconOptions: [String] = [
    "circle",
    "clock",
    "pause.circle",
    "play.circle",
    "checkmark.circle",
    "checkmark.circle.fill",
    "xmark.circle",
    "nosign",
    "exclamationmark.circle",
    "exclamationmark.bubble",
    "questionmark.circle",
    "flag",
    "star",
    "bolt",
    "flame",
    "tray",
    "archivebox",
    "paperplane",
    "hammer",
    "wrench.and.screwdriver",
    "lightbulb",
    "sparkles",
    "target"
]

private func statusIconTitle(for icon: String) -> String {
    switch icon {
    case "circle": return "圆点"
    case "clock": return "时钟"
    case "pause.circle": return "暂停"
    case "play.circle": return "进行中"
    case "checkmark.circle": return "完成"
    case "checkmark.circle.fill": return "完成（填充）"
    case "xmark.circle": return "关闭"
    case "nosign": return "受阻"
    case "exclamationmark.circle": return "提醒"
    case "exclamationmark.bubble": return "待审阅"
    case "questionmark.circle": return "询问"
    case "flag": return "旗标"
    case "star": return "星标"
    case "bolt": return "闪电"
    case "flame": return "火焰"
    case "tray": return "收件箱"
    case "archivebox": return "归档"
    case "paperplane": return "发送"
    case "hammer": return "构建"
    case "wrench.and.screwdriver": return "工具"
    case "lightbulb": return "想法"
    case "sparkles": return "闪光"
    case "target": return "目标"
    default: return icon
    }
}

private let labelIconOptions: [String] = [
    "tag",
    "tag.fill",
    "star",
    "star.fill",
    "flag",
    "flag.fill",
    "bookmark",
    "bookmark.fill",
    "doc.text",
    "doc.text.magnifyingglass",
    "folder",
    "folder.fill",
    "calendar",
    "calendar.badge.clock",
    "person.2",
    "link",
    "paperclip",
    "lightbulb",
    "sparkles",
    "flame"
]

private func labelIconTitle(for icon: String) -> String {
    switch icon {
    case "tag": return "标签"
    case "tag.fill": return "标签（填充）"
    case "star": return "星标"
    case "star.fill": return "星标（填充）"
    case "flag": return "旗标"
    case "flag.fill": return "旗标（填充）"
    case "bookmark": return "书签"
    case "bookmark.fill": return "书签（填充）"
    case "doc.text": return "文档"
    case "doc.text.magnifyingglass": return "研究"
    case "folder": return "文件夹"
    case "folder.fill": return "项目"
    case "calendar": return "日期"
    case "calendar.badge.clock": return "截止日期"
    case "person.2": return "协作"
    case "link": return "链接"
    case "paperclip": return "附件"
    case "lightbulb": return "想法"
    case "sparkles": return "闪光"
    case "flame": return "火焰"
    default: return icon
    }
}

private func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func labelColor(from storageName: String) -> Color {
    switch storageName {
    case "orange": return .orange
    case "purple": return .purple
    case "teal": return .teal
    case "red": return .red
    case "yellow": return .yellow
    case "green": return .green
    case "blue": return .blue
    default:
        guard storageName.hasPrefix("#"), storageName.count == 7 else { return .blue }
        let hex = String(storageName.dropFirst())
        guard let value = Int(hex, radix: 16) else { return .blue }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

private func colorStorageName(from color: Color) -> String {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
    let red = Int((nsColor.redComponent * 255).rounded())
    let green = Int((nsColor.greenComponent * 255).rounded())
    let blue = Int((nsColor.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
}

private struct CraftListPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            switch selection ?? .agentChat {
            case .agentChat:
                CraftSessionListPane(viewModel: viewModel)
            case .llmSettings:
                CraftSettingsListPane(viewModel: viewModel, selection: $selection)
            case .sources:
                CraftSimpleListPane(title: "数据源", subtitle: "MCP Source Runtime", rows: viewModel.sourceRuntimeConfigurations.map(\.displayName))
            case .skills:
                CraftSimpleListPane(title: "技能", subtitle: "Skill Runtime", rows: viewModel.skillRuntimeDefinitions.map { $0.manifest.name })
            case .automation:
                CraftSimpleListPane(title: "自动化", subtitle: "事件触发与执行历史", rows: viewModel.automationConfig.rules.map(\.name))
            case .productOS:
                CraftSimpleListPane(title: "Product OS", subtitle: "本地控制面模块", rows: viewModel.productOSRegistry.sources.map(\.displayName) + viewModel.productOSRegistry.skills.map(\.displayName))
            default:
                CraftSimpleListPane(title: (selection ?? .agentChat).rawValue, subtitle: "康纳同学工作区", rows: [])
            }
        }
    }
}

private struct CraftSessionListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text(sessionListTitle)
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if filteredSessions.isEmpty {
                if viewModel.sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("暂无会话", systemImage: "bubble.left", description: Text("点击左上角新建会话开始。"))
                        .padding(.top, 80)
                } else {
                    ContentUnavailableView("没有匹配的会话", systemImage: "magnifyingglass", description: Text("搜索会匹配会话标题和消息内容。"))
                        .padding(.top, 80)
                }
            } else {
                List(filteredSessions) { session in
                    CraftSessionRow(
                        row: AgentChatSessionPresentation(session: session),
                        isSelected: session.id == viewModel.selectedChatSessionID,
                        isRunning: viewModel.isChatSessionSubmitting(session.id),
                        isRegeneratingTitle: viewModel.regeneratingTitleSessionIDs.contains(session.id),
                        hasRunningBackgroundTask: !viewModel.canDeleteChatSession(session.id),
                        labelDefinitions: viewModel.governanceConfig.labels,
                        onSelect: {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                viewModel.selectChatSession(session.id)
                            }
                        },
                        onRename: { title in viewModel.renameChatSession(session.id, title: title) },
                        onSetStatus: { status in viewModel.setChatSessionStatus(session.id, status: status) },
                        onToggleLabel: { labelID in viewModel.toggleChatSessionLabel(session.id, labelID: labelID) },
                        onRegenerateTitle: { viewModel.regenerateChatSessionTitle(session.id) },
                        onDelete: { viewModel.deleteChatSession(session.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { viewModel.reloadChatSessions() }
    }

    private var filteredSessions: [AgentSession] {
        AgentSessionTextSearchFilter().filter(viewModel.chatSessions, query: viewModel.sessionSearchQuery)
    }

    private var sessionListTitle: String {
        switch viewModel.sessionListFilter {
        case .all: "全部会话"
        case .status(let status): status.displayName
        case .label(let labelID): viewModel.governanceConfig.labels.first(where: { $0.id == labelID })?.name ?? labelID
        }
    }
}

private struct CraftDetailPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    var selection: SidebarItem

    var body: some View {
        Group {
            switch selection {
            case .entities:
                GraphEntitiesView(entities: viewModel.entities, statements: viewModel.statements, episodes: viewModel.episodes)
            case .search:
                SearchView(viewModel: viewModel)
            case .observeLog:
                ObserveLogView(entries: viewModel.observeLogEntries)
            case .agentChat:
                AgentChatView(viewModel: viewModel)
            case .promotionQueue:
                PromotionQueueView(viewModel: viewModel)
            case .graphWriteCandidates:
                GraphWriteCandidateReviewView(viewModel: viewModel)
            case .pendingApprovals:
                AgentPendingApprovalReviewView(viewModel: viewModel)
            case .memoryChangeLog:
                MemoryChangeLogView(viewModel: viewModel)
            case .extractionDiagnostics:
                GraphExtractionDiagnosticsView(viewModel: viewModel)
            case .automation:
                AutomationRuntimePanelView(viewModel: viewModel)
            case .productOS:
                ProductOSRegistryView(viewModel: viewModel)
            case .sources:
                SourceRuntimePanelView(viewModel: viewModel)
            case .skills:
                SkillRuntimePanelView(viewModel: viewModel)
            case .llmSettings:
                ConnorSettingsDetailView(viewModel: viewModel)
            }
        }
    }
}


private struct CraftSessionRow: View {
    var row: AgentChatSessionPresentation
    var isSelected: Bool
    var isRunning: Bool
    var isRegeneratingTitle: Bool
    var hasRunningBackgroundTask: Bool
    var labelDefinitions: [AgentSessionLabelDefinition]
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onSetStatus: (AgentSessionStatus) -> Void
    var onToggleLabel: (String) -> Void
    var onRegenerateTitle: () -> Void
    var onDelete: () -> Void

    @State private var isEditingTitle: Bool = false
    @State private var titleDraft: String = ""
    @State private var isDeleteConfirmationPresented: Bool = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        rowContent
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    onRegenerateTitle()
                } label: {
                    Label("重设标题", systemImage: "sparkles")
                }
                .disabled(isRegeneratingTitle)
                .tint(.orange)

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(hasRunningBackgroundTask)
            }
            .contextMenu { contextMenuItems }
            .onChange(of: row.title) { _, newTitle in
            guard !isEditingTitle else { return }
            titleDraft = newTitle
        }
            .onAppear { titleDraft = row.title }
            .confirmationDialog("删除这个会话？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
                .disabled(hasRunningBackgroundTask)
            Button("取消", role: .cancel) {}
            } message: {
                Text(hasRunningBackgroundTask ? "此会话仍有后台任务正在运行,请等待任务结束后再删除。" : "删除后会话将从列表中移除。")
            }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Menu {
            ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                Button {
                    onSetStatus(status)
                } label: {
                    Label(status.displayName, systemImage: status == row.status ? "checkmark.circle.fill" : icon(for: status))
                }
            }
        } label: {
            Label("更改状态", systemImage: "circle.dashed")
        }

        Menu {
            if labelDefinitions.isEmpty {
                Button {} label: {
                    Label("暂无可切换标签", systemImage: "tag.slash")
                }
                .disabled(true)
            } else {
                ForEach(labelDefinitions) { definition in
                    Button {
                        onToggleLabel(definition.id)
                    } label: {
                        Label(definition.name, systemImage: row.labels.contains(where: { $0.id == definition.id }) ? "checkmark.circle.fill" : "tag")
                    }
                }
            }
        } label: {
            Label("标签", systemImage: "tag")
        }

        Divider()

        Button {
            beginTitleEdit()
        } label: {
            Label("重命名", systemImage: "pencil")
        }

        Button {
            onRegenerateTitle()
        } label: {
            Label("重设标题", systemImage: "sparkles")
        }
        .disabled(isRegeneratingTitle)

        Divider()

        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            Label("删除", systemImage: "trash")
        }
        .disabled(hasRunningBackgroundTask)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            if isRunning || isRegeneratingTitle {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: row.isFlagged ? "pin.fill" : icon(for: row.status))
                    .foregroundStyle(row.isFlagged ? .orange : (isSelected ? .accentColor : .secondary))
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if isEditingTitle {
                        TextField("会话标题", text: $titleDraft)
                            .textFieldStyle(.plain)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .focused($isTitleFocused)
                            .lineLimit(1)
                            .onSubmit { commitTitleEdit() }
                    } else {
                        Text(row.title)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(1)
                            .onTapGesture(count: 2) { beginTitleEdit() }
                    }
                    Spacer(minLength: 4)
                    if isRunning {
                        Text("运行中")
                            .font(AppListTypography.rowCaptionEmphasized)
                            .foregroundStyle(Color.accentColor)
                    } else if isRegeneratingTitle {
                        Text("生成中")
                            .font(AppListTypography.rowCaptionEmphasized)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(row.relativeUpdatedTime)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(row.statusText)
                        .font(AppListTypography.rowCaptionEmphasized)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(row.status).opacity(0.14), in: Capsule())
                    Text("\(row.messageCount) 条消息")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                if !row.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(row.labels.prefix(3)), id: \.id) { label in
                            Text(label.id)
                                .font(AppListTypography.rowCaption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            if !isEditingTitle { onSelect() }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused, isEditingTitle { commitTitleEdit() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var rowBackgroundColor: Color {
        isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor)
    }


    private func beginTitleEdit() {
        titleDraft = row.title
        isEditingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        isTitleFocused = false
        guard !trimmed.isEmpty, trimmed != row.title else {
            titleDraft = row.title
            return
        }
        onRename(trimmed)
    }


    private func icon(for status: AgentSessionStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle.fill"
        case .blocked: "nosign"
        case .archived: "archivebox"
        }
    }

    private func statusColor(_ status: AgentSessionStatus) -> Color {
        switch status {
        case .todo: .secondary
        case .inProgress: .blue
        case .waiting: .orange
        case .needsReview: .purple
        case .done: .green
        case .blocked: .red
        case .archived: .gray
        }
    }
}


private struct CraftSettingsListPane: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            VStack(spacing: 0) {
                ForEach(ConnorSettingsSection.allCases) { section in
                    SettingsCategoryRow(
                        title: section.title,
                        subtitle: section.subtitle,
                        systemImage: section.systemImage,
                        isSelected: viewModel.selectedSettingsSection == section
                    ) {
                        selection = .llmSettings
                        viewModel.selectSettingsSection(section)
                    }
                }
            }
            .padding(10)
            Spacer()
        }
    }
}

private struct SettingsCategoryRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppListTypography.rowTitleSelected)
                    Text(subtitle).font(AppListTypography.rowSubtitle).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CraftSimpleListPane: View {
    var title: String
    var subtitle: String
    var rows: [String]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text(title).font(AppListTypography.header)
                Text(subtitle).font(AppListTypography.rowSubtitle).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rows.isEmpty ? ["在右侧查看详情"] : rows, id: \.self) { row in
                        Text(row)
                            .font(AppListTypography.rowTitle)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct SidebarDisclosure<Content: View>: View {
    var title: String
    var systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .padding(.leading, 12)
            .padding(.top, 3)
        } label: {
            Label(title, systemImage: systemImage)
                .font(AppListTypography.rowTitleSelected)
        }
        .disclosureGroupStyle(.automatic)
    }
}

private struct SidebarRow: View {
    var title: String
    var systemImage: String
    var count: Int?
    var isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    SidebarRowCountText(count: count, isVisible: isHovering)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityCountValue)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var accessibilityCountValue: String {
        count.map { "\($0)" } ?? ""
    }
}

private struct SidebarRowCountText: View {
    var count: Int
    var isVisible: Bool

    var body: some View {
        Text("\(count)")
            .font(AppListTypography.rowCaption.monospacedDigit())
            .foregroundStyle(.secondary)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }
}

private struct SidebarMutedText: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(AppListTypography.rowSubtitle)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}
