import SwiftUI

struct NoteImportToolbarPresentation: Equatable {
    let summary: NoteImportActivitySummary

    var helpText: String {
        let taskText = "\(summary.visibleJobCount) 个导入任务"
        switch summary.presentationState {
        case .paused:
            return "打开导入中心 · \(taskText)已暂停\(progressSuffix)"
        case .cancelling:
            return "打开导入中心 · \(taskText)正在取消\(progressSuffix)"
        case .running:
            if summary.progressFraction == nil {
                return "打开导入中心 · 正在扫描导入内容"
            }
            return "打开导入中心 · \(taskText)\(progressSuffix)"
        }
    }

    var accessibilityValue: String {
        let progress: String
        if let percent { progress = "进度 \(percent)%"
        } else { progress = "进度未知" }
        switch summary.presentationState {
        case .paused: return "\(summary.visibleJobCount) 个任务，已暂停，\(progress)"
        case .cancelling: return "\(summary.visibleJobCount) 个任务，正在取消，\(progress)"
        case .running: return "\(summary.visibleJobCount) 个任务，正在进行，\(progress)"
        }
    }

    private var percent: Int? {
        summary.progressFraction.map { Int(($0 * 100).rounded()) }
    }

    private var progressSuffix: String {
        percent.map { " · \($0)%" } ?? ""
    }
}

struct NoteImportToolbarProgressButton: View {
    let summary: NoteImportActivitySummary
    let action: () -> Void

    private var presentation: NoteImportToolbarPresentation {
        NoteImportToolbarPresentation(summary: summary)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let progress = summary.progressFraction {
                    Circle()
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(NoteImportProgressAppearance.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(NoteImportProgressAppearance.accentColor)
                }

                statusImage
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(NoteImportProgressAppearance.accentColor)
            }
            .frame(width: 21, height: 21)
            .contentShape(Circle())
        }
        .buttonStyle(.appIcon)
        .help(presentation.helpText)
        .accessibilityLabel("打开导入中心")
        .accessibilityValue(presentation.accessibilityValue)
    }

    @ViewBuilder
    private var statusImage: some View {
        switch summary.presentationState {
        case .paused:
            Image(systemName: "pause.fill")
        case .cancelling:
            Image(systemName: "xmark")
        case .running:
            if summary.progressFraction != nil {
                Image(systemName: "arrow.down")
            }
        }
    }

}
