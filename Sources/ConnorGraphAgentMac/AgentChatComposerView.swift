import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct ComposerModelSelectionPresentation: Equatable, Sendable {
    var selectedModel: String
    var sessionHasOverride: Bool

    var title: String {
        selectedModel.isEmpty ? "未选择模型" : selectedModel
    }

    var showsSessionOverrideIndicator: Bool {
        sessionHasOverride
    }

    var accessibilityLabel: String {
        var label = "模型：\(title)"
        if sessionHasOverride {
            label += "，此会话使用自定义模型"
        }
        return label
    }
}

struct AgentChatComposerView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    @Bindable var contactsFeatureModel: ContactsFeatureModel
    @Binding var isSessionInfoPresented: Bool
    var onExpandApprovalReview: ((AgentPendingApproval) -> Void)? = nil
    @State private var localChatInput: String = ""
    @State private var isWorkspacePopoverPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var isImageImporterPresented: Bool = false
    @State private var isSkillPickerPresented: Bool = false
    @State private var slashSkillPickerAnchorRect: CGRect?
    @State private var slashSkillPickerTriggerRange: NSRange?
    @State private var personMentionTrigger: PersonMentionTrigger?
    @State private var isPersonMentionPickerPresented: Bool = false
    @State private var personMentionPickerSelectionIndex: Int = 0
    @State private var composerSelectionTracker = ComposerTextSelectionTracker()
    @State private var skillPickerSelectionIndex: Int = 0
    @State private var speechKeyboardMonitor: SpeechInputKeyboardMonitor?
    @State private var composerPersonMentions: [ComposerPersonMention] = []

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
                    if composerState.displayMode == .note {
                        noteFormatBar
                    }

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
                .frame(minHeight: AgentChatLayout.composerTextMinHeight, maxHeight: composerState.displayMode == .note ? .infinity : AgentChatLayout.composerTextMaxHeight, alignment: .topLeading)

                HStack(spacing: AgentChatLayout.spaceS) {
                    attachmentButton

                    workingDirectoryMenu

                    Button {
                        model.workspaceExplorer.presentTree(
                            sessionID: model.sessions.selectedSessionID,
                            workingDirectoryPath: chatActions.dependencies.workspaceSettings.defaultWorkingDirectoryPath
                        )
                    } label: {
                        AgentComposerOptionBadge(
                            title: "文件",
                            systemImage: "folder",
                            tint: model.workspaceExplorer.isTreePresented ? composerControlActiveForeground : composerControlForeground,
                            showsChevron: false,
                            isActive: model.workspaceExplorer.isTreePresented,
                            style: .compact,
                            showsBorder: false
                        )
                    }
                    .buttonStyle(.plain)
                    .help("浏览当前会话工作目录")
                    .accessibilityLabel("打开当前会话文件树")

                    Button(action: { sendComposerAction(.toggleBrowserWorkspaceVisibility) }) {
                        AgentComposerOptionBadge(
                            title: chatActions.dependencies.browser.isVisible ? "隐藏浏览器" : "浏览器",
                            systemImage: "safari",
                            tint: chatActions.dependencies.browser.isVisible ? composerControlActiveForeground : composerControlForeground,
                            showsChevron: false,
                            isActive: chatActions.dependencies.browser.isVisible,
                            style: .prominent,
                            fill: Color.accentColor.opacity(chatActions.dependencies.browser.isVisible ? 0.12 : 0.06),
                            borderTint: .accentColor
                        )
                    }
                    .buttonStyle(.plain)
                    .help(chatActions.dependencies.browser.isVisible ? "隐藏浏览器工作区" : "显示浏览器工作区")
                    .accessibilityLabel(chatActions.dependencies.browser.isVisible ? "隐藏浏览器工作区" : "显示浏览器工作区")

                    if let inspection = model.run.lastPromptInspection {
                        promptBudgetLabel(inspection)
                            .layoutPriority(-1)
                    }

                    Spacer(minLength: AgentChatLayout.spaceXS)

                    modelSelectionMenu
                        .layoutPriority(2)

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
                    .fixedSize()
                    .layoutPriority(3)
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
                if let approval = chatActions.approval.activeChatPendingApprovals.first {
                    ZStack {
                        RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))

                        AgentChatPermissionRequestCard(
                            approval: approval,
                            model: model,
                            chatActions: chatActions,
                            onExpandReview: { onExpandApprovalReview?(approval) }
                        )
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
            localChatInput = model.composer.input
            installSpeechKeyboardMonitorIfNeeded()
        }
        .onDisappear {
            speechKeyboardMonitor?.stop()
            speechKeyboardMonitor = nil
        }
        .onChange(of: model.sessions.selectedSessionID) { _, _ in
            localChatInput = model.composer.input
            composerPersonMentions = []
            closePersonMentionPicker()
        }
        .onChange(of: model.composer.input) { _, newValue in
            guard newValue != localChatInput else { return }
            localChatInput = newValue
            composerPersonMentions = ComposerPersonMentionResolver().validatedMentions(in: newValue, mentions: composerPersonMentions)
            updatePersonMentionTrigger(for: newValue)
        }
        .onChange(of: chatActions.dependencies.inputSettings.sessionSpeechTranscriptionEnabled) { _, isEnabled in
            if isEnabled {
                installSpeechKeyboardMonitorIfNeeded()
            } else {
                speechKeyboardMonitor?.stop()
                speechKeyboardMonitor = nil
            }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: supportedAttachmentContentTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await chatActions.composer.importAttachments(urls: urls) }
            case .failure(let error):
                chatActions.composer.showAttachmentToast(title: "附件选择失败", message: String(describing: error), systemImage: "xmark.circle")
            }
        }
        .fileImporter(isPresented: $isImageImporterPresented, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                handleImageImport(urls)
            case .failure:
                break
            }
        }
    }

    private var selectedSession: AgentSession? {
        model.sessions.sessions.first { $0.id == model.sessions.selectedSessionID }
    }

    private var composerStore: AgentComposerStore {
        AgentComposerStore(model: model, actions: chatActions)
    }

    private var composerState: AgentComposerState {
        composerStore.state(input: localChatInput, canSubmit: canSubmitLocalChat, selectedSession: selectedSession)
    }

    private func sendComposerAction(_ action: AgentComposerAction) {
        composerStore.send(action)
    }

    private func installSpeechKeyboardMonitorIfNeeded() {
        guard chatActions.dependencies.inputSettings.sessionSpeechTranscriptionEnabled else { return }
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
                composerPersonMentions = ComposerPersonMentionResolver().validatedMentions(in: newValue, mentions: composerPersonMentions)
                updatePersonMentionTrigger(for: newValue)
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
                isSpellCheckEnabled: chatActions.dependencies.inputSettings.spellCheckEnabled,
                sendShortcut: chatActions.dependencies.inputSettings.composerSendShortcut,
                isSkillPickerPresented: isSkillPickerPresented,
                isPersonMentionPickerPresented: isPersonMentionPickerPresented,
                onSubmit: submitLocalChatInput,
                onImportFiles: importComposerFiles,
                onSlashCommand: handleSlashCommand,
                onSkillPickerKeyCommand: handleSkillPickerKeyCommand,
                onPersonMentionPickerKeyCommand: handlePersonMentionPickerKeyCommand,
                onAttachmentImportError: handleAttachmentImportError,
                onTextFileDropped: { droppedText in
                    if localChatInput.isEmpty {
                        localChatInput = droppedText
                    } else {
                        localChatInput += "\n\n\(droppedText)"
                    }
                    chatActions.composer.updateSelectedChatInputDraft(localChatInput)
                },
                isNoteMode: composerState.displayMode == .note
            )

            slashSkillPickerAnchor
            personMentionPickerAnchor
        }
    }

    private var composerPlaceholder: String {
        if composerState.displayMode == .note {
            return "写下你的笔记..."
        }
        let sendHint = chatActions.dependencies.inputSettings.composerSendShortcut == "cmd-return" ? "⌘ + Return 发送" : "Shift + Return 换行"
        return "输入 / 选择技能，输入 @ 选择人名；\(sendHint)"
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

    private var noteFormatBar: some View {
        ComposerFormatBar(
            text: localChatInputBinding,
            selectionTracker: composerSelectionTracker,
            onInsertImage: { isImageImporterPresented = true }
        )
    }

    private func handleImageImport(_ urls: [URL]) {
        Task {
            let result = await chatActions.composer.importAttachments(urls: urls)
            guard !result.accepted.isEmpty else { return }
            let imageRefs = result.accepted.filter { $0.kind == .image }
            for ref in imageRefs {
                // Insert Markdown image reference into composer
                let mdImage = "![^\(ref.displayName)]"
                if localChatInput.isEmpty {
                    localChatInput = mdImage
                } else {
                    localChatInput += "\n\n\(mdImage)"
                }
                chatActions.composer.updateSelectedChatInputDraft(localChatInput)
                // Check model image support
                if !chatActions.composer.currentModelSupportsImages() {
                    chatActions.composer.showAttachmentToast(
                        title: "图片已保存到本地",
                        message: "当前模型不支持图片识别，仅发送文字内容给模型。你可以在后续对话中引用这张图片。",
                        systemImage: "photo.badge.checkmark"
                    )
                }
            }
        }
    }

    private func handleSlashCommand(_ rect: CGRect, triggerRange: NSRange) {
        slashSkillPickerAnchorRect = rect
        slashSkillPickerTriggerRange = triggerRange
        skillPickerSelectionIndex = preferredSkillPickerSelectionIndex()
        isSkillPickerPresented = true
        closePersonMentionPicker()
    }

    @ViewBuilder
    private var personMentionPickerAnchor: some View {
        if isPersonMentionPickerPresented, let trigger = personMentionTrigger {
            VStack {
                PersonMentionPickerView(
                    query: trigger.query,
                    profiles: contactsFeatureModel.profiles,
                    selectionIndex: personMentionPickerSelectionIndex,
                    onSelect: selectPersonMention
                )
                Spacer(minLength: 0)
            }
            .padding(.top, AgentChatLayout.spaceL)
            .padding(.leading, AgentChatLayout.spaceL)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
        }
    }

    private var personMentionPickerResults: [PersonProfile] {
        guard let trigger = personMentionTrigger else { return [] }
        return PersonMentionSearch().search(query: trigger.query, profiles: contactsFeatureModel.profiles, limit: 8)
    }

    private func updatePersonMentionTrigger(for text: String) {
        let selectedRange = composerSelectionTracker.selectedRange ?? NSRange(location: (text as NSString).length, length: 0)
        if let trigger = PersonMentionTriggerDetector().trigger(in: text, selectedRange: selectedRange) {
            personMentionTrigger = trigger
            personMentionPickerSelectionIndex = 0
            isPersonMentionPickerPresented = true
            closeSkillPicker()
        } else {
            closePersonMentionPicker()
        }
    }

    private func selectPersonMention(_ profile: PersonProfile) {
        guard let trigger = personMentionTrigger else { return }
        do {
            let replacement = try ComposerPersonMentionTextRewriter().replace(trigger: trigger, in: localChatInput, with: profile)
            localChatInput = replacement.text
            composerSelectionTracker.selectedRange = replacement.selectedRange
            composerPersonMentions = ComposerPersonMentionResolver().validatedMentions(in: replacement.text, mentions: composerPersonMentions + [replacement.mention])
            chatActions.composer.updateSelectedChatInputDraft(replacement.text)
            sendComposerAction(.inputChanged(replacement.text))
            closePersonMentionPicker()
        } catch {
            closePersonMentionPicker()
        }
    }

    private func closePersonMentionPicker() {
        isPersonMentionPickerPresented = false
        personMentionTrigger = nil
        personMentionPickerSelectionIndex = 0
    }

    private var canSubmitLocalChat: Bool {
        !localChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.composer.pendingAttachmentRefs.isEmpty
    }

    private func removeSlashSkillPickerTriggerIfNeeded() {
        guard let triggerRange = slashSkillPickerTriggerRange,
              let range = Range(triggerRange, in: localChatInput),
              localChatInput[range] == "/"
        else { return }
        localChatInput.removeSubrange(range)
        chatActions.composer.updateSelectedChatInputDraft(localChatInput)
    }

    private func preferredSkillPickerSelectionIndex() -> Int {
        let cards = chatActions.dependencies.skills.presentation.cards
        guard !cards.isEmpty else { return 0 }
        if let activeSkillSlug = composerState.activeSkillSlug,
           let activeIndex = cards.firstIndex(where: { $0.id == activeSkillSlug }) {
            return activeIndex
        }
        return 0
    }

    private func handleSkillPickerKeyCommand(_ command: SkillPickerKeyCommand) {
        let cards = chatActions.dependencies.skills.presentation.cards
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

    private func handlePersonMentionPickerKeyCommand(_ command: SkillPickerKeyCommand) {
        let results = personMentionPickerResults
        switch command {
        case .moveUp:
            guard !results.isEmpty else { return }
            personMentionPickerSelectionIndex = (personMentionPickerSelectionIndex - 1 + results.count) % results.count
        case .moveDown:
            guard !results.isEmpty else { return }
            personMentionPickerSelectionIndex = (personMentionPickerSelectionIndex + 1) % results.count
        case .confirm:
            guard results.indices.contains(personMentionPickerSelectionIndex) else { return }
            selectPersonMention(results[personMentionPickerSelectionIndex])
        case .cancel:
            closePersonMentionPicker()
        }
    }

    private func submitLocalChatInput() {
        let prompt = localChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = localChatInput
        let submittedText = localChatInput
        let submittedMentions = composerPersonMentions
        let personReferences = ComposerPersonMentionResolver().personReferences(in: submittedText, mentions: submittedMentions)
        localChatInput = ""
        composerPersonMentions = []
        closePersonMentionPicker()
        chatActions.composer.updateSelectedChatInputDraft("")
        Task {
            let runID = await chatActions.run.submitChat(prompt: prompt, clearComposer: true, displayPrompt: displayPrompt, personReferences: personReferences)
            if runID == nil, localChatInput.isEmpty {
                localChatInput = submittedText
                composerPersonMentions = submittedMentions
                chatActions.composer.updateSelectedChatInputDraft(submittedText)
            }
        }
    }

    private var workingDirectoryMenu: some View {
        Button {
            isWorkspacePopoverPresented.toggle()
        } label: {
            AgentComposerOptionBadge(
                title: workingDirectoryBadgeTitle,
                systemImage: chatActions.dependencies.workspaceSettings.primaryRoot == nil ? "folder" : "folder.fill",
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
            if chatActions.dependencies.workspaceSettings.roots.isEmpty {
                Text("尚未设置工作目录")
                    .font(AgentChatTypography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(chatActions.dependencies.workspaceSettings.roots) { root in
                        workspaceRootPopoverRow(root)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Label("历史打开列表", systemImage: "clock.arrow.circlepath")
                    .font(AgentChatTypography.calloutEmphasis)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)

                if chatActions.dependencies.workspaceSettings.recentPaths.isEmpty {
                    Text("暂无历史记录")
                        .font(AgentChatTypography.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                } else {
                    ForEach(chatActions.dependencies.workspaceSettings.recentPaths, id: \.self) { path in
                        Button {
                            chatActions.dependencies.workspaceSettings.selectWorkingDirectory(path: path)
                            isWorkspacePopoverPresented = false
                        } label: {
                            workspaceMenuItemLabel(title: workspaceMenuItemTitle(forPath: path), systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .font(AgentChatTypography.callout)
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
                    chatActions.dependencies.workspaceSettings.reset()
                    isWorkspacePopoverPresented = false
                } label: {
                    Label("重置为默认", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(chatActions.dependencies.workspaceSettings.roots.isEmpty && chatActions.dependencies.workspaceSettings.defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    chatActions.dependencies.workspaceSettings.clearRecentPaths()
                } label: {
                    Label("清空历史", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(chatActions.dependencies.workspaceSettings.recentPaths.isEmpty)
            }
            .font(AgentChatTypography.callout)
            .padding(.horizontal, 4)
        }
    }

    private func workspaceRootPopoverRow(_ root: WorkspaceRootDraft) -> some View {
        HStack(spacing: 6) {
            Button {
                chatActions.dependencies.workspaceSettings.setPrimaryRoot(id: root.id)
                isWorkspacePopoverPresented = false
            } label: {
                workspaceMenuItemLabel(title: workspaceMenuItemTitle(for: root), systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(AgentChatTypography.body)
            .help(root.path)

            Button {
                chatActions.dependencies.workspaceSettings.removeRoot(id: root.id)
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
        guard let root = chatActions.dependencies.workspaceSettings.primaryRoot else { return "选择工作目录" }
        return workspaceDisplayName(for: root)
    }

    private var workingDirectoryHelpText: String {
        guard let root = chatActions.dependencies.workspaceSettings.primaryRoot else {
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
            chatActions.dependencies.workspaceSettings.selectWorkingDirectory(path: url.path)
        }
    }

    private func menuOptionTitle(_ title: String, isSelected: Bool) -> String {
        "\(isSelected ? "✓" : "  ")  \(title)"
    }

    private var optionBadgeRow: some View {
        AgentComposerOptionBar(
            selectedSession: selectedSession,
            composerState: composerState,
            governanceConfig: chatActions.dependencies.governance.config,
            knowledgeMarketplace: chatActions.dependencies.knowledgeMarketplace,
            sourceRuntime: chatActions.dependencies.sources,
            hasRunningBackgroundTask: chatActions.run.hasRunningActiveSessionBackgroundTask,
            currentTextSelectionRange: { composerSelectionTracker.selectedRange },
            isSessionInfoPresented: $isSessionInfoPresented,
            onAction: sendComposerAction
        )
    }

    private var modelSelectionMenu: some View {
        Menu {
            if chatActions.dependencies.aiConnections.isLoadingModelConnections {
                Label("正在加载模型列表…", systemImage: "arrow.triangle.2.circlepath")
            }

            if chatActions.dependencies.aiConnections.modelConnections.isEmpty {
                Button(composerState.selectedModel.isEmpty ? "未选择模型" : composerState.selectedModel) {}
                    .disabled(true)
            } else {
                ForEach(chatActions.dependencies.aiConnections.modelConnections) { connection in
                    Menu {
                        if connection.models.isEmpty {
                            Button("没有可用模型") {}
                                .disabled(true)
                        } else {
                            ForEach(connection.models) { model in
                                Button {
                                    chatActions.run.selectLLMModel(model.id, providerMode: connection.providerMode, connectionID: connection.id)
                                } label: {
                                    if model.id == composerState.selectedModel && connection.id == chatActions.dependencies.aiConnections.defaultConnectionID {
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
                            chatActions.run.selectLLMThinkingLevel(level)
                        } label: {
                            if level == chatActions.dependencies.aiConnections.thinkingLevel {
                                Label(level.displayName, systemImage: "checkmark")
                            } else {
                                Text(level.displayName)
                            }
                        }
                        .help(level.description)
                    }

                    Divider()

                    Button {
                        chatActions.run.selectDefaultLLMThinkingLevel(chatActions.dependencies.aiConnections.thinkingLevel)
                    } label: {
                        Label("设为全局默认", systemImage: "pin")
                    }
                } label: {
                    Label("思考强度 · \(chatActions.dependencies.aiConnections.thinkingLevel.displayName)", systemImage: "brain.head.profile")
                }

                if composerState.sessionHasLLMOverride {
                    Divider()
                    Button {
                        chatActions.run.clearSessionLLMOverride()
                    } label: {
                        Label("恢复全局默认模型", systemImage: "arrow.counterclockwise")
                    }
                }

                Divider()

                Button {
                    Task { await chatActions.run.reloadLLMModelConnections() }
                } label: {
                    Label("刷新模型列表", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            ComposerModelSelectionLabel(
                presentation: ComposerModelSelectionPresentation(
                    selectedModel: composerState.selectedModel,
                    sessionHasOverride: composerState.sessionHasLLMOverride
                ),
                foreground: composerControlForeground
            )
        }
        .menuStyle(.borderlessButton)
        .controlSize(.regular)
        .help("选择真实配置的连接和模型；切换后下一轮请求立即使用该模型")
        .accessibilityHint("选择模型和思考强度")
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

            let allSkills = chatActions.dependencies.skills.presentation.cards
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
                    .font(AgentChatTypography.micro)
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
        }
    }

    private var attachmentButton: some View {
        let isNoteMode = composerState.displayMode == .note
        return Button(action: { isFileImporterPresented = true }) {
            Image(systemName: "paperclip")
                .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isNoteMode ? Color.secondary.opacity(0.42) : composerControlForeground)
        .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
        .contentShape(Rectangle())
        .disabled(isNoteMode)
        .opacity(isNoteMode ? 0.4 : 1.0)
        .help(isNoteMode ? "笔记模式下不可用，请用格式工具栏插入图片" : "添加附件")
        .accessibilityLabel("添加附件")
    }

    private var composerControlForeground: Color { .secondary }

    private var composerControlActiveForeground: Color { .accentColor }

    @ViewBuilder
    private func promptBudgetLabel(_ inspection: AgentChatPromptInspection) -> some View {
        Label("约 \(inspection.estimatedPromptTokenCount) tokens", systemImage: "text.alignleft")
            .font(AgentChatTypography.micro)
            .foregroundStyle(promptBudgetStatusColor(inspection.promptBudgetStatus))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 128, alignment: .leading)
            .accessibilityLabel("预计提示词约 \(inspection.estimatedPromptTokenCount) tokens")
    }

    private func promptBudgetStatusColor(_ status: AgentPromptBudgetStatus) -> Color {
        switch status {
        case .safe: return .secondary
        case .warning: return .orange
        case .over: return .red
        }
    }

}

struct RemoteKnowledgeBaseSelectionMenu: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore
    var explicitIDs: [String]?
    var isDisabled: Bool
    var onSelectionChanged: ([String]?) -> Void
    @State private var isPresented = false

    private var available: [CloudMarketplaceKnowledgeBase] {
        store.library.availableForConsumption
    }

    private var selection: RemoteKnowledgeBaseSelection {
        RemoteKnowledgeBaseSelection(available: available, explicitIDs: explicitIDs)
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            AgentComposerOptionBadge(
                title: selection.label,
                systemImage: "books.vertical",
                tint: .secondary,
                isActive: false,
                style: .prominent,
                showsBorder: false
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help("选择本会话允许访问的远端知识库")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("远端知识库")
                        .font(AgentChatTypography.sectionTitle)
                    Spacer()
                    Button(selection.isAllSelected ? "清除全选" : "全选") {
                        onSelectionChanged(selection.toggleAllValue)
                    }
                    .font(AgentChatTypography.callout)
                    .disabled(available.isEmpty)
                }
                .padding(12)

                Divider()

                if available.isEmpty {
                    AgentComposerPopoverEmptyState(
                        title: "暂无可用知识库",
                        systemImage: "books.vertical",
                        message: "订阅知识库，或发布自己的知识库后会显示在这里。"
                    )
                    .frame(minHeight: 150)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(available) { knowledgeBase in
                                Toggle(isOn: Binding(
                                    get: { selection.selectedIDs.contains(knowledgeBase.id) },
                                    set: { _ in onSelectionChanged(selection.toggling(knowledgeBase.id)) }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(knowledgeBase.name).lineLimit(1)
                                        Text(knowledgeBase.id)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 320)
                }
            }
            .frame(width: 320)
        }
        .task {
            if store.library.availableForConsumption.isEmpty { await store.load() }
        }
    }
}

private struct ComposerModelSelectionLabel: View {
    let presentation: ComposerModelSelectionPresentation
    var foreground: Color

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceXS) {
            Image(systemName: "cpu")
                .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(presentation.title)
                .font(AgentChatTypography.metaEmphasis)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
        .foregroundStyle(foreground)
        .padding(.leading, AgentChatLayout.spaceM)
        .padding(.trailing, presentation.showsSessionOverrideIndicator ? AgentChatLayout.spaceL : AgentChatLayout.spaceM)
        .frame(minWidth: 96, idealWidth: 148, maxWidth: AgentChatLayout.modelMenuMaxWidth, minHeight: AgentChatLayout.chipHeight, maxHeight: AgentChatLayout.chipHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if presentation.showsSessionOverrideIndicator {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                    .padding(.trailing, 6)
                    .help("此会话使用自定义模型，与全局设置不同")
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
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

// MARK: - Note Format Bar

/// 笔记模式的 Markdown 格式工具栏
/// 紧贴 Composer 文本框上方，提供 Markdown 语法快捷插入按钮
private struct ComposerFormatBar: View {
    @Binding var text: String
    var selectionTracker: ComposerTextSelectionTracker
    var onInsertImage: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            formatButton(systemImage: "bold", shortcut: "B", action: wrapSelection(prefix: "**", suffix: "**", placeholder: "加粗文本"))
            formatButton(systemImage: "italic", shortcut: "I", action: wrapSelection(prefix: "*", suffix: "*", placeholder: "斜体文本"))

            Divider()
                .frame(height: 14)

            formatButton(systemImage: "textformat.size", shortcut: "H1", action: insertLinePrefix("# ", placeholder: "标题"))
            formatButton(systemImage: "textformat.size.smaller", shortcut: "H2", action: insertLinePrefix("## ", placeholder: "标题"))

            Divider()
                .frame(height: 14)

            formatButton(systemImage: "list.bullet", shortcut: nil, action: insertLinePrefix("- ", placeholder: "列表项"))
            formatButton(systemImage: "list.number", shortcut: nil, action: insertLinePrefix("1. ", placeholder: "列表项"))

            Divider()
                .frame(height: 14)

            formatButton(systemImage: "text.quote", shortcut: nil, action: insertLinePrefix("> ", placeholder: "引用文本"))
            formatButton(systemImage: "curlybraces", shortcut: nil, action: insertCodeBlock)

            Divider()
                .frame(height: 14)

            Button(action: onInsertImage) {
                Label("图片", systemImage: "photo")
                    .lineLimit(1)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.appIcon)
            .foregroundStyle(.secondary)
            .help("插入图片")
            .accessibilityLabel("插入图片")

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: AppButtonLayout.iconButtonSize + 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func formatButton(systemImage: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let shortcut {
                Text(shortcut)
                    .font(AppTypography.monoMicroEmphasis)
            } else {
                Image(systemName: systemImage)
            }
        }
        .buttonStyle(.appIcon)
        .foregroundStyle(.secondary)
        .help(shortcut.map { "\($0) (\(buttonHelpLabel(systemImage: systemImage)))" } ?? buttonHelpLabel(systemImage: systemImage))
        .accessibilityLabel(buttonAccessibilityLabel(systemImage: systemImage, shortcut: shortcut))
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) -> () -> Void {
        {
            guard let selectedRange = selectionTracker.selectedRange,
                  selectedRange.location != NSNotFound
            else {
                text += "\(prefix)\(placeholder)\(suffix)"
                return
            }

            let nsText = text as NSString
            let location = min(selectedRange.location, nsText.length)
            let length = min(selectedRange.length, nsText.length - location)

            if length > 0 {
                let selectedText = nsText.substring(with: NSRange(location: location, length: length))
                let replacement = "\(prefix)\(selectedText)\(suffix)"
                text = nsText.replacingCharacters(in: NSRange(location: location, length: length), with: replacement)
            } else {
                let replacement = "\(prefix)\(placeholder)\(suffix)"
                text = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: replacement)
                let cursorInside = location + prefix.count
                selectionTracker.selectedRange = NSRange(location: cursorInside, length: placeholder.count)
            }
        }
    }

    private func insertLinePrefix(_ prefix: String, placeholder: String) -> () -> Void {
        {
            guard let selectedRange = selectionTracker.selectedRange,
                  selectedRange.location != NSNotFound,
                  selectedRange.location <= (text as NSString).length
            else {
                let newLine = text.isEmpty ? "" : "\n"
                text += "\(newLine)\(prefix)\(placeholder)"
                return
            }

            let nsText = text as NSString
            let location = selectedRange.location
            var insertionPoint = location

            if location > 0 {
                let precedingChar = nsText.substring(with: NSRange(location: location - 1, length: 1))
                if precedingChar == "\n" || precedingChar == "\r" {
                    insertionPoint = location
                } else {
                    let replacement = "\n\(prefix)\(placeholder)"
                    text = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: replacement)
                    return
                }
            }

            let replacement = "\(prefix)\(placeholder)"
            text = nsText.replacingCharacters(in: NSRange(location: insertionPoint, length: 0), with: replacement)
        }
    }

    private func insertCodeBlock() {
        let codeBlock = "\n```\n\n```\n"
        guard let selectedRange = selectionTracker.selectedRange,
              selectedRange.location != NSNotFound
        else {
            text += codeBlock
            return
        }

        let nsText = text as NSString
        let location = min(selectedRange.location, nsText.length)
        text = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: codeBlock)
    }

    private func buttonHelpLabel(systemImage: String) -> String {
        switch systemImage {
        case "bold": return "Cmd+B"
        case "italic": return "Cmd+I"
        case "textformat.size": return "一级标题"
        case "textformat.size.smaller": return "二级标题"
        case "list.bullet": return "无序列表"
        case "list.number": return "有序列表"
        case "text.quote": return "引用"
        case "curlybraces": return "代码块"
        case "photo": return "插入图片"
        default: return ""
        }
    }

    private func buttonAccessibilityLabel(systemImage: String, shortcut: String?) -> String {
        switch systemImage {
        case "bold": return "加粗"
        case "italic": return "斜体"
        case "textformat.size": return "一级标题"
        case "textformat.size.smaller": return "二级标题"
        case "list.bullet": return "无序列表"
        case "list.number": return "有序列表"
        case "text.quote": return "引用"
        case "curlybraces": return "代码块"
        case "photo": return "插入图片"
        default: return ""
        }
    }
}

private struct PersonMentionPickerView: View {
    var query: String
    var profiles: [PersonProfile]
    var selectionIndex: Int
    var onSelect: (PersonProfile) -> Void

    private var results: [PersonProfile] {
        PersonMentionSearch().search(query: query, profiles: profiles, limit: 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text(query.isEmpty ? "选择人物" : "没有匹配的人物")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AgentChatLayout.spaceM)
                    .padding(.vertical, AgentChatLayout.spaceS)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        onSelect(profile)
                    } label: {
                        HStack(spacing: AgentChatLayout.spaceS) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(AgentChatTypography.metaEmphasis)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(profile.contactSubtitle)
                                    .font(AgentChatTypography.micro)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: AgentChatLayout.spaceS)
                        }
                        .padding(.horizontal, AgentChatLayout.spaceM)
                        .padding(.vertical, AgentChatLayout.spaceS)
                        .background(index == selectionIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择人物：\(profile.displayName)")
                }
            }
        }
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(query.isEmpty ? "人物选择列表" : "人物选择列表，搜索：\(query)")
    }
}
