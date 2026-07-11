import SwiftUI
import AppKit
import ConnorGraphAppSupport

struct AgentToolInvocationRenderer: View {
    var invocation: AgentToolInvocationPresentation
    var showsRichDescription: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            if showsRichDescription {
                AgentToolInputSection(invocation: invocation)
            }

            switch invocation.semanticKind {
            case .shellCommand, .swiftBuild, .swiftTest, .swiftRun, .xcodeBuild, .git, .packageManager, .python, .node:
                AgentShellToolOutputView(invocation: invocation)
            case .mcp:
                AgentMCPToolOutputView(invocation: invocation)
            case .browser:
                AgentGenericToolOutputView(title: "Browser Output", text: invocation.outputText ?? invocation.errorText, resultJSON: invocation.resultJSON, severity: invocation.severity)
            case .writeFile, .editFile:
                if let change = AgentToolChangePresentation(invocation: invocation) {
                    AgentFileChangeToolOutputView(change: change, fallbackText: invocation.outputText ?? invocation.errorText, resultJSON: invocation.resultJSON, severity: invocation.severity)
                } else {
                    AgentGenericToolOutputView(title: "File Change Output", text: invocation.outputText ?? invocation.errorText, resultJSON: invocation.resultJSON, severity: invocation.severity)
                }
            case .readFile, .listDirectory, .findFiles, .searchFiles, .calendar, .unknown:
                AgentGenericToolOutputView(title: "Output", text: invocation.outputText ?? invocation.errorText, resultJSON: invocation.resultJSON, severity: invocation.severity)
            }
        }
    }
}

private struct AgentToolInputSection: View {
    var invocation: AgentToolInvocationPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ToolRendererSectionHeader(title: "Input", systemImage: "square.and.pencil", copyValue: invocation.argumentsJSON)
            if let argumentsJSON = invocation.argumentsJSON, !argumentsJSON.isEmpty {
                codeBlock(prettyJSON(argumentsJSON) ?? argumentsJSON)
            } else {
                emptyText("No structured input captured for this tool event.")
            }
        }
        .toolRendererCard()
    }
}

private struct AgentShellToolOutputView: View {
    var invocation: AgentToolInvocationPresentation

    private var shellOutput: AgentShellOutputPresentation {
        AgentShellOutputPresentation(invocation: invocation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ToolRendererSectionHeader(title: "Terminal Output", systemImage: "terminal", copyValue: shellOutput.fullText)

            if let command = shellOutput.command, !command.isEmpty {
                labeledCodeBlock("Command", command)
            }

            HStack(spacing: AgentChatLayout.spaceS) {
                statusChip("exit \(shellOutput.exitCode.map(String.init) ?? "unknown")", isError: invocation.severity == .error)
                if shellOutput.isTruncated {
                    statusChip("preview truncated", isError: false)
                }
                Spacer(minLength: 0)
            }

            if !shellOutput.stdout.isEmpty {
                labeledCodeBlock("stdout", shellOutput.stdout)
            }
            if !shellOutput.stderr.isEmpty {
                labeledCodeBlock("stderr", shellOutput.stderr, isError: true)
            }
            if shellOutput.stdout.isEmpty, shellOutput.stderr.isEmpty {
                codeBlock(shellOutput.previewText.isEmpty ? "No output captured." : shellOutput.previewText)
            }
        }
        .toolRendererCard()
    }
}

private struct AgentMCPToolOutputView: View {
    var invocation: AgentToolInvocationPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ToolRendererSectionHeader(title: "MCP Output", systemImage: "server.rack", copyValue: invocation.outputText ?? invocation.resultJSON)
            if let target = invocation.target, !target.isEmpty {
                Text(target)
                    .font(AgentChatTypography.monoMeta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            AgentGenericToolOutputView(title: "Result", text: invocation.outputText ?? invocation.errorText, resultJSON: invocation.resultJSON, severity: invocation.severity, wrapsInCard: false)
        }
        .toolRendererCard()
    }
}

