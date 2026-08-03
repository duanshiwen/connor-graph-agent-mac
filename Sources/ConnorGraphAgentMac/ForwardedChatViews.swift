import SwiftUI
import ConnorGraphCore

enum ForwardDestinationKind: String, Hashable {
    case agent
    case peer
    case group
}

struct ForwardDestination: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var targetID: String
    var title: String
    var subtitle: String
    var kind: ForwardDestinationKind
    var updatedAt: TimeInterval? = nil
}

func forwardDestinations(sessions: [AgentSession], conversations: [ImConversation]) -> [ForwardDestination] {
    let newSession = ForwardDestination(key: "agent:new", targetID: "", title: "新建与康纳的会话", subtitle: "创建后保存聊天记录", kind: .agent)
    var existing = sessions.filter { $0.governance.kind == .chat }.map {
        ForwardDestination(
            key: "agent:\($0.id)",
            targetID: $0.id,
            title: $0.title,
            subtitle: "与康纳的会话",
            kind: .agent,
            updatedAt: $0.updatedAt.timeIntervalSince1970
        )
    }
    existing += conversations.map {
        ForwardDestination(
            key: "im:\($0.id)",
            targetID: $0.id,
            title: $0.title,
            subtitle: $0.kind == .group ? "群聊" : "跟 \($0.participantName)",
            kind: $0.kind == .group ? .group : .peer,
            updatedAt: TimeInterval($0.updatedAt) / 1_000
        )
    }
    return [newSession] + sortForwardDestinationsByRecency(existing)
}

func sortForwardDestinationsByRecency(_ destinations: [ForwardDestination]) -> [ForwardDestination] {
    destinations.sorted {
        if $0.updatedAt == $1.updatedAt { return $0.key < $1.key }
        return ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0)
    }
}

struct ForwardDestinationSheet: View {
    var bundle: ForwardedChatBundle
    var destinations: [ForwardDestination]
    var isSending: Bool
    var onCancel: () -> Void
    var onSend: (String, Set<String>) async -> Void

    @State private var searchText = ""
    @State private var caption = ""
    @State private var selectedKeys: Set<String> = []

    private var visibleDestinations: [ForwardDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return destinations }
        return destinations.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择聊天")
                    .font(.headline)
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                List(visibleDestinations, selection: $selectedKeys) { destination in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: destination.kind))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(destination.kind == .agent ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.title).lineLimit(1)
                            Text(destination.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: selectedKeys.contains(destination.key) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedKeys.contains(destination.key) ? Color.accentColor : Color.secondary.opacity(0.55))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedKeys.contains(destination.key) { selectedKeys.remove(destination.key) }
                        else { selectedKeys.insert(destination.key) }
                    }
                    .tag(destination.key)
                }
                .listStyle(.inset)
            }
            .padding(20)
            .frame(width: 320)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("发送给")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                ForwardedChatCard(bundle: bundle)
                    .frame(maxWidth: 460)
                TextField("给对方留言（可选）", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Spacer()
                    Button("取消", action: onCancel)
                    Button(isSending ? "发送中…" : selectedKeys.count > 1 ? "发送给 \(selectedKeys.count) 个会话" : "发送") {
                        Task { await onSend(caption, selectedKeys) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedKeys.isEmpty || isSending)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 580)
    }

    private func icon(for kind: ForwardDestinationKind) -> String {
        switch kind {
        case .agent: "sparkles"
        case .peer: "person"
        case .group: "person.3"
        }
    }
}

struct ForwardedChatCard: View {
    var bundle: ForwardedChatBundle
    var onOpen: (() -> Void)?

    var body: some View {
        Button(action: { onOpen?() }) {
            VStack(alignment: .leading, spacing: 7) {
                Text(bundle.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                ForEach(Array(bundle.previewLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !bundle.caption.isEmpty {
                    Text(bundle.caption).font(.callout).foregroundStyle(.primary).lineLimit(2)
                }
                Divider().padding(.top, 3)
                Label("聊天记录 · \(bundle.items.count) 条", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
    }
}

struct ForwardedChatDetailView: View {
    var bundle: ForwardedChatBundle
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bundle.title).font(.title3.weight(.semibold))
                    Text("来自 \(bundle.sourceTitle) · \(bundle.items.count) 条").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭", systemImage: "xmark", action: onClose).labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(bundle.items) { item in
                        ForwardedChatDetailItemView(item: item)
                        Divider().padding(.leading, 58)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
    }
}

private struct ForwardedChatDetailItemView: View {
    var item: ForwardedChatItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay(Text(String(item.senderName.prefix(1))).font(.headline))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(item.senderName).font(.callout.weight(.medium))
                    Spacer()
                    Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: Double(item.createdAt) / 1000)))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                content
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder private var content: some View {
        switch item.kind.lowercased() {
        case "image":
            if let value = item.mediaUrl, let url = URL(string: value) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxWidth: 420, maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 6))
            } else { Label("图片", systemImage: "photo") }
        case "video": Label("视频", systemImage: "play.rectangle")
        case "audio": Label("语音", systemImage: "waveform")
        default: Text(item.text).textSelection(.enabled)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.dateStyle = .medium
        value.timeStyle = .short
        return value
    }()
}
