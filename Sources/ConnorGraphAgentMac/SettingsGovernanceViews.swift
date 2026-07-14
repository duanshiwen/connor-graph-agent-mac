import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct SettingsLabelsSection: View {
    @Bindable var model: GovernanceFeatureModel
    var sessions: [AgentSession]
    @State private var editorRequest: SettingsLabelEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "标签",
                subtitle: "用颜色、名称和图标整理会话。标签只用于分类和筛选，不影响会话内容。",
                systemImage: "tag"
            ) {
                Button("新建标签…") { presentNewLabelEditor() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            SettingsGroup(title: "标签") {
                if model.config.labels.isEmpty {
                    SettingsEmptyStateRow(systemImage: "tag.slash", title: "暂无标签", subtitle: "点击“新建标签…”创建第一个会话标签。")
                } else {
                    ForEach(model.config.labels) { label in
                        SettingsLabelDefinitionRow(
                            definition: label,
                            usageCount: countSessions(using: label.id),
                            edit: { presentLabelEditor(label) },
                            delete: { model.deleteLabel(label) }
                        )
                        if label.id != model.config.labels.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }

            SettingsGroup(title: "删除行为") {
                Text("删除标签会自动从所有会话中移除该标签，然后删除标签定义。")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $editorRequest) { request in
            SettingsLabelEditorSheet(
                title: request.isCreating ? "新建标签" : "编辑标签",
                definition: request.definition,
                onCancel: { editorRequest = nil },
                onSave: { updated in
                    model.upsertLabel(updated)
                    editorRequest = nil
                }
            )
        }
    }

    private func presentLabelEditor(_ definition: AgentSessionLabelDefinition) {
        editorRequest = SettingsLabelEditorRequest(definition: definition, isCreating: false)
    }

    private func presentNewLabelEditor() {
        editorRequest = SettingsLabelEditorRequest(
            definition: AgentSessionLabelDefinition(id: "", name: "", colorName: "blue", systemImage: "tag"),
            isCreating: true
        )
    }

    private func countSessions(using labelID: String) -> Int {
        sessions.filter { session in
            session.governance.labels.contains { $0.id == labelID }
        }.count
    }
}

struct SettingsStatusesSection: View {
    @Bindable var model: GovernanceFeatureModel
    var sessions: [AgentSession]
    @State private var editorRequest: SettingsStatusEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "状态",
                subtitle: "管理会话状态的名称和图标，用来标记会话当前进展。",
                systemImage: "circle.dashed"
            ) {
                Button("新建状态…") { presentNewStatusEditor() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            SettingsGroup(title: "状态") {
                ForEach(sortedStatuses) { status in
                    SettingsStatusDefinitionRow(
                        definition: status,
                        usageCount: countSessions(using: status),
                        canDelete: model.canDeleteStatus(status),
                        edit: { presentStatusEditor(status) },
                        delete: { model.deleteStatus(status) }
                    )
                    if status.id != sortedStatuses.last?.id { Divider().padding(.leading, 48) }
                }
            }

            SettingsGroup(title: "删除限制") {
                Text("至少需要保留一个状态。正在被会话使用的状态不能删除。")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $editorRequest) { request in
            SettingsStatusEditorSheet(
                title: request.isCreating ? "新建状态" : "编辑状态",
                definition: request.definition,
                onCancel: { editorRequest = nil },
                onSave: { updated in
                    model.upsertStatus(updated)
                    editorRequest = nil
                }
            )
        }
    }

    private var sortedStatuses: [AgentSessionStatusDefinition] {
        model.config.statuses.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder { return lhs.name < rhs.name }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private func presentStatusEditor(_ definition: AgentSessionStatusDefinition) {
        editorRequest = SettingsStatusEditorRequest(definition: definition, isCreating: false)
    }

    private func presentNewStatusEditor() {
        let nextSortOrder = (model.config.statuses.map(\.sortOrder).max() ?? 0) + 10
        editorRequest = SettingsStatusEditorRequest(
            definition: AgentSessionStatusDefinition(id: "", name: "", systemImage: "circle", sortOrder: nextSortOrder, isTerminal: false),
            isCreating: true
        )
    }

    private func countSessions(using definition: AgentSessionStatusDefinition) -> Int {
        sessions.filter { $0.governance.status.rawValue == definition.id }.count
    }
}

struct SettingsLabelEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionLabelDefinition
    var isCreating: Bool
}

struct SettingsStatusEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionStatusDefinition
    var isCreating: Bool
}

struct SettingsHeroHeader<Accessory: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: SettingsListLayout.spaceL) {
            Image(systemName: systemImage)
                .font(SettingsListTypography.largeIcon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
                Text(title).font(SettingsListTypography.header)
                Text(subtitle)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SettingsListLayout.spaceL)
            accessory
        }
        .frame(minHeight: 72)
    }
}

struct SettingsEmptyStateRow: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 54)
    }
}

