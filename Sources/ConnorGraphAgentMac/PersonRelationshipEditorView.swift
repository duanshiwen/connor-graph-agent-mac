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
            Text("为 \(sourceDisplayName) 添加结构化人际关系：谁和谁、是什么关系、有没有备注或证据。当前用户不会出现在 @ 人物选择中；如关系目标是你本人，请选择“当前用户”。")
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
                    LabeledContent("目标人物") {
                        Text("我（当前用户）")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("关系类型", selection: $draft.kind) {
                    ForEach(PersonRelationshipKind.allCases, id: \.self) { kind in
                        Text(kind.displayTitle).tag(kind)
                    }
                }

                LabeledContent("关系名称") {
                    TextField(draft.kind == .custom ? "必填，例如 师父、干妈" : "自定义名称，例如 妈妈、师父（不填则用关系类型）", text: $draft.customKindLabel)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("备注") {
                    TextField("关系背景、认识时间地点等（可选）", text: $draft.note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }

                LabeledContent("证据 / 原始表述") {
                    TextField("当初是怎么提到这段关系的，例如“她是我妈妈”（可选）", text: $draft.evidenceText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            HStack {
                if draft.kind == .custom && draft.customKindLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("选择“关系”类型时需要填写关系名称")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.orange)
                }
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
        if draft.targetMode == .personProfile && draft.targetPersonID == nil { return true }
        if draft.kind == .custom && draft.customKindLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
}
