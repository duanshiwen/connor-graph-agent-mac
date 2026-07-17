import SwiftUI
import ConnorGraphCore

struct PersonProfileEditorPresentation: Equatable {
    var isEditing: Bool
    var title: String
    var subtitle: String
    var canSave: Bool
    var footerHint: String
    var closeAccessibilityLabel: String
    var cancelAccessibilityLabel: String
    var saveAccessibilityLabel: String
    var saveHelp: String

    init(draft: PersonProfileDraft) {
        isEditing = draft.id != nil
        title = isEditing ? "编辑人物" : "新建人物"
        subtitle = "人物可以没有邮箱或电话；这里记录的是 Person Registry 中的稳定人物档案。"
        canSave = !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        footerHint = canSave ? "按 ⏎ 保存，按 Esc 取消。" : "请输入显示名后保存。"
        closeAccessibilityLabel = isEditing ? "关闭编辑人物表单" : "关闭新建人物表单"
        cancelAccessibilityLabel = isEditing ? "取消编辑人物" : "取消新建人物"
        saveAccessibilityLabel = isEditing ? "保存人物修改" : "保存新建人物"
        saveHelp = canSave ? "保存人物档案" : "请输入显示名后才能保存"
    }
}

enum PersonProfileEditorDraftFormatting {
    static func parseAliases(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func aliasesText(_ aliases: [String]) -> String {
        aliases.joined(separator: ", ")
    }
}

struct PersonProfileEditorView: View {
    @Binding var draft: PersonProfileDraft
    var onCancel: () -> Void
    var onSave: (PersonProfileDraft) -> Void

    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case displayName
    }

    private var presentation: PersonProfileEditorPresentation {
        PersonProfileEditorPresentation(draft: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dialogHeader

            Divider()
                .padding(.top, AppShellLayout.spaceL)

            ScrollView {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                    identitySection
                    contactSection
                    notesSection
                }
                .padding(.vertical, AppShellLayout.spaceL)
            }
            .scrollIndicators(.visible)

            Divider()

            dialogFooter
        }
        .padding(AppShellLayout.spaceXL)
        .frame(width: 640, height: 680)
        .onAppear {
            if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focusedField = .displayName
            }
        }
    }

    private var dialogHeader: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: presentation.isEditing ? "person.crop.circle" : "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(presentation.title)
                    .font(AppTypography.pageTitle)
                Text(presentation.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppShellLayout.spaceM)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: SettingsListLayout.iconButtonSize, height: SettingsListLayout.iconButtonSize)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
            .accessibilityLabel(presentation.closeAccessibilityLabel)
        }
    }

    private var identitySection: some View {
        PersonProfileDialogSection(title: "身份信息", systemImage: "person.text.rectangle") {
            PersonProfileDialogRow("显示名", required: true) {
                TextField("例如：张霞", text: $draft.displayName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .displayName)
                    .accessibilityLabel("显示名，必填")
                    .help("输入人物在 Person Registry 中显示的主要名称")
            }
            PersonProfileDialogRow("名") {
                TextField("例如：霞", text: $draft.givenName)
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogRow("姓") {
                TextField("例如：张", text: $draft.familyName)
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogRow("性别 / 称谓") {
                TextField("可选", text: optionalText($draft.gender))
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogHint("显示名是 Person Registry 的主要识别名称；名和姓可留空。")
        }
    }

    private var contactSection: some View {
        PersonProfileDialogSection(title: "联系方式", systemImage: "at") {
            PersonProfileDialogRow("邮箱") {
                TextField("name@example.com", text: firstEmailBinding)
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogRow("电话") {
                TextField("可选", text: firstPhoneBinding)
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogRow("地址", alignment: .top) {
                TextField("可选", text: firstAddressBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            PersonProfileDialogRow("组织") {
                TextField("可选", text: optionalText($draft.organizationName))
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogRow("职位") {
                TextField("可选", text: optionalText($draft.jobTitle))
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogHint("这些字段都是可选的；人物可以只作为关系或记忆中的独立人物存在。")
        }
    }

    private var notesSection: some View {
        PersonProfileDialogSection(title: "语义与备注", systemImage: "text.quote") {
            PersonProfileDialogRow("别名") {
                TextField("妈妈, 张阿姨", text: aliasesBinding)
                    .textFieldStyle(.roundedBorder)
            }
            PersonProfileDialogRow("备注", alignment: .top) {
                TextField("可记录关系背景、来源、记忆提示等", text: optionalText($draft.notes), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
        }
    }

    private var dialogFooter: some View {
        HStack(alignment: .center, spacing: AppShellLayout.spaceM) {
            Text(presentation.footerHint)
                .font(AgentChatTypography.meta)
                .foregroundStyle(presentation.canSave ? .secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppShellLayout.spaceL)

            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(presentation.cancelAccessibilityLabel)
                .help("放弃更改并关闭")
            Button("保存") { onSave(draft) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.canSave)
                .accessibilityLabel(presentation.saveAccessibilityLabel)
                .help(presentation.saveHelp)
        }
        .padding(.top, AppShellLayout.spaceM)
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private var aliasesBinding: Binding<String> {
        Binding(
            get: { PersonProfileEditorDraftFormatting.aliasesText(draft.aliases) },
            set: { value in
                draft.aliases = PersonProfileEditorDraftFormatting.parseAliases(value)
            }
        )
    }

    private var firstEmailBinding: Binding<String> {
        Binding(
            get: { draft.emails.first?.email ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.emails = trimmed.isEmpty ? [] : [ContactEmailAddress(label: "primary", email: trimmed)]
            }
        )
    }

    private var firstPhoneBinding: Binding<String> {
        Binding(
            get: { draft.phones.first?.number ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.phones = trimmed.isEmpty ? [] : [PersonPhoneNumber(label: "primary", number: trimmed)]
            }
        )
    }

    private var firstAddressBinding: Binding<String> {
        Binding(
            get: { draft.addresses.first?.value ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.addresses = trimmed.isEmpty ? [] : [PersonPostalAddress(label: "primary", value: trimmed)]
            }
        )
    }
}

private struct PersonProfileDialogSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: AppShellLayout.spaceS) {
                content
            }
            .padding(AppShellLayout.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                    .stroke(AppShellColors.hairline, lineWidth: 1)
            }
        }
    }
}

private struct PersonProfileDialogRow<Content: View>: View {
    var title: String
    var required: Bool
    var alignment: VerticalAlignment
    @ViewBuilder var content: Content

    init(_ title: String, required: Bool = false, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder content: () -> Content) {
        self.title = title
        self.required = required
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: AppShellLayout.spaceM) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(title)
                if required {
                    Text("必填")
                        .font(AgentChatTypography.microEmphasis)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 116, alignment: .trailing)
            .accessibilityElement(children: .combine)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: SettingsListLayout.compactRowMinHeight)
    }
}

private struct PersonProfileDialogHint: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(AgentChatTypography.meta)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 116 + AppShellLayout.spaceM)
    }
}
