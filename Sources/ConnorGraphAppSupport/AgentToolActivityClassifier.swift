import Foundation
import ConnorGraphAgent

public struct AgentToolActivityClassifier: Sendable {
    public init() {}

    public func activity(forRequestedCall call: AgentToolCall) -> AgentToolActivityPresentation? {
        activity(
            callID: call.id,
            rawToolName: call.name,
            phase: .requested,
            severity: .info,
            argumentsJSON: call.argumentsJSON,
            resultJSON: nil,
            fallbackDetail: compactJSON(call.argumentsJSON)
        )
    }

    public func activity(forApprovedCall call: AgentToolCall) -> AgentToolActivityPresentation? {
        activity(
            callID: call.id,
            rawToolName: call.name,
            phase: .approved,
            severity: .success,
            argumentsJSON: call.argumentsJSON,
            resultJSON: nil,
            fallbackDetail: "approved"
        )
    }

    public func activity(forStartedCall call: AgentToolCall) -> AgentToolActivityPresentation? {
        activity(
            callID: call.id,
            rawToolName: call.name,
            phase: .running,
            severity: .info,
            argumentsJSON: call.argumentsJSON,
            resultJSON: nil,
            fallbackDetail: "running"
        )
    }

    public func activity(forFinishedResult result: AgentToolResult) -> AgentToolActivityPresentation? {
        activity(
            callID: result.toolCallID,
            rawToolName: result.toolName,
            phase: result.error == nil ? .finished : .failed,
            severity: result.error == nil ? .success : .error,
            argumentsJSON: nil,
            resultJSON: result.contentJSON,
            fallbackDetail: trimmed(result.error ?? result.contentText)
        )
    }

    public func activity(forFailure failure: AgentToolFailure) -> AgentToolActivityPresentation? {
        var activity = activity(
            callID: failure.toolCallID,
            rawToolName: failure.toolName,
            phase: .failed,
            severity: .error,
            argumentsJSON: nil,
            resultJSON: nil,
            fallbackDetail: failure.message
        )
        if activity?.rawToolName == "Bash" {
            activity?.icon = "xmark.octagon"
        }
        return activity
    }

    private func activity(
        callID: String,
        rawToolName: String,
        phase: AgentToolActivityPhase,
        severity: AgentEventPresentationSeverity,
        argumentsJSON: String?,
        resultJSON: String?,
        fallbackDetail: String?
    ) -> AgentToolActivityPresentation? {
        let arguments = parseJSONObject(argumentsJSON)
        let result = parseJSONObject(resultJSON)
        let rawToolName = rawToolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawToolName.isEmpty else { return nil }

        let descriptor = descriptor(for: rawToolName, arguments: arguments, result: result)
        let icon = severity == .error ? errorIcon(for: descriptor.semanticKind, defaultIcon: descriptor.icon) : descriptor.icon
        let subtitle = descriptor.subtitle ?? resultSubtitle(from: result) ?? fallbackSubtitle(for: phase)

        return AgentToolActivityPresentation(
            callID: callID,
            phase: phase,
            rawToolName: rawToolName,
            semanticKind: descriptor.semanticKind,
            title: descriptor.title,
            subtitle: subtitle,
            target: descriptor.target,
            detail: fallbackDetail,
            icon: icon,
            severity: severity,
            argumentsJSON: argumentsJSON,
            resultJSON: resultJSON
        )
    }

