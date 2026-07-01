import SwiftUI
import AppKit

/// 笔记模式的 Markdown 格式工具栏
/// 紧贴 Composer 文本框上方，提供 Markdown 语法快捷插入按钮
struct AgentComposerFormatBar: View {
    @Binding var text: String
    var selectionTracker: ComposerTextSelectionTracker
    var onInsertImage: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            formatButton(systemImage: "bold", shortcut: "B", action: wrapSelection(prefix: "**", suffix: "**", placeholder: "加粗文本"))
            formatButton(systemImage: "italic", shortcut: "I", action: wrapSelection(prefix: "*", suffix: "*", placeholder: "斜体文本"))

            Divider()
                .frame(height: 14)

            formatButton(systemImage: "textformat.size", shortcut: "H1", action: insertLinePrefix("# ", placeholder: "标题"))
            formatButton(systemImage: "textformat.size.smaller", shortcut: "H2", action: insertLinePrefix("## ", placeholder: "标题"))

            Divider()
                .frame(height: 14)

            formatButton(systemImage: "list.bullet", shortcut: nil, action: insertLinePrefix("- ", placeholder: "列表项"))
            formatButton(systemImage: "list.number", shortcut: nil, action: insertLinePrefix("1. ", placeholder: "列表项"))

            Divider()
                .frame(height: 14)

            formatButton(systemImage: "text.quote", shortcut: nil, action: insertLinePrefix("> ", placeholder: "引用文本"))
            formatButton(systemImage: "curlybraces", shortcut: nil, action: insertCodeBlock)

            Divider()
                .frame(height: 14)

            Button(action: onInsertImage) {
                Label("图片", systemImage: "photo")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .labelStyle(.iconOnly)
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("插入图片")
            .accessibilityLabel("插入图片")

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func formatButton(systemImage: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: 26, height: 22)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 26, height: 22)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(shortcut.map { "\($0) (\(buttonHelpLabel(systemImage: systemImage)))" } ?? buttonHelpLabel(systemImage: systemImage))
        .accessibilityLabel(buttonAccessibilityLabel(systemImage: systemImage, shortcut: shortcut))
    }

    // MARK: - Insertion Actions

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) -> () -> Void {
        {
            guard let selectedRange = selectionTracker.selectedRange,
                  selectedRange.location != NSNotFound
            else {
                // No selection: insert at the end
                text += "\(prefix)\(placeholder)\(suffix)"
                return
            }

            let nsText = text as NSString
            let location = min(selectedRange.location, nsText.length)
            let length = min(selectedRange.length, nsText.length - location)

            if length > 0 {
                let selectedText = nsText.substring(with: NSRange(location: location, length: length))
                let replacement = "\(prefix)\(selectedText)\(suffix)"
                text = nsText.replacingCharacters(in: NSRange(location: location, length: length), with: replacement)
            } else {
                let replacement = "\(prefix)\(placeholder)\(suffix)"
                text = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: replacement)
                // Move cursor inside placeholder
                let cursorInside = location + prefix.count
                selectionTracker.selectedRange = NSRange(location: cursorInside, length: placeholder.count)
            }
        }
    }

    private func insertLinePrefix(_ prefix: String, placeholder: String) -> () -> Void {
        {
            guard let selectedRange = selectionTracker.selectedRange,
                  selectedRange.location != NSNotFound,
                  selectedRange.location <= (text as NSString).length
            else {
                let newLine = text.isEmpty ? "" : "\n"
                text += "\(newLine)\(prefix)\(placeholder)"
                return
            }

            let nsText = text as NSString
            let location = selectedRange.location
            var insertionPoint = location

            // If cursor is at the start of a line, insert prefix at line start
            if location > 0 {
                let precedingChar = nsText.substring(with: NSRange(location: location - 1, length: 1))
                if precedingChar == "\n" || precedingChar == "\r" {
                    // Cursor is at start of a line
                    insertionPoint = location
                } else {
                    // Cursor is mid-line, insert newline first
                    let replacement = "\n\(prefix)\(placeholder)"
                    text = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: replacement)
                    return
                }
            }

            let replacement = "\(prefix)\(placeholder)"
            text = nsText.replacingCharacters(in: NSRange(location: insertionPoint, length: 0), with: replacement)
        }
    }

    private func insertCodeBlock() {
        let codeBlock = "\n```\n\n```\n"
        guard let selectedRange = selectionTracker.selectedRange,
              selectedRange.location != NSNotFound
        else {
            text += codeBlock
            return
        }

        let nsText = text as NSString
        let location = min(selectedRange.location, nsText.length)
        text = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: codeBlock)
    }

    // MARK: - Helpers

    private func buttonHelpLabel(systemImage: String) -> String {
        switch systemImage {
        case "bold": return "Cmd+B"
        case "italic": return "Cmd+I"
        case "textformat.size": return "一级标题"
        case "textformat.size.smaller": return "二级标题"
        case "list.bullet": return "无序列表"
        case "list.number": return "有序列表"
        case "text.quote": return "引用"
        case "curlybraces": return "代码块"
        case "photo": return "插入图片"
        default: return ""
        }
    }

    private func buttonAccessibilityLabel(systemImage: String, shortcut: String?) -> String {
        switch systemImage {
        case "bold": return "加粗"
        case "italic": return "斜体"
        case "textformat.size": return "一级标题"
        case "textformat.size.smaller": return "二级标题"
        case "list.bullet": return "无序列表"
        case "list.number": return "有序列表"
        case "text.quote": return "引用"
        case "curlybraces": return "代码块"
        case "photo": return "插入图片"
        default: return ""
        }
    }
}
