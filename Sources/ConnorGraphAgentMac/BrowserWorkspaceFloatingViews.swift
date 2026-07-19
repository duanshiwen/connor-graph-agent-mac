import SwiftUI

enum BrowserFloatingTypography {
    // Browser chrome follows a compact macOS semantic scale: clear hierarchy,
    // consistent controls, and legible 12–14 pt text instead of one-off sizes.
    static let popoverTitle = AppTypography.sectionTitle
    static let pageTitle = AppTypography.bodyEmphasis
    static let pageURL = AppTypography.caption
    static let selectedText = AppTypography.body
    static let input = AppTypography.body
    static let hint = AppTypography.caption
    static let messageRole = AppTypography.captionEmphasis
    static let messageBody = AppTypography.body
    static let askButton = AppTypography.bodyEmphasis
    static let askButtonIcon = AppTypography.bodyEmphasis
    static let quickAction = AppTypography.captionEmphasis
    static let quickActionIcon = AppTypography.captionEmphasis
    static let loadingOverlay = AppTypography.captionEmphasis
    static let toolbarIcon = AppTypography.bodyEmphasis
    static let tabTitle = AppTypography.caption
    static let tabTitleSelected = AppTypography.captionEmphasis
    static let tabIcon = AppTypography.caption
    static let tabCloseIcon = AppTypography.microEmphasis
}

struct BrowserSelectionPopover: View {
    var popover: BrowserSelectionPopoverState
    var thread: BrowserSelectionThread?
    @Binding var question: String
    var isSubmitting: Bool
    var onAsk: () -> Void
    var onSummarizePage: () -> Void
    var onCancel: () -> Void
    var onClose: () -> Void

    static let quickPageSummaryPrompt = "总结当前网页，提取主要内容、核心论点、关键论据、重要观点或故事信息。"

