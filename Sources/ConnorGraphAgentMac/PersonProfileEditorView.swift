import SwiftUI
import ConnorGraphCore

struct PersonProfileEditorView: View {
    @Binding var draft: PersonProfileDraft
    var onCancel: () -> Void
    var onSave: (PersonProfileDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.id == nil ? "新建人物" : "编辑人物")
                .font(.title2.weight(.semibold))

            Form {
                TextField("姓名 / 显示名", text: $draft.displayName)
                TextField("名", text: $draft.givenName)
                TextField("姓", text: $draft.familyName)
                TextField("性别 / 称谓（可选）", text: optionalText($draft.gender))
                TextField("组织", text: optionalText($draft.organizationName))
                TextField("职位", text: optionalText($draft.jobTitle))
                TextField("邮箱（第一项）", text: firstEmailBinding)
                TextField("电话（第一项）", text: firstPhoneBinding)
                TextField("地址（第一项）", text: firstAddressBinding)
                TextField("备注", text: optionalText($draft.notes), axis: .vertical)
                    .lineLimit(3...6)
                TextField("别名，用逗号分隔", text: aliasesBinding)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 560)
    }

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
