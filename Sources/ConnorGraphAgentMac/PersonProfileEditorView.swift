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
public struct PersonProfileEditorPresentation: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var saveButtonTitle: String
    public var displayNameHint: String
    public var canSave: Bool

    public init(draft: PersonProfileDraft) {
        title = draft.id == nil ? "新建人物档案" : "编辑人物档案"
        subtitle = "用于人际关系检索、@人物提及和人物相关记忆归因。人物可以先存在，联系方式后补充。"
        saveButtonTitle = "保存人物档案"
        displayNameHint = "显示名是必填项，用于列表和 @人物提及。"
        canSave = !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

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
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceL) {
            header
            content
            footer
        }
        .padding(SettingsListLayout.spaceXL)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 560)

    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: draft.id == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.badge.checkmark")
                    .font(SettingsListTypography.largeIcon)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text(presentation.title)
                    .font(SettingsListTypography.header)
                Text(presentation.subtitle)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            basicInformationSection
            relationshipContextSection
            contactMethodsSection
            notesSection
        }
    }

    private var basicInformationSection: some View {
        PersonProfileEditorSection(title: "基本信息") {
            PersonProfileEditorField(
                title: "显示名",
                placeholder: "姓名 / 显示名",
                text: $draft.displayName,
                caption: presentation.displayNameHint,
                isRequired: true
            )

            HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
                PersonProfileEditorField(title: "名", placeholder: "名", text: $draft.givenName)
                PersonProfileEditorField(title: "姓", placeholder: "姓", text: $draft.familyName)
            }

            PersonProfileEditorField(
                title: "性别 / 称谓",
                placeholder: "可选，例如：她 / 他 / 老师 / 同事",
                text: optionalText($draft.gender)
            )
        }
    }

    private var relationshipContextSection: some View {
        PersonProfileEditorSection(title: "关系线索") {
            HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
                PersonProfileEditorField(title: "组织", placeholder: "公司、学校或社群", text: optionalText($draft.organizationName))
                PersonProfileEditorField(title: "职位", placeholder: "角色或头衔", text: optionalText($draft.jobTitle))
            }

            PersonProfileEditorField(
                title: "别名",
                placeholder: "多个别名用逗号分隔",
                text: aliasesBinding,
                caption: "用于把不同称呼归并到同一个人物档案。"
            )
        }
    }

    private var contactMethodsSection: some View {
        PersonProfileEditorSection(title: "联系方式") {
            HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
                PersonProfileEditorField(title: "邮箱", placeholder: "name@example.com", text: firstEmailBinding)
                PersonProfileEditorField(title: "电话", placeholder: "+86 138 0000 0000", text: firstPhoneBinding)
            }

            PersonProfileEditorField(title: "地址", placeholder: "地址或地点线索", text: firstAddressBinding)

            Text("当前版本先保存每类联系方式的第一项。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesSection: some View {
        PersonProfileEditorSection(title: "备注") {
            PersonProfileEditorField(
                title: "关系背景与沟通偏好",
                placeholder: "记录关系背景、沟通偏好或重要上下文…",
                text: optionalText($draft.notes),
                axis: .vertical,
                lineLimit: 4...8
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: SettingsListLayout.spaceL) {
            Spacer()
            Button("取消", action: onCancel)
                .buttonStyle(.bordered)
            Button(presentation.saveButtonTitle) { onSave(draft) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.canSave)
                .accessibilityLabel(presentation.saveButtonTitle)
                .help(presentation.canSave ? presentation.saveButtonTitle : presentation.displayNameHint)
        }
        .padding(.top, SettingsListLayout.spaceXS)
    }

    // MARK: - Bindings

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
private struct PersonProfileEditorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Text(title)
                .font(SettingsListTypography.rowTitle)
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
                content
            }
            .padding(SettingsListLayout.spaceL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))

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
private struct PersonProfileEditorField: View {
    var title: String
    var placeholder: String
    @Binding var text: String
    var caption: String?
    var isRequired: Bool = false
    var axis: Axis = .horizontal
    var verticalLineLimit: ClosedRange<Int>?

    init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        caption: String? = nil,
        isRequired: Bool = false,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int>? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        _text = text
        self.caption = caption
        self.isRequired = isRequired
        self.axis = axis
        verticalLineLimit = lineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(title)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                if isRequired {
                    Text("必填")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
            }
            textField
            if let caption {
                Text(caption)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var textField: some View {
        if let verticalLineLimit {
            TextField(placeholder, text: $text, axis: axis)
                .textFieldStyle(.roundedBorder)
                .lineLimit(verticalLineLimit)
                .accessibilityLabel(accessibilityTitle)
        } else {
            TextField(placeholder, text: $text, axis: axis)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(accessibilityTitle)
        }
    }

    private var accessibilityTitle: String {
        isRequired ? "\(title)，必填" : title

    }
}
