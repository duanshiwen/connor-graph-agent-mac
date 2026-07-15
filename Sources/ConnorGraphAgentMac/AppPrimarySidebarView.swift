import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct CraftPrimarySidebarView: View {
    let graph: AppFeatureGraph
    @Binding var selection: SidebarItem?
    var sendCommand: (AppCommand) -> Void
    @State private var sessionsExpanded = true
    @State private var labelsExpanded = true
    @State private var sourcesExpanded = true
    @State private var automationExpanded = true
    @State private var statusEditorRequest: StatusDefinitionEditorRequest?
    @State private var labelEditorRequest: LabelDefinitionEditorRequest?

    var body: some View {
        VStack(spacing: 10) {
            Button {
                sendCommand(.shortcut(.newSession))
                select(.agentChat)
            } label: {
                SidebarActionButtonLabel(title: "新建会话", systemImage: "square.and.pencil", minHeight: 32)
            }
            .buttonStyle(SidebarActionButtonStyle())
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Button {
                sendCommand(.newNote)
                select(.agentChat)
            } label: {
                SidebarActionButtonLabel(title: "新建或导入笔记", systemImage: "note.text.badge.plus", minHeight: 32)
            }
            .buttonStyle(SidebarActionButtonStyle())
            .padding(.horizontal, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SidebarDisclosure(title: "所有会话", systemImage: "tray", isExpanded: $sessionsExpanded) {
                        SidebarRow(title: "全部", systemImage: "bubble.left.and.bubble.right", count: allSessionsCount, isSelected: selection == .agentChat && graph.chat.sessions.filter == .all) {
                            graph.chatActions.session.setSessionListFilter(.all)
                            select(.agentChat)
                        }
                        .contextMenu {
                            Button("创建状态…", systemImage: "plus.circle") { presentNewStatusEditor() }
                        }
                        ForEach(graph.governance.config.statuses.sorted { $0.sortOrder < $1.sortOrder }) { status in
                            if let sessionStatus = AgentSessionStatus(rawValue: status.id) {
                                SidebarRow(title: status.name, systemImage: status.systemImage, count: count(for: sessionStatus), isSelected: selection == .agentChat && graph.chat.sessions.filter == .status(sessionStatus)) {
                                    graph.chatActions.session.setSessionListFilter(.status(sessionStatus))
                                    select(.agentChat)
                                }
                                .contextMenu {
                                    Button("编辑状态…", systemImage: "pencil") { presentStatusEditor(status) }
                                    Button("创建状态…", systemImage: "plus.circle") { presentNewStatusEditor(after: status) }
                                    Divider()
                                    Button(role: .destructive) { graph.governance.deleteStatus(status) } label: {
                                        Label("删除状态", systemImage: "trash")
                                    }
                                    .disabled(!graph.governance.canDeleteStatus(status))
                                }
                            } else {
                                SidebarRow(title: status.name, systemImage: status.systemImage, count: 0, isSelected: false) {
                                    presentStatusEditor(status)
                                }
                                .contextMenu {
                                    Button("编辑状态…", systemImage: "pencil") { presentStatusEditor(status) }
                                    Button("创建状态…", systemImage: "plus.circle") { presentNewStatusEditor(after: status) }
                                    Divider()
                                    Button(role: .destructive) { graph.governance.deleteStatus(status) } label: {
                                        Label("删除状态", systemImage: "trash")
                                    }
                                    .disabled(!graph.governance.canDeleteStatus(status))
                                }
                            }
                        }
                    }

                    SidebarDisclosure(title: "标签", systemImage: "tag", isExpanded: $labelsExpanded) {
                        if graph.governance.config.labels.isEmpty {
                            SidebarMutedText("暂无标签")
                                .contextMenu {
                                    Button("创建标签…", systemImage: "plus.circle") { presentNewLabelEditor() }
                                }
                        } else {
                            ForEach(graph.governance.config.labels) { label in
                                SidebarRow(title: label.name, systemImage: label.systemImage, count: count(forLabel: label.id), isSelected: selection == .agentChat && graph.chat.sessions.filter == .label(label.id)) {
                                    graph.chatActions.session.setSessionListFilter(.label(label.id))
                                    select(.agentChat)
                                }
                                .contextMenu {
                                    Button("编辑标签…", systemImage: "pencil") { presentLabelEditor(label) }
                                    Button("创建标签…", systemImage: "plus.circle") { presentNewLabelEditor() }
                                    Divider()
                                    Button(role: .destructive) { graph.governance.deleteLabel(label) } label: {
                                        Label("删除标签", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    SidebarRow(title: "人际关系", systemImage: "person.2", count: graph.contacts.presentation.rows.count, isSelected: selection == .contacts) { select(.contacts) }

                    SidebarDisclosure(title: "数据源", systemImage: "externaldrive.connected.to.line.below", isExpanded: $sourcesExpanded) {
                        SidebarRow(title: "日历", systemImage: "calendar", count: graph.calendar.presentation.eventCount, isSelected: selection == .calendar) { select(.calendar) }
                        SidebarRow(title: "邮件", systemImage: "envelope", count: mailSidebarCount, isSelected: selection == .mail) { select(.mail) }
                        SidebarRow(title: "RSS", systemImage: "dot.radiowaves.up.forward", count: rssUnreadCount, isSelected: selection == .rss) { select(.rss) }
                        SidebarRow(title: "MCP", systemImage: "server.rack", count: graph.sources.configurations.count, isSelected: selection == .sources) { select(.sources) }
                    }

                    SidebarRow(title: "技能", systemImage: "bolt", count: graph.skills.presentation.summary.total, isSelected: selection == .skills) { select(.skills) }

                    SidebarDisclosure(title: "自动化", systemImage: "wand.and.stars", isExpanded: $automationExpanded) {
                        SidebarRow(title: "定时任务", systemImage: "clock", count: graph.tasks.presentation.summary.scheduledTaskCount, isSelected: selection == .scheduledTasks) { select(.scheduledTasks) }
                        SidebarRow(title: "事件触发", systemImage: "dot.radiowaves.left.and.right", count: graph.tasks.presentation.summary.eventTriggeredTaskCount, isSelected: selection == .eventTriggeredTasks) { select(.eventTriggeredTasks) }
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
                    graph.governance.upsertStatus(definition)
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
                    graph.governance.upsertLabel(definition)
                    labelEditorRequest = nil
                }
            )
        }

    }

    private var allSessionsCount: Int {
        graph.chat.sessions.sidebarSummary.totalCount
    }

    private var mailSidebarCount: Int? {
        let unreadCount = graph.mail.presentation.totalUnreadCount
        if unreadCount > 0 { return unreadCount }
        let totalCount = graph.mail.presentation.totalMessageCount
        return totalCount > 0 ? totalCount : nil
    }

    private var rssUnreadCount: Int? {
        let count = graph.rss.presentation.unreadCount(sourceID: nil)
        return count > 0 ? count : nil
    }

    private func count(for status: AgentSessionStatus) -> Int {
        graph.chat.sessions.sidebarSummary.countsByStatus[status, default: 0]
    }

    private func count(forLabel labelID: String) -> Int {
        graph.chat.sessions.sidebarSummary.countsByLabelID[labelID, default: 0]
    }

    private func select(_ item: SidebarItem) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            _ = graph.shell.select(item)
        }
    }

    private func presentStatusEditor(_ definition: AgentSessionStatusDefinition) {
        statusEditorRequest = StatusDefinitionEditorRequest(definition: definition, isCreating: false)
    }

    private func presentNewStatusEditor(after definition: AgentSessionStatusDefinition? = nil) {
        let nextSortOrder = (definition?.sortOrder ?? graph.governance.config.statuses.map(\.sortOrder).max() ?? 0) + 10
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

struct StatusDefinitionEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionStatusDefinition
    var isCreating: Bool
}

struct LabelDefinitionEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionLabelDefinition
    var isCreating: Bool
}

struct StatusDefinitionEditorSheet: View {
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

struct LabelDefinitionEditorSheet: View {
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
    case "tray": return "待办"
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

