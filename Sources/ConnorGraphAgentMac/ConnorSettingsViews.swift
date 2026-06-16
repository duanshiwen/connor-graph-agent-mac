import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct LLMSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("模型提供方", selection: $viewModel.llmProviderMode) {
                Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
                Text("Claude Sidecar").tag(AppLLMProviderMode.governedClaudeSidecar)
            }
            .pickerStyle(.segmented)

            if viewModel.llmProviderMode == .governedClaudeSidecar {
                GroupBox("Governed Claude SDK Sidecar") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Sidecar executable path，例如 /usr/local/bin/node", text: $viewModel.sidecarExecutablePath)
                            .textFieldStyle(.roundedBorder)
                        TextField("Sidecar arguments，例如 sidecars/claude-agent-engine/claude-sidecar.mjs", text: $viewModel.sidecarArguments)
                            .textFieldStyle(.roundedBorder)
                        TextField("Working directory", text: $viewModel.sidecarWorkingDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                        Picker("康纳同学权限模式", selection: $viewModel.sidecarPermissionMode) {
                            Text("只读").tag(AgentPermissionMode.readOnly)
                            Text("写入需审批").tag(AgentPermissionMode.askToWrite)
                            Text("受信写入").tag(AgentPermissionMode.trustedWrite)
                        }
                        .pickerStyle(.segmented)
                        Text("安全边界：SDK permissionMode 固定为 bypassPermissions；康纳同学保留 session、pending approval、audit、graph memory 和 product state 主权。Sidecar 模式不允许 allowAll。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TextField("Base URL", text: $viewModel.llmBaseURLString)
                    .textFieldStyle(.roundedBorder)
                TextField("模型列表（逗号分隔）", text: $viewModel.llmModel)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("保存设置") { viewModel.saveLLMSettings() }
                Button("清除 API Key") { viewModel.clearLLMAPIKey() }
                Button("重新加载") { viewModel.loadLLMSettings() }
                Button(viewModel.isTestingLLMConnection ? "测试中…" : "测试连接") {
                    Task { await viewModel.testLLMConnection() }
                }
                .disabled(viewModel.isTestingLLMConnection)
            }

            Text(viewModel.llmHasAPIKey ? "API Key：已本地加密保存" : "API Key：尚未保存")
                .foregroundStyle(viewModel.llmHasAPIKey ? .green : .secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("安全提示：API Key 会保存到康纳同学 Home 的本地加密凭据文件", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    Text("为减少钥匙串弹窗，康纳同学会使用本机生成的 master key 对 API Key 进行 AES-GCM 加密，并写入 Application Support/Connor/config/credentials。")
                    Text("API Key 不会以明文写入应用设置、项目文件或 Git 仓库；删除 API Key 会移除对应加密凭据文件。")
                    Text("这是本机本地加密存储，不依赖 macOS 钥匙串授权弹窗。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = viewModel.llmSettingsMessage {
                Text(message).foregroundStyle(.secondary)
            }
            if let message = viewModel.llmHealthCheckMessage {
                Text(message).foregroundStyle(message.contains("OK") || message.contains("available") ? .green : .secondary)
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("模型设置")
    }
}

struct ConnorSettingsDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    Text(viewModel.selectedSettingsSection.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button(action: { viewModel.resetRuntimeSettings() }) {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.borderless)
                    .help("更多")
                }

                Group {
                    switch viewModel.selectedSettingsSection {
                    case .app:
                        SettingsAppSection(viewModel: viewModel)
                    case .ai:
                        SettingsAISection(viewModel: viewModel)
                    case .appearance:
                        SettingsAppearanceSection(viewModel: viewModel)
                    case .input:
                        SettingsInputSection(viewModel: viewModel)
                    case .permissions:
                        SettingsPermissionsSection(viewModel: viewModel)
                    case .labels:
                        SettingsLabelsSection(viewModel: viewModel)
                    case .shortcuts:
                        SettingsShortcutsSection()
                    case .preferences:
                        SettingsPreferencesSection(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)

                if let message = viewModel.appSettingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
        .task {
            viewModel.loadRuntimeSettings()
        }
    }
}

private struct SettingsAppSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "通知") {
                SettingsToggleRow(title: "桌面通知", subtitle: "AI 在聊天中完成工作时发送通知。", isOn: $viewModel.desktopNotificationsEnabled)
            }
            SettingsGroup(title: "电源") {
                SettingsToggleRow(title: "保持屏幕常亮", subtitle: "会话运行时防止屏幕关闭。", isOn: $viewModel.keepScreenAwake)
            }
            SettingsGroup(title: "工具") {
                SettingsToggleRow(title: "内置浏览器", subtitle: "如果使用外部浏览器工具，则禁用。", isOn: $viewModel.internalBrowserEnabled)
            }
            SettingsGroup(title: "网络") {
                SettingsToggleRow(title: "HTTP 代理", subtitle: "通过代理服务器路由网络流量。", isOn: $viewModel.httpProxyEnabled)
                if viewModel.httpProxyEnabled {
                    Divider()
                    SettingsTextFieldRow(title: "代理地址", subtitle: "例如 http://127.0.0.1:7890", text: $viewModel.httpProxyURLString)
                }
            }
            SettingsGroup(title: "关于") {
                SettingsValueRow(title: "版本", value: "0.1.0")
                Divider()
                HStack {
                    Text("检查更新")
                    Spacer()
                    Button("立即检查") { viewModel.appSettingsMessage = "当前为本地开发版本。" }
                }
                .font(.subheadline)
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsAISection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "默认") {
                SettingsPickerRow(title: "默认连接", subtitle: "新聊天使用的 AI 连接；每个连接有自己的协议类型和凭据。", selection: $viewModel.llmDefaultConnectionID) {
                    ForEach(viewModel.llmConnectionConfigs) { connection in
                        Text("\(connection.name) · \(connection.providerMode.displayName)").tag(connection.id)
                    }
                }
                .onChange(of: viewModel.llmDefaultConnectionID) { _, newValue in
                    viewModel.selectDefaultLLMConnection(newValue)
                }
                Divider()
                HStack(spacing: 10) {
                    Button("添加 OpenAI Compatible") { viewModel.addLLMConnection(providerMode: .openAICompatible) }
                    Button("添加 Claude") { viewModel.addLLMConnection(providerMode: .governedClaudeSidecar) }
                    Button("删除当前连接") { viewModel.deleteSelectedLLMConnection() }
                        .disabled(viewModel.llmConnectionConfigs.count <= 1)
                }
                .controlSize(.regular)
                Divider()
                SettingsPickerRow(title: "权限", subtitle: "新聊天默认权限", selection: $viewModel.defaultPermissionMode) {
                    ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            SettingsGroup(title: "当前连接") {
                SettingsTextFieldRow(title: "名称", subtitle: "显示在连接列表和聊天模型选择器中。", text: $viewModel.llmConnectionName)
                Divider()
                SettingsPickerRow(title: "协议", subtitle: "同一个连接只能选择一种调用协议。", selection: $viewModel.llmProviderMode) {
                    Text("OpenAI Compatible").tag(AppLLMProviderMode.openAICompatible)
                    Text("Claude").tag(AppLLMProviderMode.governedClaudeSidecar)
                }
                Divider()
                SettingsTextFieldRow(title: "模型列表", subtitle: "逗号分隔多个候选模型；聊天输入区每次只选择其中一个实际模型。", text: $viewModel.llmModel)
                if viewModel.llmProviderMode == .openAICompatible {
                    Divider()
                    SettingsTextFieldRow(title: "Base URL", subtitle: "OpenAI-compatible endpoint", text: $viewModel.llmBaseURLString)
                    Divider()
                    SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 6)
                    Divider()
                    SettingsValueRow(title: "API Key", value: viewModel.llmHasAPIKey ? "已本地加密保存" : "尚未保存")
                }
                Divider()
                HStack(spacing: 10) {
                    Button("保存 AI 设置") {
                        viewModel.saveLLMSettings()
                        viewModel.saveRuntimeSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("清除 API Key") { viewModel.clearLLMAPIKey() }
                        .disabled(viewModel.llmProviderMode != .openAICompatible)
                    Button(viewModel.isTestingLLMConnection ? "测试中…" : "测试连接") {
                        Task { await viewModel.testLLMConnection() }
                    }
                    .disabled(viewModel.isTestingLLMConnection)
                }
                .controlSize(.regular)
            }

            if viewModel.llmProviderMode == .governedClaudeSidecar {
                SettingsGroup(title: "Claude Sidecar") {
                    SettingsTextFieldRow(title: "可执行文件", subtitle: "例如 /usr/local/bin/node", text: $viewModel.sidecarExecutablePath)
                    Divider()
                    SettingsTextFieldRow(title: "参数", subtitle: "sidecars/claude-agent-engine/claude-sidecar.mjs", text: $viewModel.sidecarArguments)
                    Divider()
                    SettingsTextFieldRow(title: "工作目录", subtitle: "兼容旧配置 fallback；当前会话 Workspace 请在会话界面顶部设置", text: $viewModel.sidecarWorkingDirectoryPath)
                }
            }

            if let message = viewModel.llmSettingsMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let message = viewModel.llmHealthCheckMessage {
                Text(message).font(.caption).foregroundStyle(message.contains("OK") || message.contains("available") ? .green : .secondary)
            }
        }
    }
}

private struct SettingsAppearanceSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "默认主题") {
                HStack {
                    Text("模式")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("模式", selection: $viewModel.appearanceMode) {
                        ForEach(ConnorAppearanceMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                Divider()
                SettingsValueRow(title: "颜色主题", value: "使用默认")
                Divider()
                SettingsValueRow(title: "字体", value: "系统")
                Divider()
                SettingsValueRow(title: "语言", value: "简体中文")
            }
            SettingsGroup(title: "界面") {
                SettingsToggleRow(title: "连接图标", subtitle: "在会话列表和模型选择器中显示提供商图标。", isOn: $viewModel.showProviderIcons)
                Divider()
                SettingsToggleRow(title: "丰富的工具描述", subtitle: "为工具调用添加操作名称和意图描述。", isOn: $viewModel.richToolDescriptionsEnabled)
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsInputSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "发送") {
                SettingsPickerRow(title: "发送消息", subtitle: "选择默认发送快捷键", selection: $viewModel.composerSendShortcut) {
                    Text("Return").tag("return")
                    Text("⌘ Return").tag("cmd-return")
                }
                Divider()
                SettingsToggleRow(title: "自动保存草稿", subtitle: "切换会话时保留未发送输入。", isOn: $viewModel.autoSaveDraftsEnabled)
                Divider()
                SettingsToggleRow(title: "拼写检查", subtitle: "使用系统拼写检查。", isOn: $viewModel.spellCheckEnabled)
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsPermissionsSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "默认权限") {
                SettingsPickerRow(title: "新会话权限", subtitle: "控制工具调用和写入操作", selection: $viewModel.defaultPermissionMode) {
                    ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Divider()
                SettingsToggleRow(title: "网络访问需要审批", subtitle: "外部网络请求默认进入审批流程。", isOn: $viewModel.requireApprovalForNetwork)
                Divider()
                SettingsToggleRow(title: "Shell 写入需要审批", subtitle: "本地命令涉及写入时默认要求确认。", isOn: $viewModel.requireApprovalForShell)
            }
            Text("项目工作目录已改为每个会话内设置：打开任意会话，在会话顶部的 ‘当前会话 Workspace’ 中配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

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
                        .font(.subheadline.weight(.medium))
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("选择目录…") { chooseDirectories() }
                    .buttonStyle(.bordered)
            }
            .frame(minHeight: 42)

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
            Text("保存到当前 Session Capsule。Native local tools 可访问所有 roots；Claude Sidecar cwd 使用主目录。为空时兼容旧 Sidecar 目录，再回退到进程 cwd。")
                .font(.caption)
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
        return "尚未设置；将使用旧 Sidecar 工作目录或进程 cwd。"
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

private struct WorkspaceRootRow: View {
    var root: WorkspaceRootDraft
    var setPrimary: () -> Void
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(root.displayName.isEmpty ? URL(fileURLWithPath: root.path).lastPathComponent : root.displayName)
                        .font(.subheadline.weight(.medium))
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
                    .font(.caption)
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

private struct SettingsLabelsSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "关于标签") {
                Text("标签帮助你用彩色标记整理会话。布尔标签用于筛选，带值标签可表达优先级、截止日期或项目引用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsGroup(title: "标签层级") {
                if viewModel.governanceConfig.labels.isEmpty {
                    Text("尚未配置标签。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.governanceConfig.labels) { label in
                        HStack {
                            Circle().fill(color(named: label.colorName)).frame(width: 7, height: 7)
                            Text(label.name).frame(width: 180, alignment: .leading)
                            Text(label.valueType.rawValue).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .font(.subheadline)
                        .padding(.vertical, 7)
                        if label.id != viewModel.governanceConfig.labels.last?.id { Divider() }
                    }
                }
            }
            SettingsGroup(title: "自动应用规则") {
                Text("自动应用规则将在后续版本接入。当前标签定义来自会话治理配置。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(named name: String) -> Color {
        switch name {
        case "orange": .orange
        case "purple": .purple
        case "teal": .teal
        case "red": .red
        case "yellow": .yellow
        case "green": .green
        default: .blue
        }
    }
}

private struct SettingsShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "通用") {
                ShortcutRow(title: "新建聊天", keys: ["⌘", "N"])
                ShortcutRow(title: "设置", keys: ["⌘", ","])
                ShortcutRow(title: "搜索", keys: ["⌘", "F"])
                ShortcutRow(title: "命令面板", keys: ["⌘", "/"])
            }
            SettingsGroup(title: "导航") {
                ShortcutRow(title: "聚焦侧栏", keys: ["⌘", "1"])
                ShortcutRow(title: "聚焦会话列表", keys: ["⌘", "2"])
                ShortcutRow(title: "聚焦聊天", keys: ["⌘", "3"])
                ShortcutRow(title: "聚焦下一块区域", keys: ["Tab"])
            }
        }
    }
}

private struct SettingsPreferencesSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "基本信息") {
                SettingsTextFieldRow(title: "名称", subtitle: "康纳同学如何称呼你。", text: $viewModel.userDisplayName)
                Divider()
                SettingsTextFieldRow(title: "时区", subtitle: "用于相对日期和日程上下文。", text: $viewModel.userTimezone)
            }
            SettingsGroup(title: "位置") {
                SettingsTextFieldRow(title: "城市", subtitle: "用于本地信息和上下文。", text: $viewModel.userCity)
                Divider()
                SettingsTextFieldRow(title: "国家", subtitle: "用于区域格式和上下文。", text: $viewModel.userCountry)
            }
            SettingsGroup(title: "备注") {
                TextEditor(text: $viewModel.userPreferenceNotes)
                    .font(.subheadline)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(spacing: 0) {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsTextFieldRow: View {
    var title: String
    var subtitle: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    var title: String
    var subtitle: String
    @Binding var selection: Selection
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
        }
        .frame(minHeight: 46)
    }
}

private struct SettingsSaveBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack {
            Spacer()
            Button("重新加载") { viewModel.loadRuntimeSettings() }
            Button("保存设置") { viewModel.saveRuntimeSettings() }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
    }
}

private struct ShortcutRow: View {
    var title: String
    var keys: [String]

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
        .frame(minHeight: 38)
    }
}
