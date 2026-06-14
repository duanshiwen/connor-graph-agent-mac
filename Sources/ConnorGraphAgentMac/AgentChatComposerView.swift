import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct AgentSendControlButton: View {
    var isSubmitting: Bool
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSubmitting ? "stop.fill" : "arrow.up")
                .font(.system(size: AgentChatTypography.sendIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: AgentChatLayout.primaryButtonSize, height: AgentChatLayout.primaryButtonSize)
                .background(buttonBackground, in: Circle())
                .overlay(Circle().stroke(buttonBorder, lineWidth: 1))
                .shadow(color: buttonShadow, radius: 7, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSubmitting ? ConnorCraftPalette.foreground : ConnorCraftPalette.sendButtonForeground)
        .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
        .contentShape(Circle())
        .opacity(isDisabled ? 0.42 : 1)
        .disabled(isDisabled)
    }

    private var buttonBackground: Color {
        isSubmitting ? ConnorCraftPalette.stopButton : ConnorCraftPalette.sendButton
    }

    private var buttonBorder: Color {
        isSubmitting ? ConnorCraftPalette.foreground.opacity(0.10) : ConnorCraftPalette.foreground.opacity(0.08)
    }

    private var buttonShadow: Color {
        isDisabled || isSubmitting ? Color.clear : ConnorCraftPalette.foreground.opacity(0.12)
    }
}