private struct AgentFileChangeToolOutputView: View {
    var change: AgentToolChangePresentation
    var fallbackText: String?
    var resultJSON: String?
    var severity: AgentEventPresentationSeverity

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ToolRendererSectionHeader(title: "File Change", systemImage: "doc.text.magnifyingglass", copyValue: change.diffText ?? fallbackText ?? resultJSON)

            HStack(spacing: AgentChatLayout.spaceS) {
                if let path = change.path, !path.isEmpty {
                    statusChip(path, isError: false)
                }
                statusChip(change.format == .unifiedDiff ? "unified diff" : "before / after", isError: false)
                if change.isTruncated {
                    statusChip("preview truncated", isError: false)
                }
                Spacer(minLength: 0)
            }

            if let diffText = change.diffText, !diffText.isEmpty {
                diffBlock(diffText)
            } else if let fallbackText, !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outputBlock(fallbackText)
            } else if let resultJSON, let pretty = prettyJSON(resultJSON) {
                labeledCodeBlock("JSON", pretty)
            } else {
                emptyText("No file change output captured for this tool event.")
            }

            if change.isTruncated {
                Text("Diff preview truncated; \(change.omittedCharacterCount) characters omitted.")
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.orange)
            }
        }
        .toolRendererCard()
    }
}

private struct AgentGenericToolOutputView: View {
    var title: String
    var text: String?
    var resultJSON: String?
    var severity: AgentEventPresentationSeverity
    var wrapsInCard: Bool = true

    var body: some View {
        let content = VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ToolRendererSectionHeader(title: title, systemImage: severity == .error ? "xmark.octagon" : "doc.text", copyValue: text ?? resultJSON)
            if let resultJSON, let pretty = prettyJSON(resultJSON) {
                labeledCodeBlock("JSON", pretty)
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outputBlock(text)
            } else if resultJSON == nil {
                emptyText("No output captured for this tool event.")
            }
        }

        if wrapsInCard {
            content.toolRendererCard()
        } else {
            content
        }
    }
}

private struct AgentShellOutputPresentation {
    var command: String?
    var exitCode: Int?
    var stdout: String
    var stderr: String
    var previewText: String
    var fullText: String
    var isTruncated: Bool

    init(invocation: AgentToolInvocationPresentation, policy: AgentToolOutputDisplayPolicy = AgentToolOutputDisplayPolicy()) {
        self.command = Self.command(from: invocation.argumentsJSON)
        self.exitCode = Self.exitCode(from: invocation.resultJSON)
        let raw = invocation.outputText ?? invocation.errorText ?? ""
        let display = policy.display(for: raw)
        self.previewText = display.previewText
        self.fullText = raw
        self.isTruncated = display.isTruncated || invocation.isOutputTruncated

        let jsonParts = Self.partsFromResultJSON(invocation.resultJSON)
        if let jsonParts {
            self.stdout = policy.display(for: jsonParts.stdout).previewText
            self.stderr = policy.display(for: jsonParts.stderr).previewText
            if self.exitCode == nil { self.exitCode = jsonParts.exitCode }
        } else {
            let parsed = Self.partsFromPlainText(display.previewText)
            self.stdout = parsed.stdout
            self.stderr = parsed.stderr
        }
    }

    private static func command(from json: String?) -> String? {
        guard let object = dictionary(from: json) else { return nil }
        return object["command"] as? String
    }

    private static func exitCode(from json: String?) -> Int? {
        guard let object = dictionary(from: json) else { return nil }
        if let value = object["exitCode"] as? Int { return value }
        if let value = object["exit_code"] as? Int { return value }
        if let value = object["exitCode"] as? Double { return Int(value) }
        if let value = object["exit_code"] as? Double { return Int(value) }
        if let value = object["exitCode"] as? String { return Int(value) }
        if let value = object["exit_code"] as? String { return Int(value) }
        return nil
    }

