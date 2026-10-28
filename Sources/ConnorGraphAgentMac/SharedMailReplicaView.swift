import SwiftUI
import ConnorGraphAppSupport

/// Uses the same selection and detail column as locally cached mail.
struct SharedMailMessageDetailView: View {
    var message: SharedMailMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.subject.isEmpty ? "无主题" : message.subject).font(.title2)
                Text("\(message.from) → \(message.to.joined(separator: ", "))")
                Text("\(message.mailboxAddress) · \(message.folder)").font(.caption).foregroundStyle(.secondary)
                Text(Date(timeIntervalSince1970: Double(message.sentAt) / 1_000).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(message.bodyAvailable ? message.bodyText : "正文尚未从邮箱设备获取。")
                if message.bodyTruncated { Text("源设备保存的正文不完整，后续完整正文将继续同步。") }
                ForEach(message.attachments) { attachment in
                    Text("📎 \(attachment.fileName) · \(attachment.mimeType) · \(attachment.size < 0 ? "大小未知" : "\(attachment.size) 字节")")
                }
                Text("本机未缓存此邮件；回复、修改已读状态和下载附件需要在已配置邮箱的设备操作。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding().textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
