import SwiftUI
import ConnorGraphCore

struct PersonRelationshipEditorView: View {
    @Binding var draft: PersonRelationshipDraft
    var sourceDisplayName: String
    var candidateProfiles: [PersonProfile]
    var onCancel: () -> Void
    var onSave: (PersonRelationshipDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加关系")
                .font(AppTypography.pageTitle)
            Text("为 \(sourceDisplayName) 添加结构化人际关系。当前用户不会出现在 @ 人物选择中；如关系目标是你本人，请选择“当前用户”。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("目标类型", selection: $draft.targetMode) {
                    ForEach(PersonRelationshipTargetMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if draft.targetMode == .personProfile {
                    Picker("目标人物", selection: targetPersonBinding) {
                        Text("请选择").tag(Optional<ContactID>.none)
                        ForEach(candidateProfiles.filter { $0.id != draft.sourcePersonID }) { profile in
                            Text(profile.displayName).tag(Optional(profile.id))
                        }
                    }
                } else {
                    Text("目标：我（当前用户）")
                        .foregroundStyle(.secondary)
                }

                Picker("关系类型", selection: $draft.kind) {
                    ForEach(PersonRelationshipKind.allCases, id: \.self) { kind in
                        Text(kind.displayTitle).tag(kind)
                    }
                }

                TextField("显示标签（例如：妈妈、同事、朋友）", text: $draft.customKindLabel)
                TextField("备注", text: $draft.note, axis: .vertical)
                    .lineLimit(2...4)
                TextField("证据 / 原始表述", text: $draft.evidenceText, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 520)
    }

    private var targetPersonBinding: Binding<ContactID?> {
        Binding(
            get: { draft.targetPersonID },
            set: { draft.targetPersonID = $0 }
        )
    }

    private var saveDisabled: Bool {
        draft.targetMode == .personProfile && draft.targetPersonID == nil
    }
}