    private static func partsFromResultJSON(_ json: String?) -> (stdout: String, stderr: String, exitCode: Int?)? {
        guard let object = dictionary(from: json) else { return nil }
        let stdout = (object["stdout"] as? String) ?? (object["output"] as? String) ?? ""
        let stderr = (object["stderr"] as? String) ?? (object["error"] as? String) ?? ""
        let exit = exitCode(from: json)
        guard !stdout.isEmpty || !stderr.isEmpty || exit != nil else { return nil }
        return (stdout, stderr, exit)
    }

    private static func partsFromPlainText(_ text: String) -> (stdout: String, stderr: String) {
        let lower = text.lowercased()
        guard let stdoutRange = lower.range(of: "stdout:"), let stderrRange = lower.range(of: "stderr:"), stdoutRange.upperBound <= stderrRange.lowerBound else {
            return (text, "")
        }
        let stdout = String(text[stdoutRange.upperBound..<stderrRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(text[stderrRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (stdout, stderr)
    }

    private static func dictionary(from json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

private struct ToolRendererSectionHeader: View {
    var title: String
    var systemImage: String
    var copyValue: String?

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Label(title, systemImage: systemImage)
                .font(AgentChatTypography.metaEmphasis)
            Spacer(minLength: 0)
            if let copyValue, !copyValue.isEmpty {
                Button(action: { copy(copyValue) }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(AgentChatTypography.micro.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private func labeledCodeBlock(_ title: String, _ value: String, isError: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(AgentChatTypography.monoMicro.weight(.semibold))
            .foregroundStyle(isError ? Color.red : Color.secondary)
        codeBlock(value)
    }
}

private func codeBlock(_ value: String) -> some View {
    Text(value)
        .font(AgentChatTypography.monoMeta)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AgentChatLayout.spaceS)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
}

private func diffBlock(_ value: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(value.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, rawLine in
            let line = String(rawLine)
            Text(line.isEmpty ? " " : line)
                .font(AgentChatTypography.monoMeta)
                .foregroundStyle(diffLineForeground(line))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AgentChatLayout.spaceS)
                .padding(.vertical, 1)
                .background(diffLineBackground(line))
                .textSelection(.enabled)
        }
    }
    .padding(.vertical, AgentChatLayout.spaceS)
    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
}

private func diffLineForeground(_ line: String) -> Color {
    if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
    if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
    if line.hasPrefix("@@") { return .blue }
    return .primary
}

private func diffLineBackground(_ line: String) -> Color {
    if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green.opacity(0.10) }
    if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.10) }
    if line.hasPrefix("@@") { return Color.blue.opacity(0.08) }
    return Color.clear
}

private func outputBlock(_ value: String) -> some View {
    let display = AgentToolOutputDisplayPolicy().display(for: value)
    return VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
        codeBlock(display.previewText)
        if display.isTruncated {
            Text("Output preview truncated after \(display.previewText.count) characters; \(display.omittedCharacterCount) characters omitted.")
                .font(AgentChatTypography.micro)
                .foregroundStyle(.orange)
        }
    }
}

private func emptyText(_ value: String) -> some View {
    Text(value)
        .font(AgentChatTypography.meta)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

private func statusChip(_ value: String, isError: Bool) -> some View {
    Text(value)
        .font(AgentChatTypography.monoMicro)
        .foregroundStyle(isError ? Color.red : Color.secondary)
        .padding(.horizontal, 7)
        .frame(height: AgentChatLayout.chipHeight)
        .background((isError ? Color.red : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
}

private func prettyJSON(_ json: String?) -> String? {
    guard let json,
          let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          JSONSerialization.isValidJSONObject(object),
          let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: pretty, encoding: .utf8)
    else { return nil }
    return string
}

private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

private extension View {
    func toolRendererCard() -> some View {
        self
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.50), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}