struct AgentChatComposerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isSessionInfoPresented: Bool
    @State private var isWorkspacePopoverPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false

    private let workspaceMenuItemMaxWidth: CGFloat = 320
    private let supportedAttachmentContentTypes: [UTType] = [
        .plainText,
        .text,
        .json,
        .commaSeparatedText,
        .xml,
        UTType(filenameExtension: "md") ?? .text,
        UTType(filenameExtension: "markdown") ?? .text,
        UTType(filenameExtension: "log") ?? .text,
        UTType(filenameExtension: "yaml") ?? .text,
        UTType(filenameExtension: "yml") ?? .text,
        UTType(filenameExtension: "swift") ?? .sourceCode,
        UTType(filenameExtension: "py") ?? .sourceCode,
        UTType(filenameExtension: "js") ?? .sourceCode,
        UTType(filenameExtension: "ts") ?? .sourceCode,
        UTType(filenameExtension: "tsx") ?? .sourceCode,
        UTType(filenameExtension: "jsx") ?? .sourceCode,
        UTType(filenameExtension: "rs") ?? .sourceCode,
        UTType(filenameExtension: "go") ?? .sourceCode,
        UTType(filenameExtension: "java") ?? .sourceCode,
        UTType(filenameExtension: "kt") ?? .sourceCode,
        UTType(filenameExtension: "c") ?? .sourceCode,
        UTType(filenameExtension: "cpp") ?? .sourceCode,
        UTType(filenameExtension: "h") ?? .sourceCode,
        UTType(filenameExtension: "hpp") ?? .sourceCode,
        UTType(filenameExtension: "cs") ?? .sourceCode,
        UTType(filenameExtension: "rb") ?? .sourceCode,
        UTType(filenameExtension: "php") ?? .sourceCode,
        UTType(filenameExtension: "sh") ?? .shellScript,
        UTType(filenameExtension: "zsh") ?? .shellScript,
        UTType(filenameExtension: "bash") ?? .shellScript,
        UTType(filenameExtension: "sql") ?? .text,
        UTType(filenameExtension: "css") ?? .text,
        UTType(filenameExtension: "scss") ?? .text
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            optionBadgeRow

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !viewModel.pendingAttachmentRefs.isEmpty {
                        AgentAttachmentShelfView(attachments: viewModel.pendingAttachmentRefs) { id in
                            viewModel.removePendingAttachment(id: id)
                        }
                        .frame(height: 42, alignment: .topLeading)
                    }

                    SafeChatComposerTextView(
                        text: $viewModel.chatInput,
                        placeholder: "按 Shift + Return 换行",
                        isSpellCheckEnabled: viewModel.spellCheckEnabled,
                        onSubmit: { Task { await viewModel.submitChat() } }
                    )
                    .padding(.horizontal, AgentChatLayout.spaceL)
                    .padding(.top, viewModel.pendingAttachmentRefs.isEmpty ? AgentChatLayout.spaceM : AgentChatLayout.spaceXS)
                    .padding(.bottom, AgentChatLayout.spaceM)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.clear)
                }
                .frame(minHeight: AgentChatLayout.composerTextMinHeight, maxHeight: AgentChatLayout.composerTextMaxHeight, alignment: .topLeading)

                HStack(spacing: AgentChatLayout.spaceS) {
                    Button(action: { isFileImporterPresented = true }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .contentShape(Rectangle())
                    .help("添加附件")

                    workingDirectoryMenu

                    Button(action: { viewModel.toggleBrowserWorkspaceVisibility() }) {
                        AgentComposerOptionBadge(
                            title: viewModel.isBrowserVisible ? "隐藏浏览器" : "浏览器",
                            systemImage: "safari",
                            tint: viewModel.isBrowserVisible ? .accentColor : .secondary,
                            showsChevron: false,
                            isActive: viewModel.isBrowserVisible,
                            style: .compact
                        )
                    }
                    .buttonStyle(.plain)

                    if let inspection = viewModel.lastPromptInspection {
                        Label("约 \(inspection.estimatedPromptTokenCount) tokens", systemImage: "text.alignleft")
                            .font(AgentChatTypography.micro)
                            .foregroundStyle(promptBudgetStatusColor(inspection.promptBudgetStatus))
                    }

                    Spacer(minLength: AgentChatLayout.spaceS)

                    modelSelectionMenu

                    AgentSendControlButton(
                        isSubmitting: viewModel.isSubmittingChat,
                        isDisabled: !viewModel.isSubmittingChat && !viewModel.canSubmitCurrentChat,
                        action: {
                            if viewModel.isSubmittingChat {
                                viewModel.cancelActiveChatRun()
                            } else {
                                Task { await viewModel.submitChat() }
                            }
                        }
                    )
                }
                .padding(.horizontal, AgentChatLayout.spaceM)
                .padding(.vertical, AgentChatLayout.spaceS)
                .frame(minHeight: AgentChatLayout.hitTargetSize)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.58), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .overlay {
                if let approval = viewModel.activeChatPendingApprovals.first {
                    ZStack {
                        RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))

                        AgentChatPermissionRequestCard(approval: approval, viewModel: viewModel)
                            .padding(AgentChatLayout.spaceM)
                            .frame(maxHeight: 220)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .padding(0)
        .background(Color.clear)
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: supportedAttachmentContentTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await viewModel.importAttachments(urls: urls) }
            case .failure(let error):
                viewModel.errorMessage = "附件选择失败：\(error)"
            }
        }
    }

    private var selectedSession: AgentSession? {
        viewModel.chatSessions.first { $0.id == viewModel.selectedChatSessionID }
    }

    private var workingDirectoryMenu: some View {
        Button {
            isWorkspacePopoverPresented.toggle()
        } label: {
            AgentComposerOptionBadge(
                title: workingDirectoryBadgeTitle,
                systemImage: viewModel.primaryWorkspaceRootDraft == nil ? "folder" : "folder.fill",
                tint: .secondary,
                isActive: false,
                style: .compact,
                showsBorder: false
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isWorkspacePopoverPresented, arrowEdge: .bottom) {
            workingDirectoryPopoverContent
                .padding(10)
                .frame(width: 390)
        }
        .help(workingDirectoryHelpText)
    }

    private var workingDirectoryPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.workspaceRoots.isEmpty {
                Text("尚未设置工作目录")
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.workspaceRoots) { root in
                        workspaceRootPopoverRow(root)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Label("历史打开列表", systemImage: "clock.arrow.circlepath")
                    .font(AgentChatTypography.micro.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)

                if viewModel.recentWorkspacePaths.isEmpty {
                    Text("暂无历史记录")
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                } else {
                    ForEach(viewModel.recentWorkspacePaths, id: \.self) { path in
                        Button {
                            viewModel.addWorkspaceRootAndSetPrimary(path: path)
                            isWorkspacePopoverPresented = false
                        } label: {
                            workspaceMenuItemLabel(title: workspaceMenuItemTitle(forPath: path), systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .help(path)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    isWorkspacePopoverPresented = false
                    chooseWorkingDirectory()
                } label: {
                    Label("选择文件夹…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)

                Button {
                    viewModel.resetWorkspaceRootsForCurrentSession()
                    isWorkspacePopoverPresented = false
                } label: {
                    Label("重置为默认", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.workspaceRoots.isEmpty && viewModel.defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    viewModel.clearRecentWorkspacePaths()
                } label: {
                    Label("清空历史", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.recentWorkspacePaths.isEmpty)
            }
            .font(AgentChatTypography.micro)
            .padding(.horizontal, 4)
        }
    }

    private func workspaceRootPopoverRow(_ root: WorkspaceRootDraft) -> some View {
        HStack(spacing: 6) {
            Button {
                viewModel.setPrimaryWorkspaceRoot(id: root.id)
                isWorkspacePopoverPresented = false
            } label: {
                workspaceMenuItemLabel(title: workspaceMenuItemTitle(for: root), systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(root.path)

            Button {
                viewModel.removeWorkspaceRoot(id: root.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("取消此工作目录")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var workingDirectoryBadgeTitle: String {
        guard let root = viewModel.primaryWorkspaceRootDraft else { return "选择工作目录" }
        return workspaceDisplayName(for: root)
    }

    private var workingDirectoryHelpText: String {
        guard let root = viewModel.primaryWorkspaceRootDraft else {
            return "设置当前会话工作目录；本地工具和 Claude Sidecar 将从主目录开始。"
        }
        return "当前会话工作目录：\(root.path)"
    }

    private func workspaceMenuItemTitle(for root: WorkspaceRootDraft) -> String {
        workspaceMenuItemTitle(name: workspaceDisplayName(for: root), path: root.path)
    }

    private func workspaceMenuItemTitle(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
        return workspaceMenuItemTitle(name: name, path: path)
    }

    private func workspaceMenuItemTitle(name: String, path: String) -> String {
        let parent = workspaceParentDisplayPath(for: path)
        guard !parent.isEmpty else { return name }
        return "\(name)  in \(parent)"
    }

    private func workspaceMenuItemLabel(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: workspaceMenuItemMaxWidth, alignment: .leading)
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private func workspaceDisplayName(for root: WorkspaceRootDraft) -> String {
        let trimmedName = root.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        let url = URL(fileURLWithPath: root.path, isDirectory: true)
        return url.lastPathComponent.isEmpty ? root.path : url.lastPathComponent
    }

    private func workspaceParentDisplayPath(for path: String) -> String {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择当前会话工作目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.urls.first {
            viewModel.addWorkspaceRootAndSetPrimary(path: url.path)
        }
    }

    private func menuOptionTitle(_ title: String, isSelected: Bool) -> String {
        "\(isSelected ? "✓" : "  ")  \(title)"
    }

    private var optionBadgeRow: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            permissionModeMenu

            if let session = selectedSession {
                sessionStatusMenu(session)
            }

            Spacer(minLength: AgentChatLayout.spaceS)

            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    isSessionInfoPresented.toggle()
                }
            } label: {
                AgentComposerOptionBadge(
                    title: "信息",
                    systemImage: "info.circle",
                    tint: .secondary,
                    showsChevron: false,
                    isActive: isSessionInfoPresented,
                    style: .compact
                )
            }
            .buttonStyle(.plain)
            .help("会话信息")
        }
        .padding(.horizontal, 1)
        .padding(.bottom, 2)
    }

    private var permissionModeMenu: some View {
        Menu {
            ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                Button {
                    viewModel.setSidecarPermissionMode(mode)
                } label: {
                    Text(menuOptionTitle(mode.displayName, isSelected: mode == viewModel.sidecarPermissionMode))
                }
            }
        } label: {
            AgentComposerOptionBadge(
                title: viewModel.sidecarPermissionMode.displayName,
                systemImage: permissionModeIcon(viewModel.sidecarPermissionMode),
                tint: permissionModeColor(viewModel.sidecarPermissionMode),
                isActive: true,
                style: .prominent
            )
        }
        .menuStyle(.borderlessButton)
        .help("调整本轮会话权限")
    }

    private func sessionStatusMenu(_ session: AgentSession) -> some View {
        Menu {
            ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                Button {
                    viewModel.deferViewUpdate {
                        viewModel.setSelectedSessionStatus(status)
                    }
                } label: {
                    Text(menuOptionTitle(status.displayName, isSelected: status == session.governance.status))
                }
            }
        } label: {
            AgentComposerOptionBadge(
                title: session.governance.status.displayName,
                systemImage: sessionStatusIcon(session.governance.status),
                tint: sessionStatusColor(session.governance.status),
                isActive: false,
                style: .prominent
            )
        }
        .menuStyle(.borderlessButton)
        .help("更改会话状态")
    }

    private var modelSelectionMenu: some View {
        Menu {
            if viewModel.isLoadingLLMModelConnections {
                Label("正在加载模型列表…", systemImage: "arrow.triangle.2.circlepath")
            }

            if viewModel.llmModelConnections.isEmpty {
                Button(viewModel.llmSelectedModel.isEmpty ? "未选择模型" : viewModel.llmSelectedModel) {}
                    .disabled(true)
            } else {
                ForEach(viewModel.llmModelConnections) { connection in
                    Menu {
                        if connection.models.isEmpty {
                            Button("没有可用模型") {}
                                .disabled(true)
                        } else {
                            ForEach(connection.models) { model in
                                Button {
                                    viewModel.selectLLMModel(model.id, providerMode: connection.providerMode)
                                } label: {
                                    if model.id == viewModel.llmSelectedModel && connection.providerMode == viewModel.llmProviderMode {
                                        Label(model.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(model.displayName)
                                    }
                                }
                                .help(model.id)
                            }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                                Text(connection.title)
                                Text(connection.subtitle)
                                    .font(AgentChatTypography.micro)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: connection.isLiveCatalog ? "network" : "bolt.horizontal.circle")
                        }
                    }
                }

                if viewModel.sessionHasLLMOverride {
                    Divider()
                    Button {
                        viewModel.clearSessionLLMOverride()
                    } label: {
                        Label("恢复全局默认模型", systemImage: "arrow.counterclockwise")
                    }
                }

                Divider()

                Button {
                    Task { await viewModel.reloadLLMModelConnections() }
                } label: {
                    Label("刷新模型列表", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            HStack(spacing: AgentChatLayout.spaceXS) {
                Label {
                    Text(viewModel.llmSelectedModel.isEmpty ? "未选择模型" : viewModel.llmSelectedModel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "cpu")
                }
                if viewModel.sessionHasLLMOverride {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .help("此会话使用自定义模型，与全局设置不同")
                }
            }
            .font(AgentChatTypography.micro.weight(.medium))
            .padding(.horizontal, AgentChatLayout.spaceM)
            .frame(height: AgentChatLayout.chipHeight)
            .frame(maxWidth: AgentChatLayout.modelMenuMaxWidth)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.regular)
        .help("选择真实配置的连接和模型；切换后下一轮请求立即使用该模型")
    }

    private func promptBudgetStatusColor(_ status: AgentPromptBudgetStatus) -> Color {
        switch status {
        case .safe: return .secondary
        case .warning: return .orange
        case .over: return .red
        }
    }

    private func permissionModeIcon(_ mode: AgentPermissionMode) -> String {
        switch mode {
        case .readOnly: "eye"
        case .askToWrite: "exclamationmark.circle"
        case .trustedWrite: "pencil.and.outline"
        case .allowAll: "bolt.circle"
        }
    }

    private func permissionModeColor(_ mode: AgentPermissionMode) -> Color {
        switch mode {
        case .readOnly: .secondary
        case .askToWrite: .orange
        case .trustedWrite: .accentColor
        case .allowAll: .purple
        }
    }

    private func sessionStatusIcon(_ status: AgentSessionStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle"
        case .blocked: "nosign"
        case .archived: "archivebox"
        }
    }

    private func sessionStatusColor(_ status: AgentSessionStatus) -> Color {
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

struct AgentComposerOptionBadge: View {
    enum Style {
        case compact
        case prominent

        var iconSize: CGFloat {
            switch self {
            case .compact: AgentChatTypography.controlIconSize
            case .prominent: AgentChatTypography.controlIconSize + 1
            }
        }

        var textFont: Font {
            switch self {
            case .compact: AgentChatTypography.meta.weight(.medium)
            case .prominent: AgentChatTypography.metaEmphasis
            }
        }

        var chevronSize: CGFloat {
            AgentChatTypography.smallIconSize
        }
    }

    var title: String
    var systemImage: String
    var tint: Color
    var showsChevron: Bool = true
    var isActive: Bool = false
    var style: Style = .compact
    var showsBorder: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: style.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(style.textFont)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: style.chevronSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .opacity(0.72)
            }
        }
        .padding(.horizontal, AgentChatLayout.spaceS)
        .frame(height: AgentChatLayout.chipHeight)
        .foregroundStyle(tint)
        .background(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                .fill(Color.clear)
        )
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                    .stroke(Color.secondary.opacity(isActive ? 0.28 : 0.18), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        .frame(minHeight: AgentChatLayout.hitTargetSize)
        .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
    }
}

struct SafeChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSpellCheckEnabled: Bool
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SubmitAwareTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.placeholderString = placeholder
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.enabledTextCheckingTypes = isSpellCheckEnabled ? NSTextCheckingResult.CheckingType.spelling.rawValue : 0
        textView.font = AgentChatTypography.composerNSFont
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitAwareTextView else { return }
        textView.onSubmit = onSubmit
        textView.placeholderString = placeholder
        textView.font = AgentChatTypography.composerNSFont
        if textView.string != text {
            textView.string = text
        }
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.enabledTextCheckingTypes = isSpellCheckEnabled ? NSTextCheckingResult.CheckingType.spelling.rawValue : 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func insertNewline(_ sender: Any?) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) || flags.contains(.option) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? AgentChatTypography.composerNSFont,
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholderString.draw(
            at: NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height),
            withAttributes: attributes
        )
    }
}
