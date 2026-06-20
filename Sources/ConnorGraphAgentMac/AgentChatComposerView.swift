import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct AgentChatComposerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isSessionInfoPresented: Bool
    @State private var localChatInput: String = ""
    @State private var isWorkspacePopoverPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var isSkillPickerPresented: Bool = false
    @State private var slashSkillPickerAnchorRect: CGRect?
    @State private var slashSkillPickerTriggerRange: NSRange?
    @State private var composerSelectionTracker = ComposerTextSelectionTracker()
    @State private var skillPickerSelectionIndex: Int = 0
    @State private var speechKeyboardMonitor: SpeechInputKeyboardMonitor?

    private let workspaceMenuItemMaxWidth: CGFloat = 320
    private let supportedAttachmentContentTypes: [UTType] = [
        .plainText,
        .text,
        .json,
        .commaSeparatedText,
        .xml,
        .image,
        .pdf,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "rtf") ?? .rtf,
        UTType(filenameExtension: "xls") ?? .data,
        UTType(filenameExtension: "xlsx") ?? .data,
        UTType(filenameExtension: "ppt") ?? .data,
        UTType(filenameExtension: "pptx") ?? .data,
        UTType(filenameExtension: "jsonl") ?? .json,
        UTType(filenameExtension: "tsv") ?? .commaSeparatedText,
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
                    if !composerState.pendingAttachments.isEmpty {
                        AgentAttachmentShelfView(
                            attachments: composerState.pendingAttachments,
                            onPreview: { attachment in sendComposerAction(.previewAttachment(attachment)) },
                            onRemove: { id in sendComposerAction(.removeAttachment(id)) }
                        )
                        .frame(height: 42, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                        if composerState.activeSkillSlug != nil {
                            activeSkillInlineChip
                        }

                        composerTextEditor

                        SpeechInputProvisionalTranscriptView(transcript: composerState.speechProvisionalTranscript)
                    }
                    .padding(.horizontal, AgentChatLayout.spaceL)
                    .padding(.top, composerState.pendingAttachments.isEmpty ? AgentChatLayout.spaceM : AgentChatLayout.spaceXS)
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
                    .foregroundStyle(composerControlForeground)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .contentShape(Rectangle())
                    .help("添加附件")
                    .accessibilityLabel("添加附件")

                    workingDirectoryMenu

                    Button(action: { sendComposerAction(.toggleBrowserWorkspaceVisibility) }) {
                        AgentComposerOptionBadge(
                            title: viewModel.isBrowserVisible ? "隐藏浏览器" : "浏览器",
                            systemImage: "safari",
                            tint: viewModel.isBrowserVisible ? composerControlActiveForeground : composerControlForeground,
                            showsChevron: false,
                            isActive: viewModel.isBrowserVisible,
                            style: .compact
                        )
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isBrowserVisible ? "隐藏浏览器工作区" : "显示浏览器工作区")
                    .accessibilityLabel(viewModel.isBrowserVisible ? "隐藏浏览器工作区" : "显示浏览器工作区")

                    if let inspection = viewModel.lastPromptInspection {
                        Label("约 \(inspection.estimatedPromptTokenCount) tokens", systemImage: "text.alignleft")
                            .font(AgentChatTypography.micro)
                            .foregroundStyle(promptBudgetStatusColor(inspection.promptBudgetStatus))
                    }

                    Spacer(minLength: AgentChatLayout.spaceS)

                    modelSelectionMenu

                    AgentSendControlButton(
                        isSubmitting: composerState.isSubmitting,
                        isDisabled: !composerState.isSubmitting && !composerState.canSubmit,
                        action: {
                            if composerState.isSubmitting {
                                sendComposerAction(.cancelActiveRun)
                            } else {
                                submitLocalChatInput()
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
        .onAppear {
            localChatInput = viewModel.chatInput
            installSpeechKeyboardMonitorIfNeeded()
        }
        .onDisappear {
            speechKeyboardMonitor?.stop()
            speechKeyboardMonitor = nil
        }
        .onChange(of: viewModel.selectedChatSessionID) { _, _ in
            localChatInput = viewModel.chatInput
        }
        .onChange(of: viewModel.chatInput) { _, newValue in
            guard newValue != localChatInput else { return }
            localChatInput = newValue
        }
        .onChange(of: viewModel.sessionSpeechTranscriptionEnabled) { _, isEnabled in
            if isEnabled {
                installSpeechKeyboardMonitorIfNeeded()
            } else {
                speechKeyboardMonitor?.stop()
                speechKeyboardMonitor = nil
            }
        }
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadSkillRuntimeDefinitions()
            }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: supportedAttachmentContentTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await viewModel.importAttachments(urls: urls) }
            case .failure(let error):
                viewModel.showAttachmentToast(title: "附件选择失败", message: String(describing: error), systemImage: "xmark.circle")
            }
        }
    }

    private var selectedSession: AgentSession? {
        viewModel.chatSessions.first { $0.id == viewModel.selectedChatSessionID }
    }

    private var composerStore: AgentComposerStore {
        AgentComposerStore(viewModel: viewModel)
    }

    private var composerState: AgentComposerState {
        composerStore.state(input: localChatInput, canSubmit: canSubmitLocalChat, selectedSession: selectedSession)
    }

    private func sendComposerAction(_ action: AgentComposerAction) {
        composerStore.send(action)
    }

    private func installSpeechKeyboardMonitorIfNeeded() {
        guard viewModel.sessionSpeechTranscriptionEnabled else { return }
        guard speechKeyboardMonitor == nil else { return }
        let monitor = SpeechInputKeyboardMonitor(
            spaceHoldEnabled: false,
            onBegin: { sendComposerAction(.beginSpeechTranscription(composerSelectionTracker.selectedRange)) },
            onEnd: { sendComposerAction(.finishSpeechTranscription) }
        )
        monitor.start()
        speechKeyboardMonitor = monitor
    }

    private var localChatInputBinding: Binding<String> {
        Binding(
            get: { localChatInput },
            set: { newValue in
                localChatInput = newValue
                sendComposerAction(.inputChanged(newValue))
            }
        )
    }

    private var composerTextEditor: some View {
        ZStack(alignment: .topLeading) {
            SafeChatComposerTextView(
                text: localChatInputBinding,
                selectionTracker: composerSelectionTracker,
                placeholder: composerPlaceholder,
                isSpellCheckEnabled: viewModel.spellCheckEnabled,
                sendShortcut: viewModel.composerSendShortcut,
                isSkillPickerPresented: isSkillPickerPresented,
                onSubmit: submitLocalChatInput,
                onImportFiles: importComposerFiles,
                onSlashCommand: handleSlashCommand,
                onSkillPickerKeyCommand: handleSkillPickerKeyCommand,
                onAttachmentImportError: handleAttachmentImportError
            )

            slashSkillPickerAnchor
        }
    }

    private var composerPlaceholder: String {
        viewModel.composerSendShortcut == "cmd-return" ? "按 ⌘ + Return 发送" : "按 Shift + Return 换行"
    }

    @ViewBuilder
    private var slashSkillPickerAnchor: some View {
        if let slashSkillPickerAnchorRect {
            Color.clear
                .frame(width: 1, height: max(18, slashSkillPickerAnchorRect.height))
                .offset(x: max(0, slashSkillPickerAnchorRect.minX), y: max(0, slashSkillPickerAnchorRect.maxY))
                .popover(
                    isPresented: Binding(
                        get: { isSkillPickerPresented && self.slashSkillPickerAnchorRect != nil },
                        set: { isPresented in
                            isSkillPickerPresented = isPresented
                            if !isPresented {
                                self.slashSkillPickerAnchorRect = nil
                                self.slashSkillPickerTriggerRange = nil
                            }
                        }
                    ),
                    arrowEdge: .top
                ) {
                    skillPickerPopoverContent
                        .padding(10)
                        .frame(width: 320)
                }
        }
    }

    private func importComposerFiles(_ urls: [URL]) {
        sendComposerAction(.importFiles(urls))
    }

    private func handleAttachmentImportError(_ message: String) {
        sendComposerAction(.showAttachmentImportError(message))
    }

    private func handleSlashCommand(_ rect: CGRect, triggerRange: NSRange) {
        slashSkillPickerAnchorRect = rect
        slashSkillPickerTriggerRange = triggerRange
        skillPickerSelectionIndex = preferredSkillPickerSelectionIndex()
        isSkillPickerPresented = true
    }

    private var canSubmitLocalChat: Bool {
        !localChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.pendingAttachmentRefs.isEmpty
    }

    private func removeSlashSkillPickerTriggerIfNeeded() {
        guard let triggerRange = slashSkillPickerTriggerRange,
              let range = Range(triggerRange, in: localChatInput),
              localChatInput[range] == "/"
        else { return }
        localChatInput.removeSubrange(range)
        viewModel.updateSelectedChatInputDraft(localChatInput)
    }

    private func preferredSkillPickerSelectionIndex() -> Int {
        let cards = viewModel.commercialSkillManagerPresentation.cards
        guard !cards.isEmpty else { return 0 }
        if let activeSkillSlug = composerState.activeSkillSlug,
           let activeIndex = cards.firstIndex(where: { $0.id == activeSkillSlug }) {
            return activeIndex
        }
        return 0
    }

    private func handleSkillPickerKeyCommand(_ command: SkillPickerKeyCommand) {
        let cards = viewModel.commercialSkillManagerPresentation.cards
        switch command {
        case .moveUp:
            guard !cards.isEmpty else { return }
            skillPickerSelectionIndex = (skillPickerSelectionIndex - 1 + cards.count) % cards.count
        case .moveDown:
            guard !cards.isEmpty else { return }
            skillPickerSelectionIndex = (skillPickerSelectionIndex + 1) % cards.count
        case .confirm:
            guard cards.indices.contains(skillPickerSelectionIndex) else { return }
            selectSkill(cards[skillPickerSelectionIndex])
        case .cancel:
            closeSkillPicker()
        }
    }

    private func selectSkill(_ card: SkillManagerCard) {
        sendComposerAction(.selectSkill(card.id))
        removeSlashSkillPickerTriggerIfNeeded()
        closeSkillPicker()
    }

    private func closeSkillPicker() {
        isSkillPickerPresented = false
        slashSkillPickerAnchorRect = nil
        slashSkillPickerTriggerRange = nil
    }

    private func submitLocalChatInput() {
        let prompt = localChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = localChatInput
        let submittedText = localChatInput
        localChatInput = ""
        viewModel.updateSelectedChatInputDraft("")
        Task {
            let runID = await viewModel.submitChat(prompt: prompt, clearComposer: true, displayPrompt: displayPrompt)
            if runID == nil, localChatInput.isEmpty {
                localChatInput = submittedText
                viewModel.updateSelectedChatInputDraft(submittedText)
            }
        }
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
            return "设置当前会话工作目录；本地工具将从主目录开始。"
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
        AgentComposerOptionBar(
            selectedSession: selectedSession,
            composerState: composerState,
            governanceConfig: viewModel.governanceConfig,
            hasRunningBackgroundTask: viewModel.hasRunningActiveSessionBackgroundTask,
            currentTextSelectionRange: { composerSelectionTracker.selectedRange },
            isSessionInfoPresented: $isSessionInfoPresented,
            onAction: sendComposerAction
        )
    }

    private var modelSelectionMenu: some View {
        Menu {
            if viewModel.isLoadingLLMModelConnections {
                Label("正在加载模型列表…", systemImage: "arrow.triangle.2.circlepath")
            }

            if viewModel.llmModelConnections.isEmpty {
                Button(composerState.selectedModel.isEmpty ? "未选择模型" : composerState.selectedModel) {}
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
                                    viewModel.selectLLMModel(model.id, providerMode: connection.providerMode, connectionID: connection.id)
                                } label: {
                                    if model.id == composerState.selectedModel && connection.id == viewModel.llmDefaultConnectionID {
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

                Divider()

                Menu {
                    ForEach(AppLLMThinkingLevel.allCases) { level in
                        Button {
                            viewModel.selectLLMThinkingLevel(level)
                        } label: {
                            if level == viewModel.llmThinkingLevel {
                                Label(level.displayName, systemImage: "checkmark")
                            } else {
                                Text(level.displayName)
                            }
                        }
                        .help(level.description)
                    }

                    Divider()

                    Button {
                        viewModel.selectDefaultLLMThinkingLevel(viewModel.llmThinkingLevel)
                    } label: {
                        Label("设为全局默认", systemImage: "pin")
                    }
                } label: {
                    Label("思考强度 · \(viewModel.llmThinkingLevel.displayName)", systemImage: "brain.head.profile")
                }

                if composerState.sessionHasLLMOverride {
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
                    Text(composerState.selectedModel.isEmpty ? "未选择模型" : composerState.selectedModel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "cpu")
                }
                if composerState.sessionHasLLMOverride {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .help("此会话使用自定义模型，与全局设置不同")
                }
            }
            .font(AgentChatTypography.micro.weight(.medium))
            .foregroundStyle(composerControlForeground)
            .padding(.horizontal, AgentChatLayout.spaceM)
            .frame(height: AgentChatLayout.chipHeight)
            .frame(maxWidth: AgentChatLayout.modelMenuMaxWidth)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.regular)
        .help("选择真实配置的连接和模型；切换后下一轮请求立即使用该模型")
    }

    private var activeSkillInlineChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(composerState.activeSkillDisplayName ?? "当前技能")
                .font(AgentChatTypography.meta.weight(.medium))
                .lineLimit(1)
            Button {
                sendComposerAction(.clearSkill)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor.opacity(0.72))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, AgentChatLayout.spaceS)
        .frame(height: AgentChatLayout.chipHeight)
        .background(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                .stroke(Color.accentColor.opacity(0.26), lineWidth: 1)
        )
        .help("当前技能：\(composerState.activeSkillDisplayName ?? "") — 点击 × 清除")
    }

    private var skillPickerButton: some View {
        Button {
            slashSkillPickerAnchorRect = nil
            isSkillPickerPresented.toggle()
        } label: {
            AgentComposerOptionBadge(
                title: "/技能",
                systemImage: composerState.activeSkillSlug == nil ? "bolt" : "bolt.fill",
                tint: isSkillPickerPresented ? composerControlActiveForeground : composerControlForeground,
                showsChevron: false,
                isActive: isSkillPickerPresented,
                style: .compact,
                showsBorder: false
            )
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { isSkillPickerPresented && slashSkillPickerAnchorRect == nil },
                set: { isPresented in isSkillPickerPresented = isPresented }
            ),
            arrowEdge: .bottom
        ) {
            skillPickerPopoverContent
                .padding(10)
                .frame(width: 320)
        }
        .help(composerState.activeSkillSlug != nil ? "当前技能：\(composerState.activeSkillDisplayName ?? "") — 点击 × 清除" : "输入 / 或点击选择技能")
    }

    private var skillPickerPopoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选择技能")
                .font(AgentChatTypography.micro.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            Divider()

            let allSkills = viewModel.commercialSkillManagerPresentation.cards
            if allSkills.isEmpty {
                Text("暂无可用技能")
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(allSkills.enumerated()), id: \.element.id) { index, card in
                    let isKeyboardSelected = index == skillPickerSelectionIndex
                    Button {
                        skillPickerSelectionIndex = index
                        selectSkill(card)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title)
                                    .font(AgentChatTypography.meta.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(card.subtitle)
                                    .font(AgentChatTypography.micro)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if card.id == composerState.activeSkillSlug {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                                .fill(isKeyboardSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if composerState.activeSkillSlug != nil {
                Divider()
                Button {
                    sendComposerAction(.clearSkill)
                    isSkillPickerPresented = false
                    slashSkillPickerAnchorRect = nil
                    slashSkillPickerTriggerRange = nil
                } label: {
                    Label("清除当前技能", systemImage: "xmark.circle")
                        .font(AgentChatTypography.micro)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
            }

            Divider()

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("在输入框中输入 / 也可唤出此列表")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
        }
    }

    private var composerControlForeground: Color { .secondary }

    private var composerControlActiveForeground: Color { .accentColor }

    private func promptBudgetStatusColor(_ status: AgentPromptBudgetStatus) -> Color {
        switch status {
        case .safe: return .secondary
        case .warning: return .orange
        case .over: return .red
        }
    }

}

// MARK: - Speech Input Keyboard Monitor

struct SpeechInputKeyboardMonitorState: Equatable, Sendable {
    var isOptionDown = false
    var isSpaceDown = false
    var isRecording = false
    var isSpaceHoldEnabled = false
}

enum SpeechInputKeyboardAction: Equatable, Sendable {
    case none
    case begin
    case end
    case consumeOnly
}

struct SpeechInputKeyboardMonitorReducer: Sendable {
    static func optionChanged(isDown: Bool, state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        guard state.isOptionDown != isDown else { return .none }
        state.isOptionDown = isDown
        if isDown {
            guard !state.isRecording else { return .none }
            state.isRecording = true
            return .begin
        }
        guard state.isRecording else { return .none }
        state.isRecording = false
        return .end
    }

    static func spaceKeyDown(isRepeat: Bool, state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        guard state.isSpaceHoldEnabled else { return .none }
        if isRepeat { return .consumeOnly }
        guard !state.isSpaceDown else { return .consumeOnly }
        state.isSpaceDown = true
        guard !state.isRecording else { return .consumeOnly }
        state.isRecording = true
        return .begin
    }

    static func spaceKeyUp(state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        guard state.isSpaceHoldEnabled else { return .none }
        guard state.isSpaceDown else { return .consumeOnly }
        state.isSpaceDown = false
        guard state.isRecording else { return .consumeOnly }
        state.isRecording = false
        return .end
    }

    static func cancel(state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        let shouldEnd = state.isRecording
        state.isOptionDown = false
        state.isSpaceDown = false
        state.isRecording = false
        return shouldEnd ? .end : .none
    }
}

@MainActor
final class SpeechInputKeyboardMonitor {
    private var monitor: Any?
    private var state: SpeechInputKeyboardMonitorState
    private let onBegin: () -> Void
    private let onEnd: () -> Void

    init(spaceHoldEnabled: Bool = false, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.state = SpeechInputKeyboardMonitorState(isSpaceHoldEnabled: spaceHoldEnabled)
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        perform(SpeechInputKeyboardMonitorReducer.cancel(state: &state))
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            let isOptionDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            perform(SpeechInputKeyboardMonitorReducer.optionChanged(isDown: isOptionDown, state: &state))
            return event
        case .keyDown where event.keyCode == 49:
            let action = SpeechInputKeyboardMonitorReducer.spaceKeyDown(isRepeat: event.isARepeat, state: &state)
            perform(action)
            return action == .none ? event : nil
        case .keyUp where event.keyCode == 49:
            let action = SpeechInputKeyboardMonitorReducer.spaceKeyUp(state: &state)
            perform(action)
            return action == .none ? event : nil
        default:
            return event
        }
    }

    private func perform(_ action: SpeechInputKeyboardAction) {
        switch action {
        case .begin: onBegin()
        case .end: onEnd()
        case .none, .consumeOnly: break
        }
    }
}
