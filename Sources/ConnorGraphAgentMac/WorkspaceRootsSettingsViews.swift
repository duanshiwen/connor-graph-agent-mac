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
                        .lineLimit(1)
                        .truncationMode(.middle)
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
    let clearAllMemoryAndSessions: () async throws -> Void
    @State private var showsPersonalityResetConfirmation = false
    @State private var showsMemoryClearConfirmation = false
    @State private var memoryClearConfirmationText = ""
    @State private var isClearingMemory = false
    @State private var memoryClearErrorMessage: String?
    @State private var memoryClearStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "偏好",
                subtitle: "管理康纳同学用于称呼、语言、时区和个性化上下文的用户信息。",
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
            SettingsGroup(title: "环境感知") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("定位权限")
                            .font(SettingsListTypography.rowTitleSelected)
                        Text(model.environmentLocationStatusMessage)
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开系统设置") { model.openLocationPrivacySettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
                Divider()
                SettingsValueRow(title: "天气服务", value: "Open-Meteo · 15 分钟缓存")
                Divider()
                SettingsValueRow(title: "位置存储", value: "不保存位置轨迹")
            }
            SettingsGroup(title: "康纳同学的性格") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("姓名")
                                .font(SettingsListTypography.rowTitleSelected)
                            Text("姓名是固定身份，不会被性格描述或 AI 分析结果更改。")
                                .font(SettingsListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(ConnorPersonalitySettings.lockedDisplayName, systemImage: "lock.fill")
                            .font(SettingsListTypography.rowTitleSelected)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("描述你希望的性格")
                            .font(SettingsListTypography.rowTitleSelected)
                        TextEditor(text: $model.personalityRequest)
                            .font(SettingsListTypography.rowTitle)
                            .frame(minHeight: 110)
                            .appFormTextEditor()
                            .disabled(model.isGeneratingPersonality)
                        HStack {
                            if model.isGeneratingPersonality {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在分析并补充…")
                                    .font(SettingsListTypography.rowCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await model.generatePersonalityDraft() }
                            } label: {
                                Label(model.personalityDraft == nil ? "AI 分析" : "重新生成", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isGeneratingPersonality || model.personalityRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if let error = model.personalityErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.red)
                    }

                    if let draft = model.personalityDraft {
                        Divider()
                        ConnorPersonalityPreview(
                            title: "待应用的 AI 分析结果",
                            personality: draft
                        )
                        HStack {
                            Spacer()
                            Button("取消") { model.cancelPersonalityDraft() }
                                .buttonStyle(.bordered)
                            Button {
                                model.confirmPersonalityDraft()
                            } label: {
                                Label("应用性格", systemImage: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if !model.connorPersonality.isEmpty {
                        Divider()
                        ConnorPersonalityPreview(
                            title: "当前已生效",
                            personality: model.connorPersonality
                        )
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                showsPersonalityResetConfirmation = true
                            } label: {
                                Label("恢复默认性格", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .confirmationDialog(
                    "恢复默认性格？",
                    isPresented: $showsPersonalityResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("恢复默认性格", role: .destructive) { model.resetPersonality() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("已保存的自定义性格会被清除，康纳同学将恢复默认对话风格。")
                }
            }
            SettingsGroup(title: "备注") {
                TextEditor(text: $model.notes)
                    .font(SettingsListTypography.rowTitle)
                    .frame(minHeight: 150)
                    .appFormTextEditor()
            }
            SettingsGroup(title: "危险操作") {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("清除全部记忆和会话")
                            .font(SettingsListTypography.rowTitleSelected)
                            .foregroundStyle(.red)
                        Text("永久删除全部会话，以及 Memory OS 的 L0、L1、L2、L3、L4 记忆、处理队列和搜索索引。此操作不可撤销。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Button(role: .destructive) {
                        memoryClearConfirmationText = ""
                        memoryClearErrorMessage = nil
                        showsMemoryClearConfirmation = true
                    } label: {
                        Label("清除记忆", systemImage: "trash.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isClearingMemory)
                }
                .padding(.vertical, 4)

                if let memoryClearStatusMessage {
                    Divider()
                    Label(memoryClearStatusMessage, systemImage: "checkmark.circle.fill")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.green)
                }
            }
        }
        .onAppear { model.refreshEnvironmentPermissionStatus() }
        .sheet(isPresented: $showsMemoryClearConfirmation) {
            ClearMemoryConfirmationSheet(
                confirmationText: $memoryClearConfirmationText,
                isClearing: isClearingMemory,
                errorMessage: memoryClearErrorMessage,
                onCancel: {
                    guard !isClearingMemory else { return }
                    showsMemoryClearConfirmation = false
                },
                onConfirm: clearMemoryAfterConfirmation
            )
        }
    }

    private func clearMemoryAfterConfirmation() {
        guard MemoryClearConfirmationPolicy.accepts(memoryClearConfirmationText), !isClearingMemory else { return }
        isClearingMemory = true
        memoryClearErrorMessage = nil
        Task { @MainActor in
            do {
                try await clearAllMemoryAndSessions()
                isClearingMemory = false
                showsMemoryClearConfirmation = false
                memoryClearConfirmationText = ""
                memoryClearStatusMessage = "全部记忆和会话已清除。"
            } catch {
                isClearingMemory = false
                memoryClearErrorMessage = "清除失败：\(error.localizedDescription)"
            }
        }
    }
}

enum MemoryClearConfirmationPolicy {
    static let requiredText = "清除全部记忆"

    static func accepts(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines) == requiredText
    }
}

private struct ClearMemoryConfirmationSheet: View {
    @Binding var confirmationText: String
    let isClearing: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @FocusState private var isConfirmationFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text("永久清除全部记忆和会话？")
                        .font(AppTypography.sectionTitle)
                    Text("将删除所有会话，以及 L0、L1、L2、L3、L4 的全部记忆和索引。删除后无法恢复。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("请输入“\(MemoryClearConfirmationPolicy.requiredText)”以继续")
                    .font(SettingsListTypography.rowTitleSelected)
                TextField(MemoryClearConfirmationPolicy.requiredText, text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isConfirmationFieldFocused)
                    .disabled(isClearing)
                    .onSubmit {
                        if MemoryClearConfirmationPolicy.accepts(confirmationText) {
                            onConfirm()
                        }
                    }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消", action: onCancel)
                    .disabled(isClearing)
                Button(role: .destructive, action: onConfirm) {
                    if isClearing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在清除…")
                        }
                    } else {
                        Label("永久清除", systemImage: "trash.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!MemoryClearConfirmationPolicy.accepts(confirmationText) || isClearing)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(isClearing)
        .onAppear { isConfirmationFieldFocused = true }
    }
}

private struct ConnorPersonalityPreview: View {
    let title: String
    let personality: ConnorPersonalitySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SettingsListTypography.rowTitleSelected)
            personalityRow("性别", personality.gender)
            personalityRow("总体人格", personality.summary)
            personalityRow("核心特征", personality.traits.joined(separator: "、"))
            personalityRow("沟通方式", personality.communicationStyle)
            personalityRow("思考方式", personality.reasoningStyle)
            personalityRow("主动性", personality.initiativeStyle)
            personalityRow("情绪基调", personality.emotionalTone)
            personalityRow("行为边界", personality.boundaries.joined(separator: "；"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func personalityRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Text(value)
                    .font(SettingsListTypography.rowTitle)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
                .controlSize(AppButtonLayout.controlSize)
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
