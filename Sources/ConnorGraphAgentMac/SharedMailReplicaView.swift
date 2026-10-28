import SwiftUI
import ConnorGraphAppSupport

struct SharedMailReplicaView: View {
    var messages: [SharedMailMessage]
    @State private var selection: String?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var filtered: [SharedMailMessage] { messages.filter {query.isEmpty || $0.subject.localizedCaseInsensitiveContains(query) || $0.from.localizedCaseInsensitiveContains(query) || $0.mailboxAddress.localizedCaseInsensitiveContains(query)} }
    var body: some View {
        VStack {
            HStack { Text("跨端邮件").font(.headline); Spacer(); Button("关闭") {dismiss()} }.padding()
            Text("只读邮件内容；邮箱配置和附件文件保留在原设备。").font(.caption)
            HSplitView {
                VStack {
                    TextField("搜索主题、发件人或邮箱",text:$query).padding(8)
                    List(filtered) {mail in
                        Button {selection=mail.id} label: {
                            VStack(alignment:.leading) {Text(mail.subject).font(.headline);Text("\(mail.from) · \(mail.mailboxAddress)").font(.caption);Text(mail.snippet).lineLimit(2)}.frame(maxWidth:.infinity,alignment:.leading)
                        }.buttonStyle(.plain)
                    }
                    if filtered.isEmpty {Text("还没有收到跨端邮件。").padding()}
                }.frame(minWidth:260)
                ScrollView {
                    if let mail=messages.first(where:{$0.id==selection}) {
                        VStack(alignment:.leading,spacing:10) {
                            Text(mail.subject).font(.title2)
                            Text("\(mail.from) → \(mail.to.joined(separator:", "))")
                            Text("\(mail.mailboxAddress) · \(mail.folder)").font(.caption)
                            Divider()
                            Text(mail.bodyAvailable ? mail.bodyText : "正文尚未从邮箱设备获取。")
                            if mail.bodyTruncated {Text("源设备保存的正文不完整，后续完整正文将继续同步。")}
                            ForEach(mail.attachments) {a in Text("📎 \(a.fileName) · \(a.mimeType) · \(a.size < 0 ? "大小未知" : "\(a.size) 字节")")}
                            if !mail.attachments.isEmpty {Text("附件仅同步清单，文件需在已配置邮箱的设备下载。").font(.caption)}
                        }.padding().textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    } else {Text("选择一封邮件查看正文和附件清单。").padding()}
                }.frame(minWidth:400)
            }
        }.frame(minWidth:800,minHeight:600)
    }
}
