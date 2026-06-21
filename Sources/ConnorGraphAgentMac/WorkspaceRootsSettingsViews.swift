import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct WorkspaceRootsSettingsContent: View {
    @ObservedObject var viewModel: AppViewModel

    private var primaryRoot: WorkspaceRootDraft? {
        viewModel.workspaceRoots.first(where: \.isPrimary) ?? viewModel.workspaceRoots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前会话 Workspace")
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

            if !viewModel.workspaceRoots.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(viewModel.workspaceRoots) { root in
                        WorkspaceRootRow(
                            root: root,
                            setPrimary: { viewModel.setPrimaryWorkspaceRoot(id: root.id) },
                            remove: { viewModel.removeWorkspaceRoot(id: root.id) }
                        )
                        if root.id != viewModel.workspaceRoots.last?.id { Divider() }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("输入目录路径", text: $viewModel.workspaceRootPathInput)
                    .textFieldStyle(.roundedBorder)
                Button("添加路径") {
                    viewModel.addWorkspaceRoot(path: viewModel.workspaceRootPathInput)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.workspaceRootPathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("保存到当前 Session Capsule。Native local tools 可访问所有 roots；为空时回退到进程 cwd。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var summaryText: String {
        if let primaryRoot {
            return "主目录：\(primaryRoot.path) · 共 \(viewModel.workspaceRoots.count) 个 root"
        }
        let fallback = viewModel.defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty { return "默认项目目录：\(fallback)" }
        return "尚未设置；将使用进程 cwd。"
    }

    private func chooseDirectories() {
        let panel = NSOpenPanel()
        panel.title = "选择当前会话项目工作目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            viewModel.addWorkspaceRoots(paths: panel.urls.map(\.path))
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
    @ObservedObject var viewModel: AppViewModel

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
                subtitle: "管理应用和 Browser Workspace 的常用键盘操作。修改后会写入 runtime-settings.json 并立即用于菜单命令或局部 key monitor。",
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
                        shortcut: viewModel.shortcut(for: generalActions[index]),
                        onRecord: { viewModel.beginRecordingShortcut(for: generalActions[index]) },
                        onReset: { viewModel.resetShortcut(generalActions[index]) }
                    )
                }
            }

            SettingsGroup(title: "Browser Workspace") {
                ForEach(browserActions.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    EditableShortcutRow(
                        title: title(for: browserActions[index]),
                        subtitle: subtitle(for: browserActions[index]),
                        shortcut: viewModel.shortcut(for: browserActions[index]),
                        onRecord: { viewModel.beginRecordingShortcut(for: browserActions[index]) },
                        onReset: { viewModel.resetShortcut(browserActions[index]) }
                    )
                }
            }

            SettingsGroup(title: "语音输入") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("按住说话 · 鼠标按住或按住 Option", systemImage: "mic")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("Composer 的语音输入使用系统语音识别：录音中显示实时 partial 结果，松开后直接提交当前识别文本，不再启动后台整理任务。浏览器媒体转写仍使用独立的本地媒体运行时。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("长按空格可以作为未来高级选项，但默认关闭；只有在能够消费 Space keyDown、避免向文本框输入重复空格时才应启用。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }

            Text("修改后会写入 runtime-settings.json,并由菜单命令或 Browser Workspace 局部 key monitor 真实生效。Governance / Source / Skill 等低频入口不在此页暴露快捷键,避免占用过多 ⌘ 数字键。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $viewModel.recordingShortcutAction) { action in
            ShortcutRecorderSheet(
                title: title(for: action),
                currentShortcut: viewModel.shortcut(for: action),
                onCancel: { viewModel.recordingShortcutAction = nil },
                onSave: { shortcut in viewModel.updateShortcut(action, shortcut: shortcut) }
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
        case .focusBrowserAddress: "Browser Workspace 可见时聚焦地址栏。"
        case .newBrowserTab: "Browser Workspace 可见时创建新标签。"
        case .closeBrowserTab: "Browser Workspace 可见时关闭当前标签,不关闭 macOS 窗口。"
        case .browserBack: "Browser Workspace 当前标签后退。"
        case .browserForward: "Browser Workspace 当前标签前进。"
        case .toggleBrowserBookmarks: "切换浏览器书签面板。"
        case .toggleBrowserHistory: "切换浏览器历史面板。"
        }
    }
}

struct SettingsPreferencesSection: View {
    @ObservedObject var viewModel: AppViewModel

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
                SettingsTextFieldRow(title: "称呼", subtitle: "康纳同学如何称呼你。首次启动且未设置时会读取 macOS 账户名称，可手动更改。", text: $viewModel.userDisplayName)
                Divider()
                SettingsTextFieldRow(title: "时区", subtitle: "未设置时自动读取系统时区，用于相对日期和日程上下文。", text: $viewModel.userTimezone)
                Divider()
                SettingsTextFieldRow(title: "语言偏好", subtitle: "未设置时自动读取系统语言；康纳同学会优先按此语言回复。", text: $viewModel.userPreferredLanguage)
                Divider()
                SettingsTextFieldRow(title: "出生日期", subtitle: "可选。建议使用 YYYY-MM-DD，用于年龄、人生阶段和长期个性化上下文。", text: $viewModel.userBirthDate)
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
                    Button("重新读取空白项") { viewModel.refreshSystemPreferenceDefaults() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            SettingsGroup(title: "位置") {
                SettingsTextFieldRow(title: "城市", subtitle: "用于本地信息和上下文。不会在启动时自动请求定位权限，可手动填写或主动授权读取。", text: $viewModel.userCity)
                Divider()
                SettingsTextFieldRow(title: "国家/地区", subtitle: "未设置时会优先从系统地区推断，也可手动更改。", text: $viewModel.userCountry)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前位置")
                            .font(SettingsListTypography.rowTitleSelected)
                        if let message = viewModel.userLocationStatusMessage {
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
                    Button("使用当前位置") { viewModel.requestUserLocation() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            SettingsGroup(title: "备注") {
                TextEditor(text: $viewModel.userPreferenceNotes)
                    .font(SettingsListTypography.rowTitle)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