    private func descriptor(for rawToolName: String, arguments: [String: Any], result: [String: Any]) -> ToolDescriptor {
        switch rawToolName {
        case "Read":
            let offset = int(arguments["offset"])
            let limit = int(arguments["limit"])
            return ToolDescriptor(
                semanticKind: .readFile,
                title: "Read File",
                target: basename(string(arguments["file_path"]) ?? string(result["path"])),
                subtitle: lineRange(offset: offset, limit: limit),
                icon: "doc.text.magnifyingglass"
            )
        case "Write":
            let operation = string(result["operation"])
            return ToolDescriptor(
                semanticKind: .writeFile,
                title: "Write File",
                target: basename(string(arguments["file_path"]) ?? string(result["path"])),
                subtitle: operation,
                icon: "square.and.pencil"
            )
        case "Edit", "MultiEdit":
            return ToolDescriptor(
                semanticKind: .editFile,
                title: "Edit File",
                target: basename(string(arguments["file_path"]) ?? string(result["path"])),
                subtitle: editSubtitle(arguments: arguments, result: result),
                icon: "pencil"
            )
        case "LS":
            return ToolDescriptor(
                semanticKind: .listDirectory,
                title: "List Directory",
                target: pathTarget(string(arguments["path"]) ?? string(result["path"])),
                subtitle: countSubtitle(result["count"], noun: "items"),
                icon: "folder"
            )
        case "Glob":
            return ToolDescriptor(
                semanticKind: .findFiles,
                title: "Find Files",
                target: string(arguments["pattern"]),
                subtitle: countSubtitle(result["count"], noun: "matches"),
                icon: "scope"
            )
        case "Grep":
            return ToolDescriptor(
                semanticKind: .searchFiles,
                title: "Search Files",
                target: string(arguments["pattern"]),
                subtitle: countSubtitle(result["matches"], noun: "matches"),
                icon: "magnifyingglass"
            )
        case "Bash":
            return shellDescriptor(command: string(arguments["command"]) ?? string(result["command"]))
        default:
            if let mcp = mcpDescriptor(rawToolName) { return mcp }
            if rawToolName.localizedCaseInsensitiveContains("browser") {
                return ToolDescriptor(semanticKind: .browser, title: "Browser", target: rawToolName, subtitle: nil, icon: "safari")
            }
            return ToolDescriptor(semanticKind: .unknown, title: rawToolName, target: nil, subtitle: nil, icon: "wrench.and.screwdriver")
        }
    }

    private func shellDescriptor(command: String?) -> ToolDescriptor {
        let command = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = command.lowercased()
        let target = canonicalShellTarget(command)

        if containsCommand(normalized, "swift build") {
            return ToolDescriptor(semanticKind: .swiftBuild, title: "Swift: 编译项目", target: "swift build", subtitle: nil, icon: "swift")
        }
        if containsCommand(normalized, "swift test") {
            return ToolDescriptor(semanticKind: .swiftTest, title: "Swift: 运行测试", target: "swift test", subtitle: nil, icon: "swift")
        }
        if containsCommand(normalized, "swift run") {
            return ToolDescriptor(semanticKind: .swiftRun, title: "Swift: 运行目标", target: "swift run", subtitle: nil, icon: "swift")
        }
        if normalized.contains("xcodebuild") {
            let title = normalized.contains(" test") ? "Xcode: 运行测试" : "Xcode: 编译项目"
            return ToolDescriptor(semanticKind: .xcodeBuild, title: title, target: "xcodebuild", subtitle: nil, icon: "hammer")
        }
        if containsCommand(normalized, "git diff") {
            return ToolDescriptor(semanticKind: .git, title: "Git: 查看变更", target: "git diff", subtitle: nil, icon: "arrow.triangle.branch")
        }
        if containsCommand(normalized, "git status") {
            return ToolDescriptor(semanticKind: .git, title: "Git: 查看状态", target: "git status", subtitle: nil, icon: "arrow.triangle.branch")
        }
        if containsCommand(normalized, "git commit") {
            return ToolDescriptor(semanticKind: .git, title: "Git: 提交变更", target: "git commit", subtitle: nil, icon: "arrow.triangle.branch")
        }
        if startsShellSegment(normalized, prefixes: ["rg ", "grep "]) {
            return ToolDescriptor(semanticKind: .searchFiles, title: "Shell: 搜索文本", target: target, subtitle: nil, icon: "magnifyingglass")
        }
        if startsShellSegment(normalized, prefixes: ["cat ", "head ", "tail ", "sed "]) {
            return ToolDescriptor(semanticKind: .shellCommand, title: "Shell: 查看文件", target: target, subtitle: nil, icon: "terminal")
        }
        if startsShellSegment(normalized, prefixes: ["python ", "python3 "]) {
            return ToolDescriptor(semanticKind: .python, title: "Python: 运行脚本", target: target, subtitle: nil, icon: "chevron.left.forwardslash.chevron.right")
        }
        if startsShellSegment(normalized, prefixes: ["node ", "bun ", "npm ", "pnpm ", "yarn "]) {
            return ToolDescriptor(semanticKind: .node, title: "JS: 运行工具", target: target, subtitle: nil, icon: "curlybraces")
        }
        if startsShellSegment(normalized, prefixes: ["mkdir ", "cp ", "mv ", "rm "]) {
            return ToolDescriptor(semanticKind: .shellCommand, title: "Shell: 文件系统操作", target: target, subtitle: nil, icon: "terminal")
        }
        return ToolDescriptor(semanticKind: .shellCommand, title: "Shell", target: target?.nilIfEmpty, subtitle: nil, icon: "terminal")
    }