    var body: some View {
        let isPageQuestion = popover.context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(isPageQuestion ? "问一问 AI" : "网页选择", systemImage: isPageQuestion ? "sparkles" : "selection.pin.in.out")
                    .font(BrowserFloatingTypography.popoverTitle)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(BrowserFloatingTypography.toolbarIcon)
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !popover.context.page.title.isEmpty {
                    Text(popover.context.page.title)
                        .font(BrowserFloatingTypography.pageTitle)
                        .lineLimit(1)
                }
                if !popover.context.page.url.isEmpty {
                    Text(popover.context.page.url)
                        .font(BrowserFloatingTypography.pageURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !isPageQuestion {
                Text(popover.context.selectedText)
                    .font(BrowserFloatingTypography.selectedText)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            BrowserSelectionThreadList(messages: thread?.messages ?? [], isPageQuestion: isPageQuestion)
                .frame(maxHeight: 360)

            if isPageQuestion {
                HStack(spacing: 8) {
                    Button(action: onSummarizePage) {
                        BrowserQuickActionBadge(title: "总结网页主要内容", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .help(Self.quickPageSummaryPrompt)

                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 8) {
                TextField(isPageQuestion ? "基于当前网页提问…" : "基于选中文本提问…", text: $question, axis: .vertical)
                    .font(BrowserFloatingTypography.input)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit(onAsk)

                AgentSendControlButton(
                    isSubmitting: isSubmitting,
                    isDisabled: !isSubmitting && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: {
                        if isSubmitting {
                            onCancel()
                        } else {
                            onAsk()
                        }
                    }
                )
            }

            Text("发送后浮窗保持打开")
                .font(BrowserFloatingTypography.hint)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

struct BrowserSelectionThreadList: View {
    var messages: [BrowserSelectionThreadMessage]
    var isPageQuestion: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if messages.isEmpty {
                    Text(isPageQuestion ? "这个网页还没有提问记录。" : "这个网页选择还没有提问记录。")
                        .font(BrowserFloatingTypography.messageBody)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(messages) { message in
                        HStack(alignment: .top, spacing: 6) {
                            Text(message.role == .user ? "你" : "AI")
                                .font(BrowserFloatingTypography.messageRole)
                                .foregroundStyle(message.role == .user ? ConnorCraftPalette.accent : Color.secondary)
                                .frame(width: 28, alignment: .leading)
                            if message.isPending {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.62)
                                    Text("正在生成回复…")
                                        .font(BrowserFloatingTypography.messageBody)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if message.role == .assistant {
                                AgentMarkdownPreviewText(markdown: message.text, font: BrowserFloatingTypography.messageBody)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(message.text)
                                    .font(BrowserFloatingTypography.messageBody)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BrowserFormAssistantPopover: View {
    var state: BrowserFormAssistantState
    @Binding var question: String
    var tone: Binding<BrowserFormAssistantTone>
    var length: Binding<BrowserFormAssistantLength>
    var language: Binding<BrowserFormAssistantLanguage>
    var siteEnabled: Bool
    var canUndo: Bool
    var onTask: (BrowserFormQuickTask) -> Void
    var onAsk: () -> Void
    var onCancel: () -> Void
    var onUpdateCandidate: (UUID, String) -> Void
    var onInsert: (String, BrowserFormInsertionMode) -> Void
    var onUndo: () -> Void
    var onToggleSite: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("输入助手", systemImage: "sparkles")
                    .font(BrowserFloatingTypography.popoverTitle)
                Text(state.semantic.displayName)
                    .font(BrowserFloatingTypography.hint)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(siteEnabled ? "在此网站关闭" : "在此网站启用", action: onToggleSite)
                    if canUndo { Button("撤销上次插入", systemImage: "arrow.uturn.backward", action: onUndo) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(BrowserFloatingTypography.toolbarIcon)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("输入助手设置")
                Button(action: onClose) {
                    Image(systemName: "xmark").font(BrowserFloatingTypography.toolbarIcon)
                }
                .buttonStyle(.borderless)
                .help("关闭输入助手")
            }

            if state.field.sensitive {
                Label(state.field.sensitiveReason.isEmpty ? "此字段可能包含敏感信息，请手动填写。" : state.field.sensitiveReason,
                      systemImage: "hand.raised.fill")
                    .font(BrowserFloatingTypography.messageBody)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if !siteEnabled {
                Text("此网站的输入助手已关闭。")
                    .font(BrowserFloatingTypography.messageBody)
                    .foregroundStyle(.secondary)
            } else {
                fieldSummary
                controls

                if state.candidates.isEmpty && !state.isGenerating {
                    HStack(spacing: 6) {
                        ForEach(state.quickTasks) { task in
                            Button { onTask(task) } label: {
                                BrowserQuickActionBadge(title: task.title, systemImage: task.systemImage)
                            }
                            .buttonStyle(.plain)
                            .help(task.prompt)
                        }
                    }
                }

                if state.isGenerating {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("正在生成候选…").font(BrowserFloatingTypography.messageBody).foregroundStyle(.secondary)
                        Spacer()
                        Button("取消", action: onCancel).buttonStyle(.plain).font(BrowserFloatingTypography.hint)
                    }
                    .padding(.vertical, 6)
                }

                if !state.candidates.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(state.candidates) { candidate in
                                candidateRow(candidate)
                            }
                        }
                    }
                    .frame(maxHeight: 260)

                    HStack(spacing: 5) {
                        refinementButton("更简短", prompt: "将当前候选改得更简短，继续返回三个候选。")
                        refinementButton("更正式", prompt: "将当前候选改得更正式，继续返回三个候选。")
                        refinementButton("更友好", prompt: "将当前候选改得更友好自然，继续返回三个候选。")
                        refinementButton("重新生成", prompt: "根据当前要求重新生成三个不同候选。")
                    }
                }

                if let latestRequest = state.messages.last(where: { $0.role == .user }) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("你").font(BrowserFloatingTypography.messageRole).foregroundStyle(ConnorCraftPalette.accent)
                        Text(latestRequest.text).font(BrowserFloatingTypography.hint).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                if let error = state.errorMessage, !error.isEmpty {
                    Text(error).font(BrowserFloatingTypography.hint).foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    TextField("继续修改或说明你的要求…", text: $question, axis: .vertical)
                        .font(BrowserFloatingTypography.input)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .onSubmit(onAsk)
                    AgentSendControlButton(
                        isSubmitting: state.isGenerating,
                        isDisabled: !state.isGenerating && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: state.isGenerating ? onCancel : onAsk
                    )
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.secondary.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private var fieldSummary: some View {
        let label = [state.field.label, state.field.ariaLabel, state.field.placeholder]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "当前输入框"
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).font(BrowserFloatingTypography.pageTitle).lineLimit(1)
            if !state.field.currentValue.isEmpty {
                Text(state.field.currentValue)
                    .font(BrowserFloatingTypography.selectedText)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            compactPicker("语气", selection: tone, values: BrowserFormAssistantTone.allCases)
            compactPicker("长度", selection: length, values: BrowserFormAssistantLength.allCases)
            compactPicker("语言", selection: language, values: BrowserFormAssistantLanguage.allCases)
            Spacer(minLength: 0)
        }
    }

    private func compactPicker<Value: Hashable & Identifiable & RawRepresentable>(
        _ title: String,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value.RawValue == String {
        Picker(title, selection: selection) {
            ForEach(values) { value in Text(value.rawValue).tag(value) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .help(title)
    }

    private func candidateRow(_ candidate: BrowserFormCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(candidate.label).font(BrowserFloatingTypography.messageRole).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("插入到光标", systemImage: "text.cursor") { onInsert(candidate.text, .insert) }
                    Button("替换选中内容", systemImage: "selection.pin.in.out") { onInsert(candidate.text, .replaceSelection) }
                    Button("替换全部", systemImage: "arrow.triangle.2.circlepath") { onInsert(candidate.text, .replaceAll) }
                } label: {
                    Label("插入", systemImage: "arrow.down.to.line.compact")
                        .font(BrowserFloatingTypography.quickAction)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            TextEditor(text: Binding(
                get: { candidate.text },
                set: { onUpdateCandidate(candidate.id, $0) }
            ))
            .font(BrowserFloatingTypography.messageBody)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 48, maxHeight: 82)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.secondary.opacity(0.10), lineWidth: 1))
    }

    private func refinementButton(_ title: String, prompt: String) -> some View {
        Button {
            onTask(.init(id: title, title: title, systemImage: "wand.and.stars", prompt: prompt))
        } label: {
            Text(title).font(BrowserFloatingTypography.quickAction).lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(height: 24)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}

enum BrowserFormInsertionMode: String, Sendable {
    case insert
    case replaceSelection
    case replaceAll
}

struct BrowserQuickActionBadge: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(BrowserFloatingTypography.quickActionIcon)
            Text(title)
                .font(BrowserFloatingTypography.quickAction)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .foregroundStyle(Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct BrowserTabChip: View {
    var title: String
    var url: String
    var width: CGFloat
    var isSelected: Bool
    var isLoading: Bool
    var isPrivate: Bool = false
    var sessionTitle: String? = nil
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : (isPrivate ? "hand.raised.fill" : "globe"))
                .font(BrowserFloatingTypography.tabIcon)
                .foregroundStyle(.secondary.opacity(isSelected ? 0.85 : 0.65))

            Text(title)
                .font(isSelected ? BrowserFloatingTypography.tabTitleSelected : BrowserFloatingTypography.tabTitle)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(BrowserFloatingTypography.tabCloseIcon)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary.opacity(0.72))
            .help("关闭标签页")
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .frame(width: width, height: 25)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tabBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture(perform: onSelect)
        .help([sessionTitle, url].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: "\n"))
        .accessibilityLabel(sessionTitle.map { "\(title)，会话：\($0)" } ?? title)
    }

    private var tabBackground: Color { isSelected ? Color(nsColor: .controlBackgroundColor) : Color.secondary.opacity(0.045) }
    private var tabBorder: Color { isSelected ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.07) }
}

struct BrowserVerticalTabGroupHeader: View {
    var title: String
    var count: Int
    var isExpanded: Bool
    var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "bubble.left.fill" : "bubble.left")
                .font(BrowserFloatingTypography.tabIcon)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)

            if isExpanded {
                Text(title)
                    .font(isActive ? BrowserFloatingTypography.tabTitleSelected : BrowserFloatingTypography.tabTitle)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(BrowserFloatingTypography.tabTitle)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, isExpanded ? 6 : 8)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .help(title)
        .accessibilityLabel("会话：\(title)，\(count) 个标签页")
    }
}

struct BrowserVerticalTabRow: View {
    var item: BrowserGlobalTabItem
    var isExpanded: Bool
    var isSelected: Bool
    var isPrivate: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if item.tab.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
                    .fixedSize()
            } else {
                Image(systemName: isPrivate ? "hand.raised.fill" : "globe")
                    .font(BrowserFloatingTypography.tabIcon)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
            }

            if isExpanded {
                Text(item.displayTitle)
                    .font(isSelected ? BrowserFloatingTypography.tabTitleSelected : BrowserFloatingTypography.tabTitle)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(BrowserFloatingTypography.tabCloseIcon)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary.opacity(0.72))
                .help("关闭标签页")
            }
        }
        .padding(.horizontal, isExpanded ? 7 : 9)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 18)
                    .padding(.leading, 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: onSelect)
        .help("\(item.sessionTitle)\n\(item.displayTitle)\n\(item.displayURL)")
        .accessibilityLabel("\(item.displayTitle)，会话：\(item.sessionTitle)")
    }

    private var tabBackground: Color {
        isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear
    }
}

struct BrowserDownloadsPanelView: View {
    var items: [BrowserDownloadItem]
    var onClose: () -> Void
    var onCancel: (UUID) -> Void
    var onOpen: (BrowserDownloadItem) -> Void
    var onReveal: (BrowserDownloadItem) -> Void
    var onClearCompleted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppShellLayout.spaceS) {
                Image(systemName: "arrow.down.circle")
                    .font(BrowserFloatingTypography.popoverTitle)
                    .foregroundStyle(.secondary)
                Text("下载")
                    .font(BrowserFloatingTypography.popoverTitle)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.appIcon)
                    .help("关闭下载面板")
            }
            .padding(.horizontal, AppShellLayout.spaceM)
            .padding(.vertical, AppShellLayout.spaceS)
            Divider()

            if items.isEmpty {
                VStack(spacing: AppShellLayout.spaceS) {
                    Spacer()
                    Image(systemName: "arrow.down.doc").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("还没有下载项目").font(BrowserFloatingTypography.hint.weight(.semibold)).foregroundStyle(.secondary)
                    Text("网页下载会显示在这里，并保存到“下载”文件夹。")
                        .font(AppTypography.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(AppShellLayout.spaceL)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            downloadRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("\(items.count) 个项目").font(AppTypography.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("清除已完成", action: onClearCompleted)
                    .buttonStyle(.plain)
                    .font(AppTypography.captionEmphasis)
                    .disabled(!items.contains { $0.status == .finished || $0.status == .failed || $0.status == .cancelled })
            }
            .padding(.horizontal, AppShellLayout.spaceM)
            .padding(.vertical, AppShellLayout.spaceS)
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func downloadRow(_ item: BrowserDownloadItem) -> some View {
        HStack(spacing: AppShellLayout.spaceS) {
            Image(systemName: statusImage(item.status))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusColor(item.status))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.filename).font(BrowserFloatingTypography.pageTitle).lineLimit(1)
                if item.status == .preparing || item.status == .downloading {
                    ProgressView(value: item.progress).controlSize(.small)
                }
                Text(statusText(item))
                    .font(BrowserFloatingTypography.pageURL)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.status == .preparing || item.status == .downloading {
                Button(action: { onCancel(item.id) }) { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain).help("取消下载")
            } else if item.status == .finished {
                Menu {
                    Button("打开", systemImage: "arrow.up.forward.app") { onOpen(item) }
                    Button("在 Finder 中显示", systemImage: "folder") { onReveal(item) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(.horizontal, AppShellLayout.spaceM)
        .padding(.vertical, AppShellLayout.spaceS)
    }

    private func statusImage(_ status: BrowserDownloadStatus) -> String {
        switch status {
        case .preparing, .downloading: "arrow.down"
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private func statusColor(_ status: BrowserDownloadStatus) -> Color {
        switch status {
        case .finished: .green
        case .failed: .red
        default: .secondary
        }
    }

    private func statusText(_ item: BrowserDownloadItem) -> String {
        switch item.status {
        case .preparing: "正在准备…"
        case .downloading: "已完成 \(Int(item.progress * 100))%"
        case .finished: "已保存到下载文件夹"
        case .failed: item.errorMessage ?? "下载失败"
        case .cancelled: "已取消"
        }
    }
}

struct BrowserToolbarIconButtonLabel: View {
    var systemImage: String
    var isActive: Bool = false
    var iconFont: Font = BrowserFloatingTypography.toolbarIcon

    var body: some View {
        Image(systemName: systemImage)
            .font(iconFont)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(width: AppButtonLayout.iconButtonSize, height: AppButtonLayout.iconButtonSize)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.09), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct BrowserAskAIButtonLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(BrowserFloatingTypography.askButtonIcon)
            Text("问一问 AI")
                .font(BrowserFloatingTypography.askButton)
        }
        .foregroundStyle(ConnorCraftPalette.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [ConnorCraftPalette.accent.opacity(0.18), ConnorCraftPalette.accentSubtleFill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(Capsule().stroke(ConnorCraftPalette.accentBorder, lineWidth: 1))
        .shadow(color: ConnorCraftPalette.accent.opacity(0.16), radius: 8, x: 0, y: 3)
        .contentShape(Capsule())
    }
}

struct BrowserLoadingOverlay: View {
    var message: String
    var systemImage: String = "arrow.triangle.2.circlepath"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(BrowserFloatingTypography.loadingOverlay)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}

struct WebNavigationState: Equatable {
    var canGoBack: Bool
    var canGoForward: Bool
    var title: String
    var url: String
    var isLoading: Bool = false
    var errorMessage: String? = nil
}
