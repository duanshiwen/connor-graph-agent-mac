import SwiftUI
import ConnorGraphCore

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

    private var presentation: PersonProfileEditorPresentation {
        PersonProfileEditorPresentation(draft: draft)
    }

    var body: some View {
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
            get: { draft.aliases.joined(separator: ", ") },
            set: { value in
                draft.aliases = value
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
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
        } else {
            TextField(placeholder, text: $text, axis: axis)
                .textFieldStyle(.roundedBorder)
        }
    }
}
