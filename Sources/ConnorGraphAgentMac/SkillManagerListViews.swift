import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct CraftSkillListPane: View {
    @Bindable var model: SkillRuntimeFeatureModel

    var body: some View {
        VStack(spacing: 0) {
            SkillListHeader(onAdd: model.presentAddDialog)

            if model.presentation.cards.isEmpty {
                SkillListEmptyState()
            } else {
                SkillListRows(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $model.isAddDialogPresented) {
            AddSkillRequestDialog(model: model)
        }
        .sheet(isPresented: $model.isEditDialogPresented) {
            EditSkillRequestDialog(model: model)
        }
        .modifier(SkillDeleteConfirmationModifier(model: model))
    }
}

private struct SkillListHeader: View {
    var onAdd: () -> Void

    var body: some View {
        AppListPaneHeader(title: "技能") {
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.appIcon)
            .help("添加技能")
            .accessibilityLabel("添加技能")
        }
    }
}

private struct SkillListEmptyState: View {
    var body: some View {
        ContentUnavailableView("暂无技能", systemImage: "sparkles", description: Text("点击右上角 +，添加一个新技能。"))
            .padding(.top, 80)
    }
}

private struct SkillListRows: View {
    @Bindable var model: SkillRuntimeFeatureModel

    var body: some View {
        List(model.presentation.cards) { card in
            CraftSkillRow(
                card: card,
                isSelected: card.id == model.selectedCardID,
                onSelect: { model.selectCard(card.id) },
                onEdit: { model.presentEditDialog(card: card) },
                onDelete: { model.requestDelete(card: card) }
            )
            .nativeListRowStyle()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct SkillDeleteConfirmationModifier: ViewModifier {
    @Bindable var model: SkillRuntimeFeatureModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "删除这个技能？",
            isPresented: Binding(
                get: { model.pendingDeletionCard != nil },
                set: { isPresented in
                    if !isPresented { model.cancelDelete() }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                model.confirmDelete()
            }
            .disabled(model.pendingDeletionCard?.sourceTier != SkillSourceTier.user.rawValue)

            Button("取消", role: .cancel) {
                model.cancelDelete()
            }
        } message: {
            if let card = model.pendingDeletionCard {
                SkillDeleteConfirmationMessage(card: card)
            }
        }
    }
}

private struct SkillDeleteConfirmationMessage: View {
    var card: SkillManagerCard

    var body: some View {
        if card.sourceTier == SkillSourceTier.user.rawValue {
            Text("删除后，\(card.title) 会从技能列表中移除。")
        } else {
            Text("这个技能来自 \(card.sourceTier)，不能在这里删除。只有你添加的技能可以删除。")
        }
    }
}

private struct AddSkillRequestDialog: View {
    @Bindable var model: SkillRuntimeFeatureModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        SkillRequestDialogLayout(
            iconName: "sparkles",
            title: "添加技能",
            description: "告诉康纳你希望新技能帮你完成什么，它会在这里帮你创建。",
            statusMessage: model.addDialogMessage,
            isSubmitting: model.isSubmittingAddRequest,
            isFailure: false,
            textEditor: {
                SkillRequestTextEditor(
                    text: $model.addRequestDraft,
                    placeholder: "例如：帮我审查 PR，重点检查安全、测试和架构一致性。",
                    isFocused: $isFocused
                )
            },
            actions: {
                SkillRequestDialogActions(
                    closeTitle: "关闭",
                    primaryTitle: model.isSubmittingAddRequest ? "创建中…" : "开始创建",
                    isSubmitting: model.isSubmittingAddRequest,
                    isPrimaryDisabled: model.addRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: {
                        model.cancelAddDialog()
                        dismiss()
                    },
                    onSubmit: { Task { await model.submitAddRequest() } }
                )
            }
        )
        .onAppear { isFocused = true }
    }
}

private struct EditSkillRequestDialog: View {
    @Bindable var model: SkillRuntimeFeatureModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var skillTitle: String {
        model.editingCard?.title ?? "这个技能"
    }

    var body: some View {
        SkillRequestDialogLayout(
            iconName: "pencil.and.sparkles",
            title: "编辑技能",
            description: "告诉康纳你想怎样调整“\(skillTitle)”，它会在这里帮你修改。",
            statusMessage: model.editDialogMessage,
            isSubmitting: model.isSubmittingEditRequest,
            isFailure: model.editDialogMessage?.contains("失败") == true,
            textEditor: {
                VStack(alignment: .leading, spacing: 16) {
                    if let card = model.editingCard {
                        SkillEditingMetadataBar(card: card)
                    }
                    SkillRequestTextEditor(
                        text: $model.editRequestDraft,
                        placeholder: "例如：把它改成更关注性能瓶颈，并要求输出检查清单。",
                        isFocused: $isFocused
                    )
                }
            },
            actions: {
                SkillRequestDialogActions(
                    closeTitle: "关闭",
                    primaryTitle: model.isSubmittingEditRequest ? "修改中…" : "提交修改",
                    isSubmitting: model.isSubmittingEditRequest,
                    isPrimaryDisabled: model.editRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: {
                        model.cancelEditDialog()
                        dismiss()
                    },
                    onSubmit: { Task { await model.submitEditRequest() } }
                )
            }
        )
        .onAppear { isFocused = true }
    }
}

private struct SkillRequestDialogLayout<TextEditorContent: View, ActionsContent: View>: View {
    var iconName: String
    var title: String
    var description: String
    var statusMessage: String?
    var isSubmitting: Bool
    var isFailure: Bool
    @ViewBuilder var textEditor: () -> TextEditorContent
    @ViewBuilder var actions: () -> ActionsContent

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
            SkillRequestDialogHeader(iconName: iconName, title: title, description: description)
            textEditor()
            SkillRequestStatusMessage(message: statusMessage, isSubmitting: isSubmitting, isFailure: isFailure)
            actions()
        }
        .padding(AppShellLayout.spaceXL)
        .frame(width: 520)
    }
}

