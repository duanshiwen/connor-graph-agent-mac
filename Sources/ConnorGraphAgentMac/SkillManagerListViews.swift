import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct CraftSkillListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("技能")
                    .font(AppListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Spacer()
                    Button(action: viewModel.presentAddSkillDialog) {
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

            if viewModel.commercialSkillManagerPresentation.cards.isEmpty {
                ContentUnavailableView("暂无技能", systemImage: "sparkles", description: Text("点击右上角 +，添加一个新技能。"))
                    .padding(.top, 80)
            } else {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $viewModel.isAddSkillDialogPresented) {
            AddSkillRequestDialog(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isEditSkillDialogPresented) {
            EditSkillRequestDialog(viewModel: viewModel)
        }
        .confirmationDialog(
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
                if card.sourceTier == SkillSourceTier.user.rawValue {
                    Text("删除后，\(card.title) 会从技能列表中移除。")
                } else {
                    Text("这个技能来自 \(card.sourceTier)，不能在这里删除。只有你添加的技能可以删除。")
                }
            }
        }
        .task { viewModel.reloadSkillRuntimeDefinitions() }
    }
}

private struct AddSkillRequestDialog: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("添加技能")
                        .font(.title3.weight(.semibold))
                    Text("告诉康纳你希望新技能帮你完成什么，它会在这里帮你创建。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextEditor(text: $viewModel.addSkillRequestDraft)
                .font(.body)
                .focused($isFocused)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.addSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("例如：帮我审查 PR，重点检查安全、测试和架构一致性。")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            if let message = viewModel.addSkillDialogMessage, !message.isEmpty {
                HStack(spacing: 8) {
                    if viewModel.isSubmittingAddSkillRequest {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
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

            HStack {
                Button("关闭") {
                    viewModel.cancelAddSkillDialog()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isSubmittingAddSkillRequest)

                Spacer()

                Button(viewModel.isSubmittingAddSkillRequest ? "创建中…" : "开始创建") {
                    Task { await viewModel.submitAddSkillRequest() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSubmittingAddSkillRequest || viewModel.addSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "pencil.and.sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("编辑技能")
                        .font(.title3.weight(.semibold))
                    Text("告诉康纳你想怎样调整“\(skillTitle)”，它会在这里帮你修改。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let card = viewModel.editingSkillCard {
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

            TextEditor(text: $viewModel.editSkillRequestDraft)
                .font(.body)
                .focused($isFocused)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.editSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("例如：把它改成更关注性能瓶颈，并要求输出检查清单。")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            if let message = viewModel.editSkillDialogMessage, !message.isEmpty {
                HStack(spacing: 8) {
                    if viewModel.isSubmittingEditSkillRequest {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: message.contains("失败") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(message.contains("失败") ? .orange : .green)
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

            HStack {
                Button("关闭") {
                    viewModel.cancelEditSkillDialog()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isSubmittingEditSkillRequest)

                Spacer()

                Button(viewModel.isSubmittingEditSkillRequest ? "修改中…" : "提交修改") {
                    Task { await viewModel.submitEditSkillRequest() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSubmittingEditSkillRequest || viewModel.editSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { isFocused = true }
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
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(skillAccent.opacity(isSelected ? 0.20 : 0.12))
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(skillAccent)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(card.sourceTier)
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                Text(card.subtitle)
                    .font(AppListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    SkillMiniChip(text: card.riskLabel, color: riskColor)
                    SkillMiniChip(text: card.trustState, color: trustColor)
                    if !card.requiredSources.isEmpty {
                        SkillMiniChip(text: "sources \(card.requiredSources.count)", color: .blue)
                    }
                }
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
