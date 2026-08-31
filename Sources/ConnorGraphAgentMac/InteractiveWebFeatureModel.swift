import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

/// 互动网页工作区：分页列表 + 详情 + 上架/下架 + 删除 + 转发 + 打开（新会话浏览器审核）。
/// 列表与详情数据来自后端 InteractiveWebAPIClient；「打开互动网页」由组合根注入
/// onOpenInNewSession，走「新建会话 + 会话浏览器查看」的审核流程。
@MainActor
@Observable
final class InteractiveWebFeatureModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var projects: [InteractiveWebRemoteProject] = []
    var listState: LoadState = .idle
    var selectedProjectID: String?
    var detail: InteractiveWebRemoteProjectDetail?
    var detailState: LoadState = .idle
    var isMutating = false
    var isPresentingDeleteConfirm = false
    var noticeMessage: String?
    var errorMessage: String?

    /// 组合根注入：在新建会话里用聊天浏览器打开互动网页（title 已含「审核互动网页：」前缀）。
    @ObservationIgnored var onOpenInNewSession: ((URL, String) -> Void)?

    private let client: InteractiveWebAPIClient

    init(client: InteractiveWebAPIClient) {
        self.client = client
    }

    // MARK: - 列表

    func loadProjectsIfNeeded() async {
        guard case .idle = listState else { return }
        await reloadProjects()
    }

    func reloadProjects() async {
        listState = .loading
        do {
            projects = try await client.projects(limit: 100, page: 1)
            listState = .loaded
        } catch {
            listState = .failed(String(describing: error))
            errorMessage = "加载互动网页列表失败：\(error.localizedDescription)"
        }
    }

    func select(_ project: InteractiveWebRemoteProject) {
        selectedProjectID = project.id
        Task { await loadDetail() }
    }

    func reloadSelected() {
        Task { await loadDetail() }
    }

    func clearSelection() {
        selectedProjectID = nil
        detail = nil
        detailState = .loaded
    }

    private func loadDetail() async {
        guard let id = selectedProjectID else { return }
        detailState = .loading
        do {
            detail = try await client.project(id: id)
            detailState = .loaded
        } catch {
            detailState = .failed(String(describing: error))
            errorMessage = "加载互动网页详情失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 上架 / 下架

    func toggleOnlineStatus() async {
        guard let detail else { return }
        let isActive = detail.status == "active"
        isMutating = true
        defer { isMutating = false }
        do {
            if isActive {
                try await client.offline(siteID: detail.siteId)
                noticeMessage = "已下架「\(detail.name)」"
            } else {
                try await client.online(siteID: detail.siteId)
                noticeMessage = "已上架「\(detail.name)」"
            }
            await loadDetail()
            await reloadProjects()
        } catch {
            errorMessage = "\(isActive ? "下架" : "上架")失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 删除

    func requestDelete() {
        guard detail != nil else { return }
        isPresentingDeleteConfirm = true
    }

    func deleteSelected() async {
        guard let detail else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.deleteProject(projectID: detail.id)
            isPresentingDeleteConfirm = false
            noticeMessage = "已删除「\(detail.name)」"
            selectedProjectID = nil
            self.detail = nil
            detailState = .loaded
            await reloadProjects()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 打开 / 转发

    func siteURL(for project: InteractiveWebRemoteProject) -> URL {
        client.publicSiteURL(siteID: project.siteId)
    }

    func siteURL(for detail: InteractiveWebRemoteProjectDetail) -> URL {
        client.publicSiteURL(siteID: detail.siteId)
    }

    /// 详情页「打开互动网页」：新建会话 + 会话浏览器查看（审核）。
    func openInNewSession() {
        guard let detail else { return }
        onOpenInNewSession?(siteURL(for: detail), "审核互动网页：\(detail.name)")
    }

    func forwardBundle(for project: InteractiveWebRemoteProject) -> ForwardedChatBundle {
        makeForwardBundle(
            id: project.id,
            name: project.name,
            siteId: project.siteId,
            status: project.status,
            accessMode: project.accessMode,
            deploymentID: project.currentDeploymentId,
            updatedAt: project.updatedAt
        )
    }

    func forwardBundle(for detail: InteractiveWebRemoteProjectDetail) -> ForwardedChatBundle {
        makeForwardBundle(
            id: detail.id,
            name: detail.name,
            siteId: detail.siteId,
            status: detail.status,
            accessMode: detail.accessMode,
            deploymentID: detail.currentDeploymentId,
            updatedAt: detail.updatedAt
        )
    }

    private func makeForwardBundle(
        id: String,
        name: String,
        siteId: String,
        status: String,
        accessMode: String,
        deploymentID: String?,
        updatedAt: String
    ) -> ForwardedChatBundle {
        let isActive = status == "active"
        var body = "这是康纳同学生成的互动网页，请帮助检查或修改它。\n名称：\(name)"
        body += "\n状态：\(isActive ? "已上架" : "已下架")"
        body += "\n访问权限：\(InteractiveWebAccessModeDisplay(accessMode))"
        if let deploymentID, !deploymentID.isEmpty {
            body += "\n当前部署：\(deploymentID)"
        }
        body += "\n链接：\(client.publicSiteURL(siteID: siteId).absoluteString)"
        body += "\n\n如果要修改这个互动网页，请用「互动网页」工具读取并修改它。"
        return ForwardedChatBundle(
            title: "互动网页：\(name)",
            sourceTitle: "互动网页 · \(interactiveWebDisplayTime(updatedAt))",
            items: [
                ForwardedChatItem(
                    id: id,
                    senderName: "互动网页",
                    createdAt: interactiveWebEpochMillis(updatedAt),
                    text: body
                )
            ]
        )
    }
}

// MARK: - 展示辅助

/// 访问权限的中文展示。
func InteractiveWebAccessModeDisplay(_ raw: String) -> String {
    switch raw {
    case "public": return "公开"
    case "password": return "密码访问"
    case "private": return "仅本人"
    default: return raw
    }
}

/// RFC3339 时间串 → 展示文本（解析失败退回原串）。
@MainActor
func interactiveWebDisplayTime(_ raw: String) -> String {
    guard let date = interactiveWebDate(from: raw) else { return raw }
    return date.formatted(date: .abbreviated, time: .shortened)
}

/// RFC3339 时间串 → epoch 毫秒（转发载荷用；解析失败退回 0）。
@MainActor
func interactiveWebEpochMillis(_ raw: String) -> Int64 {
    guard let date = interactiveWebDate(from: raw) else { return 0 }
    return Int64(date.timeIntervalSince1970 * 1000)
}

@MainActor
private func interactiveWebDate(from raw: String) -> Date? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for formatter in InteractiveWebDateFormatters.shared.all {
        if let date = formatter.date(from: trimmed) { return date }
    }
    return nil
}

@MainActor
private struct InteractiveWebDateFormatters {
    static let shared = InteractiveWebDateFormatters()
    let all: [ISO8601DateFormatter]

    init() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        all = [fractional, internet]
    }
}
