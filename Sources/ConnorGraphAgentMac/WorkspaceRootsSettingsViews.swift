import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct WorkspaceRootsSettingsContent: View {
    @Bindable var model: WorkspaceSettingsFeatureModel

    private var primaryRoot: WorkspaceRootDraft? {
        model.roots.first(where: \.isPrimary) ?? model.roots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前会话工作目录")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text(summaryText)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("选择目录…") { chooseDirectories() }
                    .buttonStyle(.bordered)
            }
            .frame(minHeight: SettingsListLayout.rowMinHeight)

            if !model.roots.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(model.roots) { root in
                        WorkspaceRootRow(
                            root: root,
                            setPrimary: { model.setPrimaryRoot(id: root.id) },
                            remove: { model.removeRoot(id: root.id) }
                        )
                        if root.id != model.roots.last?.id { Divider() }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("输入目录路径", text: $model.pathInput)
                    .textFieldStyle(.roundedBorder)
                Button("添加路径") {
                    model.addRoot(path: model.pathInput)
                }
                .buttonStyle(.bordered)
                .disabled(model.pathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("这些目录只用于当前会话。本地工具可在你授权的目录中读取或处理文件；未设置时使用默认工作目录。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var summaryText: String {
        if let primaryRoot {
            return "主目录：\(primaryRoot.path) · 共 \(model.roots.count) 个目录"
        }
        let fallback = model.defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty { return "默认项目目录：\(fallback)" }
        return "尚未设置；将使用默认工作目录。"
    }

    private func chooseDirectories() {
        let panel = NSOpenPanel()
        panel.title = "选择当前会话项目工作目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            model.addRoots(paths: panel.urls.map(\.path))
        }
    }
}

struct WorkspaceRootRow: View {
    var root: WorkspaceRootDraft
    var setPrimary: () -> Void
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(root.displayName.isEmpty ? URL(fileURLWithPath: root.path).lastPathComponent : root.displayName)
                        .font(SettingsListTypography.rowTitleSelected)
                    Text(root.role)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                    if root.isPrimary {
                        Text("主目录")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(root.path)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !root.isPrimary {
                Button("设为主目录", action: setPrimary)
                    .buttonStyle(.bordered)
            }
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: 50)
        .padding(.vertical, 6)
    }
}

struct SettingsShortcutsSection: View {
    @Bindable var model: InputSettingsFeatureModel

    private let generalActions: [AgentRuntimeShortcutAction] = [
        .newSession,
        .toggleBrowser,
        .focusTopSearch,
        .openSettings
    ]

    private let browserActions: [AgentRuntimeShortcutAction] = [
        .focusBrowserAddress,
        .newBrowserTab,
        .closeBrowserTab,
        .browserBack,
        .browserForward,
        .toggleBrowserBookmarks,
        .toggleBrowserHistory
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "快捷键",
                subtitle: "管理应用和内置浏览器的常用键盘操作。修改后会立即生效。",
                systemImage: "keyboard"
            ) {
                EmptyView()
            }

            SettingsGroup(title: "全局") {
                ForEach(generalActions.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    EditableShortcutRow(
                        title: title(for: generalActions[index]),
                        subtitle: subtitle(for: generalActions[index]),
                        shortcut: model.shortcut(for: generalActions[index]),
                        onRecord: { model.beginRecordingShortcut(for: generalActions[index]) },
                        onReset: { model.resetShortcut(generalActions[index]) }
                    )
                }
            }

            SettingsGroup(title: "内置浏览器") {
                ForEach(browserActions.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    EditableShortcutRow(
                        title: title(for: browserActions[index]),
                        subtitle: subtitle(for: browserActions[index]),
                        shortcut: model.shortcut(for: browserActions[index]),
                        onRecord: { model.beginRecordingShortcut(for: browserActions[index]) },
                        onReset: { model.resetShortcut(browserActions[index]) }
                    )
                }
            }

            SettingsGroup(title: "语音输入") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("按住说话 · 鼠标按住或按住 Option", systemImage: "mic")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("在对话输入框中按住说话，录音时会显示实时识别文字，松开后直接发送当前识别内容。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("目前推荐使用鼠标按住或 Option 键进行语音输入，避免和文字输入冲突。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }

