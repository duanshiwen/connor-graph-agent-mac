import SwiftUI
import ConnorGraphAppSupport

private struct WorkspaceFileTreeVisibleRow: Identifiable {
    enum Content {
        case node(WorkspaceFileNode)
        case loading
        case empty
        case error(String)
    }

    var id: String
    var depth: Int
    var content: Content
}

struct WorkspaceFileTreePaneView: View {
    @Bindable var model: WorkspaceExplorerFeatureModel
    var sessionID: String?
    var workingDirectoryPath: String
    var onOpenHTMLPreview: (WorkspaceFileNode, WorkspaceExplorerRoot) -> Void
    var onClose: (() -> Void)? = nil

    private var configurationID: String {
        "\(sessionID ?? "")|\(workingDirectoryPath)"
    }

    var body: some View {
        VStack(spacing: 0) {
            AppListPaneHeader(title: "工作区目录树") {
                Button(action: model.collapseAll) {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .buttonStyle(.appIcon)
                .disabled(model.expandedNodeIDs.isEmpty)
                .help("折叠全部")
                .accessibilityLabel("折叠全部目录")

                Button(action: model.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.appIcon)
                .disabled(model.roots.isEmpty)
                .help("刷新文件树")
                .accessibilityLabel("刷新文件树")

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.appIcon)
                    .help("关闭文件树")
                    .accessibilityLabel("关闭文件树")
                }
            }

            if model.roots.isEmpty {
                ContentUnavailableView(
                    "尚未选择工作目录",
                    systemImage: "folder.badge.questionmark",
                    description: Text("从输入框下方的文件夹菜单选择当前会话工作目录。")
                )
                .padding(.horizontal, AppShellLayout.spaceM)
                .padding(.top, 64)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.roots) { root in
                            rootRow(root)
                            if model.expandedNodeIDs.contains(root.nodeID) {
                                ForEach(visibleRows(parentID: root.nodeID, depth: 1)) { row in
                                    visibleRow(row)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppShellLayout.spaceS)
                    .padding(.vertical, AppShellLayout.spaceS)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: configurationID) {
            model.configure(sessionID: sessionID, workingDirectoryPath: workingDirectoryPath)
        }
    }

    private func rootRow(_ root: WorkspaceExplorerRoot) -> some View {
        Button(action: { model.toggleRoot(root) }) {
            HStack(spacing: 6) {
                disclosureIcon(isExpanded: model.expandedNodeIDs.contains(root.nodeID))
                Image(systemName: model.expandedNodeIDs.contains(root.nodeID) ? "folder.fill" : "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(root.displayName)
                    .font(AppListTypography.rowTitleSelected)
                    .lineLimit(1)
                if root.isPrimary {
                    Image(systemName: "star.fill")
                        .font(AppTypography.micro)
                        .foregroundStyle(.secondary)
                        .help("主工作目录")
                }
                Spacer(minLength: 0)
            }
            .workspaceTreeRowSurface(isSelected: false, depth: 0)
        }
        .buttonStyle(.plain)
        .help(root.url.path)
    }

    @ViewBuilder
    private func visibleRow(_ row: WorkspaceFileTreeVisibleRow) -> some View {
        switch row.content {
        case .loading:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("正在读取...").font(AppTypography.caption).foregroundStyle(.secondary)
            }
            .workspaceTreeRowSurface(isSelected: false, depth: row.depth)
        case .error(let error):
            Label(error, systemImage: "exclamationmark.triangle")
                .font(AppTypography.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .workspaceTreeRowSurface(isSelected: false, depth: row.depth)
        case .empty:
            Text("空文件夹")
                .font(AppTypography.caption)
                .foregroundStyle(.tertiary)
                .workspaceTreeRowSurface(isSelected: false, depth: row.depth)
        case .node(let node):
            nodeRow(node, depth: row.depth)
        }
    }

    private func visibleRows(parentID: String, depth: Int) -> [WorkspaceFileTreeVisibleRow] {
        if model.loadingNodeIDs.contains(parentID) {
            return [.init(id: "\(parentID):loading", depth: depth, content: .loading)]
        }
        if let error = model.errorsByNodeID[parentID] {
            return [.init(id: "\(parentID):error", depth: depth, content: .error(error))]
        }
        guard let children = model.childrenByNodeID[parentID] else { return [] }
        if children.isEmpty {
            return [.init(id: "\(parentID):empty", depth: depth, content: .empty)]
        }
        var rows: [WorkspaceFileTreeVisibleRow] = []
        for node in children {
            rows.append(.init(id: node.id, depth: depth, content: .node(node)))
            if node.isExpandable, model.expandedNodeIDs.contains(node.id) {
                rows.append(contentsOf: visibleRows(parentID: node.id, depth: depth + 1))
            }
        }
        return rows
    }

    private func nodeRow(_ node: WorkspaceFileNode, depth: Int) -> some View {
        Button(action: { model.activateNode(node, openHTMLPreview: onOpenHTMLPreview) }) {
            HStack(spacing: 6) {
                if node.isExpandable {
                    disclosureIcon(isExpanded: model.expandedNodeIDs.contains(node.id))
                } else {
                    Color.clear.frame(width: 12, height: 12)
                }
                Image(systemName: iconName(for: node))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(node.name)
                    .font(AppListTypography.rowTitle)
                    .lineLimit(1)
                    .foregroundStyle(node.isHidden ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .workspaceTreeRowSurface(isSelected: model.selectedNodeID == node.id, depth: depth)
        }
        .buttonStyle(.plain)
        .help(node.relativePath)
        .accessibilityLabel(node.name)
    }

    private func disclosureIcon(isExpanded: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 12, height: 12)
            .foregroundStyle(.secondary)
    }

    private func iconName(for node: WorkspaceFileNode) -> String {
        switch node.kind {
        case .directory: model.expandedNodeIDs.contains(node.id) ? "folder.fill" : "folder"
        case .package: "shippingbox"
        case .symbolicLink: "arrow.triangle.turn.up.right.diamond"
        case .file: fileIcon(forExtension: node.url.pathExtension.lowercased())
        }
    }

    private func fileIcon(forExtension extensionName: String) -> String {
        switch extensionName {
        case "html", "htm": "globe"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg": "photo"
        case "pdf": "doc.richtext"
        case "md", "markdown", "txt", "rtf": "doc.text"
        case "swift", "m", "mm", "h", "js", "ts", "tsx", "jsx", "py", "rs", "go", "java", "kt", "c", "cpp": "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "plist": "curlybraces"
        case "csv", "xls", "xlsx", "numbers": "tablecells"
        case "doc", "docx", "pages": "doc"
        case "ppt", "pptx", "key": "rectangle.on.rectangle"
        case "zip", "tar", "gz", "rar", "7z": "archivebox"
        default: "doc"
        }
    }
}

struct WorkspaceFileTreeOverlay: View {
    @Bindable var model: WorkspaceExplorerFeatureModel
    var sessionID: String?
    var workingDirectoryPath: String
    var onOpenHTMLPreview: (WorkspaceFileNode, WorkspaceExplorerRoot) -> Void
    var onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                WorkspaceFileTreePaneView(
                    model: model,
                    sessionID: sessionID,
                    workingDirectoryPath: workingDirectoryPath,
                    onOpenHTMLPreview: onOpenHTMLPreview,
                    onClose: onClose
                )
                .frame(
                    width: min(420, max(300, proxy.size.width - 24)),
                    height: max(300, proxy.size.height - 24)
                )
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                        .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
                .padding(.vertical, 12)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    func workspaceTreeRowSurface(isSelected: Bool, depth: Int) -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .padding(.leading, CGFloat(depth) * 14 + 5)
            .padding(.trailing, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(Rectangle())
    }
}