struct SettingsLabelDefinitionRow: View {
    var definition: AgentSessionLabelDefinition
    var usageCount: Int
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(settingsLabelColor(from: definition.colorName)).frame(width: 28, height: 28)
                Image(systemName: definition.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name).font(SettingsListTypography.rowTitleSelected)
                Text("用于 \(usageCount) 个会话")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑…", action: edit)
                .controlSize(.regular)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44)
            .help("删除标签")
        }
        .frame(minHeight: 56)
        .contextMenu {
            Button("编辑标签…", systemImage: "pencil", action: edit)
            Button(role: .destructive, action: delete) { Label("删除标签", systemImage: "trash") }
        }
    }
}

struct SettingsStatusDefinitionRow: View {
    var definition: AgentSessionStatusDefinition
    var usageCount: Int
    var canDelete: Bool
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: definition.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name).font(SettingsListTypography.rowTitleSelected)
                Text("用于 \(usageCount) 个会话")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑…", action: edit)
                .controlSize(.regular)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44)
            .disabled(!canDelete)
            .help(canDelete ? "删除状态" : "至少保留一个状态，且不能删除正在被会话使用的状态")
        }
        .frame(minHeight: 56)
        .contextMenu {
            Button("编辑状态…", systemImage: "pencil", action: edit)
            Button(role: .destructive, action: delete) { Label("删除状态", systemImage: "trash") }
                .disabled(!canDelete)
        }
    }
}

struct SettingsLabelEditorSheet: View {
    var title: String
    var definition: AgentSessionLabelDefinition
    var onCancel: () -> Void
    var onSave: (AgentSessionLabelDefinition) -> Void

    @State private var name: String
    @State private var color: Color
    @State private var systemImage: String

    init(title: String, definition: AgentSessionLabelDefinition, onCancel: @escaping () -> Void, onSave: @escaping (AgentSessionLabelDefinition) -> Void) {
        self.title = title
        self.definition = definition
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: definition.name)
        _color = State(initialValue: settingsLabelColor(from: definition.colorName))
        _systemImage = State(initialValue: definition.systemImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(SettingsListTypography.header)
            TextField("标签名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("图标", selection: $systemImage) {
                ForEach(settingsLabelIconOptions, id: \.self) { icon in
                    Label(settingsLabelIconTitle(for: icon), systemImage: icon).tag(icon)
                }
            }
            .pickerStyle(.menu)
            ColorPicker("颜色", selection: $color, supportsOpacity: false)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(AgentSessionLabelDefinition(id: definition.id, name: settingsTrimmed(name), colorName: settingsColorStorageName(from: color), systemImage: systemImage))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(settingsTrimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct SettingsStatusEditorSheet: View {
    var title: String
    var definition: AgentSessionStatusDefinition
    var onCancel: () -> Void
    var onSave: (AgentSessionStatusDefinition) -> Void

    @State private var name: String
    @State private var systemImage: String

    init(title: String, definition: AgentSessionStatusDefinition, onCancel: @escaping () -> Void, onSave: @escaping (AgentSessionStatusDefinition) -> Void) {
        self.title = title
        self.definition = definition
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: definition.name)
        _systemImage = State(initialValue: definition.systemImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(SettingsListTypography.header)
            TextField("状态名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("图标", selection: $systemImage) {
                ForEach(settingsStatusIconOptions, id: \.self) { icon in
                    Label(settingsStatusIconTitle(for: icon), systemImage: icon).tag(icon)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(AgentSessionStatusDefinition(id: definition.id, name: settingsTrimmed(name), systemImage: systemImage, sortOrder: definition.sortOrder, isTerminal: definition.isTerminal))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(settingsTrimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private let settingsStatusIconOptions: [String] = [
    "circle", "clock", "pause.circle", "play.circle", "checkmark.circle", "checkmark.circle.fill", "xmark.circle", "nosign", "exclamationmark.circle", "exclamationmark.bubble", "questionmark.circle", "flag", "star", "bolt", "flame", "tray", "archivebox", "paperplane", "hammer", "wrench.and.screwdriver", "lightbulb", "sparkles", "target"
]

private func settingsStatusIconTitle(for icon: String) -> String {
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

private let settingsLabelIconOptions: [String] = [
    "tag", "tag.fill", "star", "star.fill", "flag", "flag.fill", "bookmark", "bookmark.fill", "doc.text", "doc.text.magnifyingglass", "folder", "folder.fill", "calendar", "calendar.badge.clock", "person.2", "link", "paperclip", "lightbulb", "sparkles", "flame"
]

private func settingsLabelIconTitle(for icon: String) -> String {
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

private func settingsTrimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func settingsLabelColor(from storageName: String) -> Color {
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

private func settingsColorStorageName(from color: Color) -> String {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
    let red = Int((nsColor.redComponent * 255).rounded())
    let green = Int((nsColor.greenComponent * 255).rounded())
    let blue = Int((nsColor.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
}