            Text("修改后的快捷键会立即生效。此处只展示常用操作，低频入口暂不单独配置快捷键。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $model.recordingShortcutAction) { action in
            ShortcutRecorderSheet(
                title: title(for: action),
                currentShortcut: model.shortcut(for: action),
                onCancel: { model.recordingShortcutAction = nil },
                onSave: { shortcut in model.updateShortcut(action, shortcut: shortcut) }
            )
        }
    }

    private func title(for action: AgentRuntimeShortcutAction) -> String {
        switch action {
        case .newSession: "新建会话"
        case .toggleBrowser: "切换浏览器"
        case .focusTopSearch: "搜索"
        case .openSettings: "设置…"
        case .focusBrowserAddress: "聚焦地址栏"
        case .newBrowserTab: "新建浏览器标签"
        case .closeBrowserTab: "关闭当前标签"
        case .browserBack: "后退"
        case .browserForward: "前进"
        case .toggleBrowserBookmarks: "打开 / 关闭书签"
        case .toggleBrowserHistory: "打开 / 关闭历史"
        }
    }

    private func subtitle(for action: AgentRuntimeShortcutAction) -> String {
        switch action {
        case .newSession: "创建新会话并进入聊天。"
        case .toggleBrowser: "在当前会话中切换内置浏览器工作区。"
        case .focusTopSearch: "聚焦应用顶部的会话搜索框。"
        case .openSettings: "打开设置中心。"
        case .focusBrowserAddress: "内置浏览器可见时聚焦地址栏。"
        case .newBrowserTab: "内置浏览器可见时创建新标签。"
        case .closeBrowserTab: "内置浏览器可见时关闭当前标签，不关闭应用窗口。"
        case .browserBack: "内置浏览器当前标签后退。"
        case .browserForward: "内置浏览器当前标签前进。"
        case .toggleBrowserBookmarks: "切换浏览器书签面板。"
        case .toggleBrowserHistory: "切换浏览器历史面板。"
        }
    }
}

struct SettingsPreferencesSection: View {
    @Bindable var model: UserPreferencesFeatureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "偏好",
                subtitle: "管理康纳同学用于称呼、语言、时区、位置和个性化上下文的用户信息。",
                systemImage: "person.crop.circle"
            ) {
                EmptyView()
            }

            SettingsGroup(title: "基本信息") {
                SettingsTextFieldRow(title: "称呼", subtitle: "康纳同学如何称呼你。首次启动且未设置时会读取 macOS 账户名称，可手动更改。", text: $model.displayName)
                Divider()
                SettingsTextFieldRow(title: "时区", subtitle: "未设置时自动读取系统时区，用于相对日期和日程上下文。", text: $model.timezone)
                Divider()
                SettingsTextFieldRow(title: "语言偏好", subtitle: "未设置时自动读取系统语言；康纳同学会优先按此语言回复。", text: $model.preferredLanguage)
                Divider()
                SettingsGenderIdentityRow(model: model)
                Divider()
                SettingsBirthDatePickerRow(
                    title: "出生日期",
                    subtitle: "可选。用于年龄、人生阶段和长期个性化上下文。",
                    date: $model.birthDatePickerDate,
                    hasValue: !model.birthDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onDateChange: { model.setBirthDateFromPicker($0) },
                    onClear: { model.clearBirthDate() }
                )
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("系统默认")
                            .font(SettingsListTypography.rowTitleSelected)
                        Text("只补全仍为空的项目，不覆盖你已经手动填写的偏好。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("重新读取空白项") { model.refreshSystemDefaults() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            SettingsGroup(title: "位置") {
                SettingsTextFieldRow(title: "城市", subtitle: "用于本地信息和上下文。不会在启动时自动请求定位权限，可手动填写或主动授权读取。", text: $model.city)
                Divider()
                SettingsTextFieldRow(title: "国家/地区", subtitle: "未设置时会优先从系统地区推断，也可手动更改。", text: $model.country)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前位置")
                            .font(SettingsListTypography.rowTitleSelected)
                        if let message = model.locationStatusMessage {
                            Text(message)
                                .font(SettingsListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("申请位置权限后自动填写城市和国家/地区。")
                                .font(SettingsListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("使用当前位置") { model.requestLocation() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            SettingsGroup(title: "备注") {
                TextEditor(text: $model.notes)
                    .font(SettingsListTypography.rowTitle)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct SettingsGenderIdentityRow: View {
    @Bindable var model: UserPreferencesFeatureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("性别")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("可选。用于称呼、语气和长期个性化上下文；不会推断法定性别或出生性别。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(
                    "性别",
                    selection: Binding(
                        get: { model.genderIdentitySelection },
                        set: { model.setGenderIdentitySelection($0) }
                    )
                ) {
                    Text("未设置").tag("")
                    Text("女性").tag("女性")
                    Text("男性").tag("男性")
                    Text("非二元").tag("非二元")
                    Text("性别流动").tag("性别流动")
                    Text("无性别").tag("无性别")
                    Text("酷儿 / 性别酷儿").tag("酷儿 / 性别酷儿")
                    Text("不愿透露").tag("不愿透露")
                    Text("自我描述…").tag(UserPreferencesFeatureModel.customGenderIdentitySelection)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
            }
            .frame(minHeight: SettingsListLayout.rowMinHeight)

            if model.genderIdentitySelection == UserPreferencesFeatureModel.customGenderIdentitySelection {
                TextField(
                    "请描述你的性别身份",
                    text: Binding(
                        get: { model.genderIdentityCustomText },
                        set: { model.setGenderIdentityCustomText($0) }
                    )
                )
                .font(SettingsListTypography.rowTitle)
                .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
