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
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "globe")
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
        .help(url)
    }

    private var tabBackground: Color { isSelected ? Color(nsColor: .controlBackgroundColor) : Color.secondary.opacity(0.045) }
    private var tabBorder: Color { isSelected ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.07) }
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