    private func mcpDescriptor(_ rawToolName: String) -> ToolDescriptor? {
        guard rawToolName.hasPrefix("mcp__") else { return nil }
        let parts = rawToolName.split(separator: "__", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else {
            return ToolDescriptor(semanticKind: .mcp, title: "MCP", target: rawToolName, subtitle: nil, icon: "server.rack")
        }
        return ToolDescriptor(
            semanticKind: .mcp,
            title: "MCP: \(parts[1])",
            target: parts.dropFirst(2).joined(separator: "__"),
            subtitle: nil,
            icon: "server.rack"
        )
    }

    private struct ToolDescriptor {
        var semanticKind: AgentToolSemanticKind
        var title: String
        var target: String?
        var subtitle: String?
        var icon: String
    }

    private func editSubtitle(arguments: [String: Any], result: [String: Any]) -> String? {
        let edits = int(result["edits"]) ?? int(arguments["edits"])
        guard let edits else { return nil }
        return edits == 1 ? "1 edit" : "\(edits) edits"
    }

    private func lineRange(offset: Int?, limit: Int?) -> String? {
        guard let offset else { return nil }
        guard let limit, limit > 0 else { return "\(offset)" }
        return "\(offset)–\(offset + limit - 1)"
    }

    private func resultSubtitle(from result: [String: Any]) -> String? {
        if let exitCode = int(result["exitCode"]) { return "exit \(exitCode)" }
        if let operation = string(result["operation"]) { return operation }
        return nil
    }

    private func fallbackSubtitle(for phase: AgentToolActivityPhase) -> String? {
        switch phase {
        case .requested: nil
        case .approved: "approved"
        case .running: "running"
        case .finished: "done"
        case .failed: "failed"
        }
    }

    private func countSubtitle(_ value: Any?, noun: String) -> String? {
        guard let count = int(value) else { return nil }
        return "\(count) \(noun)"
    }

    private func errorIcon(for kind: AgentToolSemanticKind, defaultIcon: String) -> String {
        switch kind {
        case .shellCommand, .swiftBuild, .swiftTest, .swiftRun, .xcodeBuild, .git, .packageManager, .python, .node:
            return "xmark.octagon"
        default:
            return defaultIcon
        }
    }

    private func containsCommand(_ normalized: String, _ command: String) -> Bool {
        startsShellSegment(normalized, prefixes: [command + " ", command + ";", command + "|", command + "&"]) || normalized == command || normalized.contains("&& \(command)")
    }

    private func startsShellSegment(_ normalized: String, prefixes: [String]) -> Bool {
        let segments = normalized
            .replacingOccurrences(of: "&&", with: ";")
            .replacingOccurrences(of: "||", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return segments.contains { segment in
            prefixes.contains { prefix in segment.hasPrefix(prefix) || segment == prefix.trimmingCharacters(in: .whitespaces) }
        }
    }

    private func canonicalShellTarget(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed
            .replacingOccurrences(of: "&&", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.hasPrefix("cd ") }) ?? trimmed
        return String(cleaned.prefix(80))
    }

    private func pathTarget(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return path == "." ? path : basename(path)
    }

    private func basename(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent.nilIfEmpty ?? path
    }

    private func parseJSONObject(_ json: String?) -> [String: Any] {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    private func compactJSON(_ json: String) -> String {
        trimmed(json) ?? ""
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value.nilIfEmpty }
        return nil
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        if let array = value as? [Any] { return array.count }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
