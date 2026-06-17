import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct CraftSkillListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            SkillListHeader(onAdd: viewModel.presentAddSkillDialog)

            if viewModel.commercialSkillManagerPresentation.cards.isEmpty {
                SkillListEmptyState()
            } else {
                SkillListRows(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $viewModel.isAddSkillDialogPresented) {
            AddSkillRequestDialog(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isEditSkillDialogPresented) {
            EditSkillRequestDialog(viewModel: viewModel)
        }
        .modifier(SkillDeleteConfirmationModifier(viewModel: viewModel))
        .task { viewModel.reloadSkillRuntimeDefinitions() }
    }
}

private struct SkillListHeader: View {
    var onAdd: () -> Void

    var body: some View {
        ZStack {
            Text("技能")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("添加技能")
                .accessibilityLabel("添加技能")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct SkillListEmptyState: View {
    var body: some View {
        ContentUnavailableView("暂无技能", systemImage: "sparkles", description: Text("点击右上角 +，添加一个新技能。"))
            .padding(.top, 80)
    }
}

private struct SkillListRows: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(viewModel.commercialSkillManagerPresentation.cards) { card in
            CraftSkillRow(
                card: card,
                isSelected: card.id == viewModel.selectedSkillManagerCardID,
                onSelect: { viewModel.selectSkillManagerCard(card.id) },
                onEdit: { viewModel.presentEditSkillDialog(card: card) },
                onDelete: { viewModel.requestDeleteSkill(card: card) }
            )
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct SkillDeleteConfirmationModifier: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "删除这个技能？",
            isPresented: Binding(
                get: { viewModel.pendingSkillDeletionCard != nil },
                set: { isPresented in
                    if !isPresented { viewModel.cancelDeleteSkill() }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                viewModel.confirmDeletePendingSkill()
            }
            .disabled(viewModel.pendingSkillDeletionCard?.sourceTier != SkillSourceTier.user.rawValue)

            Button("取消", role: .cancel) {
                viewModel.cancelDeleteSkill()
            }
        } message: {
            if let card = viewModel.pendingSkillDeletionCard {
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
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        SkillRequestDialogLayout(
            iconName: "sparkles",
            title: "添加技能",
            description: "告诉康纳你希望新技能帮你完成什么，它会在这里帮你创建。",
            statusMessage: viewModel.addSkillDialogMessage,
            isSubmitting: viewModel.isSubmittingAddSkillRequest,
            isFailure: false,
            textEditor: {
                SkillRequestTextEditor(
                    text: $viewModel.addSkillRequestDraft,
                    placeholder: "例如：帮我审查 PR，重点检查安全、测试和架构一致性。",
                    isFocused: $isFocused
                )
            },
            actions: {
                SkillRequestDialogActions(
                    closeTitle: "关闭",
                    primaryTitle: viewModel.isSubmittingAddSkillRequest ? "创建中…" : "开始创建",
                    isSubmitting: viewModel.isSubmittingAddSkillRequest,
                    isPrimaryDisabled: viewModel.addSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: {
                        viewModel.cancelAddSkillDialog()
                        dismiss()
                    },
                    onSubmit: { Task { await viewModel.submitAddSkillRequest() } }
                )
            }
        )
        .onAppear { isFocused = true }
    }
}

private struct EditSkillRequestDialog: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var skillTitle: String {
        viewModel.editingSkillCard?.title ?? "这个技能"
    }

    var body: some View {
        SkillRequestDialogLayout(
            iconName: "pencil.and.sparkles",
            title: "编辑技能",
            description: "告诉康纳你想怎样调整“\(skillTitle)”，它会在这里帮你修改。",
            statusMessage: viewModel.editSkillDialogMessage,
            isSubmitting: viewModel.isSubmittingEditSkillRequest,
            isFailure: viewModel.editSkillDialogMessage?.contains("失败") == true,
            textEditor: {
                VStack(alignment: .leading, spacing: 16) {
                    if let card = viewModel.editingSkillCard {
                        SkillEditingMetadataBar(card: card)
                    }
                    SkillRequestTextEditor(
                        text: $viewModel.editSkillRequestDraft,
                        placeholder: "例如：把它改成更关注性能瓶颈，并要求输出检查清单。",
                        isFocused: $isFocused
                    )
                }
            },
            actions: {
                SkillRequestDialogActions(
                    closeTitle: "关闭",
                    primaryTitle: viewModel.isSubmittingEditSkillRequest ? "修改中…" : "提交修改",
                    isSubmitting: viewModel.isSubmittingEditSkillRequest,
                    isPrimaryDisabled: viewModel.editSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: {
                        viewModel.cancelEditSkillDialog()
                        dismiss()
                    },
                    onSubmit: { Task { await viewModel.submitEditSkillRequest() } }
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
        VStack(alignment: .leading, spacing: 16) {
            SkillRequestDialogHeader(iconName: iconName, title: title, description: description)
            textEditor()
            SkillRequestStatusMessage(message: statusMessage, isSubmitting: isSubmitting, isFailure: isFailure)
            actions()
        }
        .padding(22)
        .frame(width: 520)
    }
}

private struct SkillRequestDialogHeader: View {
    var iconName: String
    var title: String
    var description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(description)
                    .font(.callout)
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
        TextEditor(text: $text)
            .font(.body)
            .focused(isFocused)
            .frame(minHeight: 150)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
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
        HStack(alignment: .top, spacing: 10) {
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var rowBackgroundColor: Color {
        isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor)
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
                .lineLimit(1)
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
