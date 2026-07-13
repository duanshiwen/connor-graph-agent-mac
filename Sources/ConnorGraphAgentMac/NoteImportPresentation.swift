import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct NoteImportControlPresentation: Equatable {
    enum Action: Equatable { case pause, resume, restart }

    let action: Action
    let title: String
    let systemImage: String

    init?(job: NoteImportJobRecord, runtimeState: NoteImportRuntimeState? = .running) {
        guard !job.status.isTerminal, job.cancelRequestedAt == nil else { return nil }
        if NoteImportActivitySummary.isPaused(job) {
            action = .resume
            title = "继续"
            systemImage = "play"
        } else if [.awaitingReview, .ready, .importing, .processing].contains(job.status), runtimeState == nil {
            action = .restart
            title = "继续剩余任务"
            systemImage = "arrow.clockwise"
        } else if [.scanning, .importing, .processing].contains(job.status) {
            action = .pause
            title = "暂停"
            systemImage = "pause"
        } else {
            return nil
        }
    }
}

struct NoteImportJobPresentation: Equatable {
    let displayName: String
    let systemImage: String

    init(job: NoteImportJobRecord, runtimeState: NoteImportRuntimeState? = .running) {
        if job.status.isTerminal {
            displayName = job.status.displayName
            systemImage = job.status.systemImage
        } else if job.cancelRequestedAt != nil || job.status == .cancelling {
            displayName = NoteImportJobStatus.cancelling.displayName
            systemImage = NoteImportJobStatus.cancelling.systemImage
        } else if NoteImportActivitySummary.isPaused(job) {
            displayName = NoteImportJobStatus.paused.displayName
            systemImage = NoteImportJobStatus.paused.systemImage
        } else if [.awaitingReview, .ready, .importing, .processing].contains(job.status), runtimeState == nil {
            displayName = "导入已中断"
            systemImage = "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        } else if runtimeState == .recovering || runtimeState == .starting {
            displayName = "正在恢复"
            systemImage = "arrow.clockwise"
        } else {
            displayName = job.status.displayName
            systemImage = job.status.systemImage
        }
    }
}

enum NoteImportProgressAppearance {
    static var accentColor: Color { Color(nsColor: .controlAccentColor) }
}

extension NoteImportSourceKind {
    var displayName: String { switch self { case .markdownFolder: "Markdown 文件夹"; case .obsidianVault: "Obsidian 仓库"; case .notionExport: "Notion 导出"; case .evernoteENEX: "Evernote / 印象笔记" } }
    var detail: String { switch self { case .markdownFolder: "递归导入 .md 与本地附件"; case .obsidianVault: "保留双链、嵌入与别名"; case .notionExport: "Markdown、HTML 与数据库 CSV"; case .evernoteENEX: "导入 ENEX 笔记、标签与资源" } }
    var selectionHint: String { switch self { case .markdownFolder, .obsidianVault: "请选择文件夹"; case .notionExport: "请选择已解压的导出文件夹"; case .evernoteENEX: "请选择 .enex 文件" } }
    var systemImage: String { switch self { case .markdownFolder: "folder"; case .obsidianVault: "link"; case .notionExport: "square.grid.2x2"; case .evernoteENEX: "archivebox" } }
}

extension NoteImportJobStatus {
    var displayName: String { switch self { case .created: "准备中"; case .scanning: "正在扫描"; case .awaitingReview: "等待确认"; case .ready: "即将开始"; case .importing: "正在导入"; case .processing: "AI 正在处理"; case .paused: "已暂停"; case .cancelling: "正在取消"; case .cancelled: "已取消"; case .completedWithIssues: "已完成，有问题"; case .completed: "已完成"; case .failed: "失败" } }
    var systemImage: String { switch self { case .completed: "checkmark.circle.fill"; case .completedWithIssues, .failed: "exclamationmark.triangle.fill"; case .cancelled: "xmark.circle"; case .paused: "pause.circle.fill"; case .scanning: "doc.text.magnifyingglass"; default: "arrow.triangle.2.circlepath" } }
    var tint: Color { switch self { case .completed: .green; case .completedWithIssues, .failed: .orange; case .cancelled: .secondary; case .paused: NoteImportProgressAppearance.accentColor; default: NoteImportProgressAppearance.accentColor } }
}

extension NoteImportItemStatus {
    var displayName: String { switch self { case .discovered: "已发现"; case .validating: "验证中"; case .needsEncodingReview: "检查编码"; case .ready: "等待导入"; case .duplicateUnchanged: "未变化"; case .duplicateChanged: "有更新"; case .creatingSession: "创建笔记"; case .imported: "已导入"; case .queuedForLLM: "等待 AI"; case .runningLLM: "AI 处理中"; case .completed: "完成"; case .parseFailed: "解析失败"; case .sessionFailed: "创建失败"; case .attachmentFailed: "附件失败"; case .llmFailed: "AI 失败"; case .cancelled: "已取消" } }
    var systemImage: String { switch self { case .completed: "checkmark.circle.fill"; case .parseFailed, .sessionFailed, .attachmentFailed, .llmFailed: "exclamationmark.triangle.fill"; case .cancelled: "xmark.circle"; default: "clock" } }
    var tint: Color { switch self { case .completed: .green; case .parseFailed, .sessionFailed, .attachmentFailed, .llmFailed: .orange; case .cancelled: .secondary; default: .secondary } }
}
