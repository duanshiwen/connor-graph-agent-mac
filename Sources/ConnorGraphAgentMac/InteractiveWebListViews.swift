import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

// MARK: - 互动网页列表 pane

struct CraftInteractiveWebListPane: View {
    @Bindable var model: InteractiveWebFeatureModel
    var forwarding: ListItemForwardingContext

    @State private var pendingForwardBundle: ForwardedChatBundle?
    @State private var isForwardSending = false

    var body: some View {
        VStack(spacing: 0) {
            AppListPaneHeader(title: "互动网页") {
                Button {
                    Task { await model.reloadProjects() }
                } label: {
                    if model.isMutating || isListLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.appIcon)
                .disabled(model.isMutating)
                .help("刷新互动网页列表")
                .accessibilityLabel("刷新互动网页列表")
            }

            switch model.listState {
            case .idle:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { Task { await model.loadProjectsIfNeeded() } }
            case .loading where model.projects.isEmpty:
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text("正在加载互动网页…")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            case .failed(let message):
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .padding(.top, 80)
            default:
                if model.projects.isEmpty {
                    ContentUnavailableView(
                        "还没有互动网页",
                        systemImage: "globe",
                        description: Text("康纳同学生成的互动网页会出现在这里。选中后可在详情页上架、下架、删除，或转发给会话让康纳同学继续修改。")
                    )
                    .padding(.top, 80)
                } else {
                    List(model.projects, id: \.id) { project in
                        InteractiveWebListRow(
                            project: project,
                            isSelected: project.id == model.selectedProjectID,
                            onSelect: { model.select(project) },
                            onForward: { pendingForwardBundle = model.forwardBundle(for: project) },
                            onCopyLink: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(model.siteURL(for: project).absoluteString, forType: .string)
                            }
                        )
                        .nativeListRowStyle()
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 6, for: .scrollContent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $pendingForwardBundle) { bundle in
            ForwardDestinationSheet(
                bundle: bundle,
                pager: forwarding.makePager(),
                isSending: isForwardSending,
                onCancel: { pendingForwardBundle = nil },
                onSend: { caption, keys in
                    var copy = bundle
                    copy.caption = caption
                    isForwardSending = true
                    defer {
                        isForwardSending = false
                        pendingForwardBundle = nil
                    }
                    try? await forwarding.send(copy, keys)
                }
            )
        }
    }

    private var isListLoading: Bool {
        if case .loading = model.listState { return true }
        return false
    }
}

private struct InteractiveWebListRow: View {
    let project: InteractiveWebRemoteProject
    let isSelected: Bool
    let onSelect: () -> Void
    let onForward: () -> Void
    let onCopyLink: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(project.status == "active" ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: AppListCardLayout.contentSpacing) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(AppListCardLayout.titleLineLimit)
                        if project.status == "active" {
                            Text("已上架")
                                .font(AppListTypography.rowCaption)
                                .foregroundStyle(.green)
                        } else {
                            Text("已下架")
                                .font(AppListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("访问权限：\(InteractiveWebAccessModeDisplay(project.accessMode)) · 更新于 \(interactiveWebDisplayTime(project.updatedAt))")
                        .font(AppListTypography.rowCaptionEmphasized)
                        .lineLimit(1)
                    Text(project.siteId)
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Button(action: onCopyLink) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.appIcon)
                    .help("复制链接")
                    Button(action: onForward) {
                        Image(systemName: "paperplane")
                    }
                    .buttonStyle(.appIcon)
                    .help("转发到会话…")
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 互动网页详情 pane

struct InteractiveWebDetailPane: View {
    @Bindable var model: InteractiveWebFeatureModel
    var forwarding: ListItemForwardingContext

    @State private var pendingForwardBundle: ForwardedChatBundle?
    @State private var isForwardSending = false

    var body: some View {
        Group {
            switch model.detailState {
            case .idle:
                ContentUnavailableView(
                    "选择一个互动网页",
                    systemImage: "globe",
                    description: Text("从左侧列表选中一个互动网页查看详情。")
                )
                .padding(.top, 80)
            case .loading:
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text("正在加载互动网页详情…")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            case .failed(let message):
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .padding(.top, 80)
            case .loaded:
                if let detail = model.detail {
                    InteractiveWebDetailContent(
                        model: model,
                        detail: detail,
                        onForward: { pendingForwardBundle = model.forwardBundle(for: detail) }
                    )
                } else {
                    ContentUnavailableView(
                        "选择一个互动网页",
                        systemImage: "globe",
                        description: Text("从左侧列表选中一个互动网页查看详情。")
                    )
                    .padding(.top, 80)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $pendingForwardBundle) { bundle in
            ForwardDestinationSheet(
                bundle: bundle,
                pager: forwarding.makePager(),
                isSending: isForwardSending,
                onCancel: { pendingForwardBundle = nil },
                onSend: { caption, keys in
                    var copy = bundle
                    copy.caption = caption
                    isForwardSending = true
                    defer {
                        isForwardSending = false
                        pendingForwardBundle = nil
                    }
                    try? await forwarding.send(copy, keys)
                }
            )
        }
        .confirmationDialog(
            "删除这个互动网页？",
            isPresented: Binding(
                get: { model.isPresentingDeleteConfirm },
                set: { model.isPresentingDeleteConfirm = $0 }
            )
        ) {
            Button("删除", role: .destructive) {
                Task { await model.deleteSelected() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将不可恢复，包括全部部署、文件与收集到的数据。")
        }
    }
}

private struct InteractiveWebDetailContent: View {
    @Bindable var model: InteractiveWebFeatureModel
    let detail: InteractiveWebRemoteProjectDetail
    let onForward: () -> Void

    private var isActive: Bool { detail.status == "active" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let message = model.noticeMessage {
                    InteractiveWebBanner(text: message, tint: .green)
                }
                if let message = model.errorMessage {
                    InteractiveWebBanner(text: message, tint: .red)
                }

                headerCard
                actionCard
                infoCard
            }
            .padding(20)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(detail.name)
                    .font(.title2.weight(.semibold))
                statusBadge
            }
            HStack(spacing: 6) {
                Image(systemName: "link")
                Text(model.siteURL(for: detail).absoluteString)
                    .font(AppListTypography.rowSubtitle)
                    .textSelection(.enabled)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var statusBadge: some View {
        Text(isActive ? "已上架" : "已下架")
            .font(AppListTypography.rowCaption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (isActive ? Color.green : Color.secondary.opacity(0.3))
                    .opacity(0.18)
            )
            .clipShape(Capsule())
            .foregroundStyle(isActive ? .green : .secondary)
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isActive ? "操作" : "操作", systemImage: "slider.horizontal.3")
                .font(.headline)

            HStack(spacing: 10) {
                Button {
                    Task { await model.toggleOnlineStatus() }
                } label: {
                    Label(isActive ? "下架" : "上架", systemImage: isActive ? "arrow.down.circle" : "arrow.up.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .orange : .green)
                .disabled(model.isMutating)
                .help(isActive ? "下架后用户将无法访问" : "重新上架并恢复访问")

                Button(action: onForward) {
                    Label("转发到会话…", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isMutating)

                Button {
                    model.requestDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(model.isMutating)
            }

            Divider()

            HStack {
                Button {
                    model.openInNewSession()
                } label: {
                    Label("打开互动网页", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMutating)
                .help("新建会话并用会话浏览器查看这个互动网页（审核模式）")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("信息", systemImage: "info.circle")
                .font(.headline)

            InteractiveWebMetaRow(title: "项目 ID", value: detail.id)
            InteractiveWebMetaRow(title: "站点 ID", value: detail.siteId)
            InteractiveWebMetaRow(title: "访问权限", value: InteractiveWebAccessModeDisplay(detail.accessMode))
            InteractiveWebMetaRow(title: "创建时间", value: interactiveWebDisplayTime(detail.createdAt))
            InteractiveWebMetaRow(title: "更新时间", value: interactiveWebDisplayTime(detail.updatedAt))
            if let deploymentID = detail.currentDeploymentId, !deploymentID.isEmpty {
                InteractiveWebMetaRow(title: "当前部署", value: deploymentID)
            }
            InteractiveWebMetaRow(
                title: "资源",
                value: "\(detail.deployments.count) 个部署 · \(detail.files.count) 个文件 · \(detail.collections.count) 个收集"
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct InteractiveWebMetaRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(AppListTypography.rowSubtitle)
                .textSelection(.enabled)
        }
    }
}

private struct InteractiveWebBanner: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tint == .red ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(text)
                .font(AppListTypography.rowSubtitle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(10)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