private struct SkillRequestDialogHeader: View {
    var iconName: String
    var title: String
    var description: String

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(title)
                    .font(AppTypography.pageTitle)
                Text(description)
                    .font(AppTypography.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SkillEditingMetadataBar: View {
    var card: SkillManagerCard

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.secondary)
            Text(card.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
            Text(card.sourceTier)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SkillRequestTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        SkillRequestTextView(
            text: $text,
            placeholder: placeholder,
            isFocused: isFocused
        )
        .frame(minHeight: 150)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        )
    }
}

private struct SkillRequestTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.placeholderString = placeholder
        textView.string = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        textView.placeholderString = placeholder
        if textView.string != text {
            textView.string = text
        }
        if isFocused.wrappedValue, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isFocused: FocusState<Bool>.Binding
        weak var textView: PlaceholderTextView?

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding) {
            _text = text
            self.isFocused = isFocused
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            textView.needsDisplay = true
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholderString.draw(
            at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
            withAttributes: attributes
        )
    }
}

private struct SkillRequestStatusMessage: View {
    var message: String?
    var isSubmitting: Bool
    var isFailure: Bool

    var body: some View {
        if let message, !message.isEmpty {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isFailure ? .orange : .green)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct SkillRequestDialogActions: View {
    var closeTitle: String
    var primaryTitle: String
    var isSubmitting: Bool
    var isPrimaryDisabled: Bool
    var onClose: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        HStack {
            Button(closeTitle, action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)

            Spacer()

            Button(primaryTitle, action: onSubmit)
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || isPrimaryDisabled)
        }
    }
}

struct CraftSkillRow: View {
    var card: SkillManagerCard
    var isSelected: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        rowContent
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                }
                .tint(.blue)

                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
                .disabled(card.sourceTier != SkillSourceTier.user.rawValue)
            }
            .contextMenu { contextMenuItems }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: AppListCardLayout.contentPadding) {
            SkillRowIcon(iconName: iconName, accent: skillAccent, isSelected: isSelected)

            VStack(alignment: .leading, spacing: 6) {
                SkillRowTitleLine(card: card, isSelected: isSelected)
                Text(card.subtitle)
                    .font(AppListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                SkillRowBadgeLine(card: card, riskColor: riskColor, trustColor: trustColor)
            }
        }
        .appListRowSurface(isSelected: isSelected)
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: onEdit) {
            Label("编辑", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label("删除", systemImage: "trash")
        }
        .disabled(card.sourceTier != SkillSourceTier.user.rawValue)
    }

    private var iconName: String {
        card.warnings.isEmpty ? "bolt.fill" : "exclamationmark.triangle.fill"
    }

    private var skillAccent: Color {
        if !card.warnings.isEmpty { return .orange }
        if card.riskLabel == "high" || card.riskLabel == "critical" { return .orange }
        return .accentColor
    }

    private var riskColor: Color {
        switch card.riskLabel {
        case "high", "critical": .orange
        case "medium": .blue
        default: .secondary
        }
    }

    private var trustColor: Color {
        switch card.trustState {
        case "projectRequiresTrust", "unknown": .orange
        case "bundledTrusted", "trusted", "userTrusted": .green
        default: .secondary
        }
    }
}

private struct SkillRowIcon: View {
    var iconName: String
    var accent: Color
    var isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent.opacity(isSelected ? 0.20 : 0.12))
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: 24, height: 24)
    }
}

private struct SkillRowTitleLine: View {
    var card: SkillManagerCard
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(card.title)
                .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                .lineLimit(AppListCardLayout.titleLineLimit)
            Spacer(minLength: 4)
            Text(card.sourceTier)
                .font(AppListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SkillRowBadgeLine: View {
    var card: SkillManagerCard
    var riskColor: Color
    var trustColor: Color

    var body: some View {
        HStack(spacing: 5) {
            SkillMiniChip(text: card.riskLabel, color: riskColor)
            SkillMiniChip(text: card.trustState, color: trustColor)
            if !card.requiredSources.isEmpty {
                SkillMiniChip(text: "sources \(card.requiredSources.count)", color: .blue)
            }
        }
    }
}

private struct SkillMiniChip: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(AppListTypography.rowCaption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
