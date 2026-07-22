import Foundation
import ConnorGraphCore

public enum AppAgentPendingApprovalSeverity: String, Sendable, Equatable {
    case warning
    case success
    case error
    case cancelled
}

public struct AppAgentPendingApprovalPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var requestID: String
    public var title: String
    public var detail: String
    public var statusLabel: String
    public var toolDisplayName: String
    public var capabilityLabel: String
    public var capabilityDescription: String
    public var sessionTitle: String
    public var severity: AppAgentPendingApprovalSeverity
    public var createdAt: Date
    public var allowsAlwaysAllow: Bool

    public init(_ approval: AgentPendingApproval, sessionTitle: String? = nil) {
        self.id = approval.id
        self.requestID = approval.requestID
        self.toolDisplayName = approval.toolName.map {
            AgentToolDisplayNameResolver.displayName(rawToolName: $0, semanticKind: .unknown)
        } ?? "未指定工具"
        self.capabilityLabel = Self.capabilityLabel(approval.capability)
        self.capabilityDescription = Self.capabilityDescription(approval.capability)
        let resolvedSessionTitle = sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.sessionTitle = resolvedSessionTitle.isEmpty ? "会话 \(approval.sessionID)" : resolvedSessionTitle
        let mail = AppMailSendApprovalPresentation(approval)
        if mail.isMailSendRequest {
            self.title = mail.title
            self.detail = [mail.recipientSummary, mail.subjectSummary, mail.securitySummary].joined(separator: " · ")
            self.allowsAlwaysAllow = false
        } else if approval.toolName == "calendar_write", let calendar = Self.calendarPayload(approval.payloadJSON) {
            self.title = calendar.title
            self.detail = calendar.detail
            self.allowsAlwaysAllow = false
        } else if approval.toolName == "personality_commit_proposal", let personality = Self.personalityPayload(approval.payloadJSON) {
            self.title = personality.title
            self.detail = personality.detail
            self.allowsAlwaysAllow = false
        } else {
            self.title = "请求执行：\(toolDisplayName)"
            self.detail = "权限：\(capabilityLabel) · \(capabilityDescription) · 请求：\(approval.requestID) · 参数：\(Self.compactJSON(approval.payloadJSON))"
            self.allowsAlwaysAllow = true
        }
        self.statusLabel = Self.statusLabel(approval.status)
        self.severity = Self.severity(for: approval.status)
        self.createdAt = approval.createdAt
    }

    private static func calendarPayload(_ json: String) -> (title: String, detail: String)? {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let operation = object["operation"] as? String else { return nil }
        let title: String
        switch operation {
        case "create_event": title = "日历：创建日程"
        case "update_event": title = "日历：更新日程"
        case "delete_event": title = "日历：删除日程"
        default: title = "日历：修改日程"
        }
        let eventTitle = object["verifiedEventTitle"] as? String ?? object["title"] as? String ?? "未命名日程"
        let eventID = object["eventID"] as? String
        let calendarID = object["verifiedCalendarID"] as? String ?? object["calendarID"] as? String
        let fields = [eventTitle, eventID.map { "日程 ID：\($0)" }, calendarID.map { "日历 ID：\($0)" }].compactMap { $0 }
        return (title, fields.joined(separator: " · "))
    }

    private static func personalityPayload(_ json: String) -> (title: String, detail: String)? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let title = object["title"] as? String ?? "更新康纳同学性格"
        let before = (object["beforeSummary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let after = (object["afterSummary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let beforeText = before.isEmpty ? "默认性格" : before
        let afterText = after.isEmpty ? "默认性格" : after
        return (title, "固定姓名：康纳同学 · \(beforeText) → \(afterText)")
    }

    private static func statusLabel(_ status: AgentPendingApprovalStatus) -> String {
        switch status {
        case .pending: "等待审批"
        case .approved: "已批准"
        case .denied: "已拒绝"
        case .cancelled: "已取消"
        }
    }

    private static func capabilityLabel(_ capability: AgentPermissionCapability) -> String {
        switch capability {
        case .readGraph: "读取知识图谱"
        case .readSession: "读取会话"
        case .mutateSessionStatus: "修改会话状态"
        case .mutatePersonality: "修改康纳同学性格"
        case .proposeGraphWrite: "提议写入知识图谱"
        case .commitGraphWrite: "写入知识图谱"
        case .invalidateGraphStatement: "作废图谱信息"
        case .deleteGraphObject: "删除图谱对象"
        case .externalNetwork: "访问网络"
        case .readBrowserPage: "读取浏览器页面"
        case .navigateBrowser: "浏览器导航"
        case .interactBrowser: "操作浏览器页面"
        case .commitBrowserAction: "提交浏览器操作"
        case .transferBrowserFile: "传输浏览器文件"
        case .modelCall: "调用模型"
        case .costlyModelCall: "调用高成本模型"
        case .readWorkspaceFile: "读取工作目录文件"
        case .listWorkspaceFiles: "查看工作目录"
        case .searchWorkspaceFiles: "搜索工作目录"
        case .writeWorkspaceFile: "写入工作目录文件"
        case .editWorkspaceFile: "编辑工作目录文件"
        case .deleteWorkspaceFile: "删除工作目录文件"
        case .computeScientific: "执行科学计算"
        case .runReadOnlyShellCommand: "运行只读终端命令"
        case .runWorkspaceShellCommand: "运行工作目录命令"
        case .runNetworkShellCommand: "运行联网命令"
        case .runDestructiveShellCommand: "运行高风险命令"
        case .readMail: "读取邮件"
        case .readMailBody: "读取邮件正文"
        case .mutateMailState: "修改邮件状态"
        case .manageMailboxes: "管理邮箱"
        case .createMailDraft: "创建邮件草稿"
        case .sendMail: "发送邮件"
        case .importMailAttachment: "导入邮件附件"
        case .readContacts: "读取联系人"
        case .mutateContacts: "修改联系人"
        case .readCalendar: "读取日历"
        case .mutateCalendar: "修改日历"
        case .readRSS: "读取 RSS 订阅"
        case .readRSSContent: "读取 RSS 正文"
        case .mutateRSSState: "修改 RSS 状态"
        case .manageRSSSources: "管理 RSS 订阅源"
        case .syncRSSSources: "同步 RSS 订阅源"
        case .importRSSOPML: "导入 RSS 订阅"
        case .exportRSSOPML: "导出 RSS 订阅"
        }
    }

    private static func capabilityDescription(_ capability: AgentPermissionCapability) -> String {
        switch capability {
        case .readGraph, .readSession, .readBrowserPage, .readWorkspaceFile, .listWorkspaceFiles,
             .searchWorkspaceFiles, .readMail, .readMailBody, .readContacts, .readCalendar,
             .readRSS, .readRSSContent:
            "允许工具读取对应范围内的信息，不会主动修改内容。"
        case .externalNetwork, .navigateBrowser:
            "允许连接外部网络或打开网页，可能向第三方服务发送请求。"
        case .modelCall, .costlyModelCall:
            "允许调用 AI 模型；可能产生用量或费用。"
        case .runReadOnlyShellCommand, .computeScientific:
            "允许在本机执行计算或只读命令。"
        case .writeWorkspaceFile, .editWorkspaceFile, .deleteWorkspaceFile, .runWorkspaceShellCommand,
             .runNetworkShellCommand, .runDestructiveShellCommand:
            "允许在本机执行可能修改文件、访问网络或产生其他副作用的操作。"
        case .interactBrowser, .commitBrowserAction, .transferBrowserFile:
            "允许操作网页、提交页面动作或传输文件，可能对外部服务产生影响。"
        default:
            "允许工具执行可能更改数据或外部状态的操作，请确认目标和参数。"
        }
    }

    private static func severity(for status: AgentPendingApprovalStatus) -> AppAgentPendingApprovalSeverity {
        switch status {
        case .pending: .warning
        case .approved: .success
        case .denied: .error
        case .cancelled: .cancelled
        }
    }

    private static func compactJSON(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let compact = try? JSONSerialization.data(withJSONObject: object, options: []),
              let string = String(data: compact, encoding: .utf8)
        else { return trimmed }
        return string
    }
}
